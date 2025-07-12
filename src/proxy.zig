//! Advanced Reverse Proxy module for Wraith
//! Handles HTTP/3 reverse proxy with load balancing and health checks

const std = @import("std");
const root = @import("root.zig");
const zquic = root.zquic;
const tokioZ = root.tokioZ;

const Allocator = std.mem.Allocator;

pub const ProxyManager = struct {
    allocator: Allocator,
    upstreams: std.ArrayList(Upstream),
    load_balancer: LoadBalancer,
    health_checker: HealthChecker,
    request_counter: std.atomic.Value(u64),
    connection_pool: ConnectionPool,

    const Self = @This();

    pub fn init(allocator: Allocator, config: ProxyConfig) !Self {
        var upstreams = std.ArrayList(Upstream).init(allocator);

        // Initialize upstreams from config
        for (config.upstreams) |upstream_config| {
            const upstream = Upstream{
                .id = upstream_config.name,
                .address = try allocator.dupe(u8, upstream_config.address),
                .port = upstream_config.port,
                .weight = upstream_config.weight,
                .max_fails = upstream_config.max_fails,
                .fail_timeout = upstream_config.fail_timeout,
                .is_backup = upstream_config.backup,
                .current_fails = 0,
                .last_fail_time = 0,
                .is_healthy = true,
                .active_connections = std.atomic.Value(u32).init(0),
                .total_requests = std.atomic.Value(u64).init(0),
            };
            try upstreams.append(upstream);
        }

        return Self{
            .allocator = allocator,
            .upstreams = upstreams,
            .load_balancer = LoadBalancer.init(config.method),
            .health_checker = HealthChecker.init(allocator, config.health_check),
            .request_counter = std.atomic.Value(u64).init(0),
            .connection_pool = try ConnectionPool.init(allocator, config.connection_pool),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.upstreams.items) |upstream| {
            self.allocator.free(upstream.address);
        }
        self.upstreams.deinit();
        self.health_checker.deinit();
        self.connection_pool.deinit();
    }

    pub fn forwardRequest(self: *Self, request: ProxyRequest) !ProxyResponse {
        // Select upstream using load balancing
        const upstream = self.selectUpstream(request) orelse {
            return ProxyResponse{
                .status = 502,
                .body = "Bad Gateway: No healthy upstreams available",
                .headers = std.StringHashMap([]const u8).init(self.allocator),
            };
        };

        // Increment request counter
        _ = self.request_counter.fetchAdd(1, .SeqCst);
        _ = upstream.total_requests.fetchAdd(1, .SeqCst);
        _ = upstream.active_connections.fetchAdd(1, .SeqCst);
        defer _ = upstream.active_connections.fetchSub(1, .SeqCst);

        // Forward request to upstream
        const response = self.sendToUpstream(upstream, request) catch |err| {
            self.markUpstreamFailed(upstream);
            switch (err) {
                error.ConnectionRefused => return ProxyResponse{
                    .status = 502,
                    .body = "Bad Gateway: Connection refused by upstream",
                    .headers = std.StringHashMap([]const u8).init(self.allocator),
                },
                error.Timeout => return ProxyResponse{
                    .status = 504,
                    .body = "Gateway Timeout: Upstream did not respond in time",
                    .headers = std.StringHashMap([]const u8).init(self.allocator),
                },
                else => return err,
            }
        };

        std.log.info("Proxied request to {s}:{} - Status: {}", .{ upstream.address, upstream.port, response.status });
        return response;
    }

    fn selectUpstream(self: *Self, request: ProxyRequest) ?*Upstream {
        const healthy_upstreams = self.getHealthyUpstreams();
        if (healthy_upstreams.len == 0) {
            return null;
        }

        return self.load_balancer.select(healthy_upstreams, request);
    }

    fn getHealthyUpstreams(self: *Self) []*Upstream {
        var healthy = std.ArrayList(*Upstream).init(self.allocator);
        defer healthy.deinit();

        const now = std.time.timestamp();

        for (self.upstreams.items) |*upstream| {
            // Check if upstream is within fail timeout
            if (upstream.current_fails >= upstream.max_fails) {
                if (now - upstream.last_fail_time < upstream.fail_timeout) {
                    continue; // Still in fail timeout
                } else {
                    // Reset fail count after timeout
                    upstream.current_fails = 0;
                    upstream.is_healthy = true;
                }
            }

            if (upstream.is_healthy) {
                healthy.append(upstream) catch continue;
            }
        }

        return healthy.toOwnedSlice() catch &.{};
    }

    fn sendToUpstream(self: *Self, upstream: *Upstream, request: ProxyRequest) !ProxyResponse {
        // Get pooled connection for zero-copy operations
        const addr = try std.fmt.allocPrint(self.allocator, "{s}:{}", .{ upstream.address, upstream.port });
        defer self.allocator.free(addr);

        var client = try self.connection_pool.getConnection(addr);

        // Send request with zero-copy optimization
        const upstream_response = try client.sendRequestZeroCopy(.{
            .method = request.method,
            .path = request.path,
            .headers = request.headers,
            .body = request.body,
            .use_post_quantum = true, // Enable ML-KEM-768/SLH-DSA
        });

        var response_headers = std.StringHashMap([]const u8).init(self.allocator);

        // Copy response headers (filtering out hop-by-hop headers)
        var header_iter = upstream_response.headers.iterator();
        while (header_iter.next()) |header| {
            const header_name_lower = try std.ascii.allocLowerString(self.allocator, header.key_ptr.*);
            defer self.allocator.free(header_name_lower);

            // Skip hop-by-hop headers
            if (isHopByHopHeader(header_name_lower)) continue;

            try response_headers.put(try self.allocator.dupe(u8, header.key_ptr.*), try self.allocator.dupe(u8, header.value_ptr.*));
        }

        // Add proxy headers
        try response_headers.put(try self.allocator.dupe(u8, "x-proxied-by"), try self.allocator.dupe(u8, "Wraith/0.1.0"));

        // Return connection to pool for reuse
        self.connection_pool.returnConnection(addr, client);

        return ProxyResponse{
            .status = upstream_response.status,
            .body = upstream_response.body, // Zero-copy - no duplication needed
            .headers = response_headers,
        };
    }

    fn markUpstreamFailed(self: *Self, upstream: *Upstream) void {
        _ = self;
        upstream.current_fails += 1;
        upstream.last_fail_time = std.time.timestamp();

        if (upstream.current_fails >= upstream.max_fails) {
            upstream.is_healthy = false;
            std.log.warn("Upstream {s}:{} marked as unhealthy", .{ upstream.address, upstream.port });
        }
    }

    fn isHopByHopHeader(header_name: []const u8) bool {
        const hop_by_hop_headers = [_][]const u8{
            "connection",
            "keep-alive",
            "proxy-authenticate",
            "proxy-authorization",
            "te",
            "trailers",
            "transfer-encoding",
            "upgrade",
        };

        for (hop_by_hop_headers) |hop_header| {
            if (std.mem.eql(u8, header_name, hop_header)) {
                return true;
            }
        }
        return false;
    }

    pub fn getStats(self: *Self) ProxyStats {
        var total_requests: u64 = 0;
        var healthy_count: u32 = 0;
        var active_connections: u32 = 0;

        for (self.upstreams.items) |upstream| {
            total_requests += upstream.total_requests.load(.SeqCst);
            active_connections += upstream.active_connections.load(.SeqCst);
            if (upstream.is_healthy) {
                healthy_count += 1;
            }
        }

        const pool_stats = self.connection_pool.getStats();

        return ProxyStats{
            .total_requests = self.request_counter.load(.SeqCst),
            .upstream_requests = total_requests,
            .active_connections = active_connections,
            .healthy_upstreams = healthy_count,
            .total_upstreams = @intCast(self.upstreams.items.len),
            .pool_hits = pool_stats.hits,
            .pool_misses = pool_stats.misses,
        };
    }
};

pub const Upstream = struct {
    id: []const u8,
    address: []const u8,
    port: u16,
    weight: u32,
    max_fails: u32,
    fail_timeout: u32,
    is_backup: bool,

    // Runtime state
    current_fails: u32,
    last_fail_time: i64,
    is_healthy: bool,
    active_connections: std.atomic.Value(u32),
    total_requests: std.atomic.Value(u64),
};

pub const LoadBalancingMethod = enum {
    round_robin,
    least_connections,
    ip_hash,
    random,
    weighted,
};

pub const LoadBalancer = struct {
    method: LoadBalancingMethod,
    round_robin_index: std.atomic.Value(u32),

    const Self = @This();

    pub fn init(method: LoadBalancingMethod) Self {
        return Self{
            .method = method,
            .round_robin_index = std.atomic.Value(u32).init(0),
        };
    }

    pub fn select(self: *Self, upstreams: []*Upstream, request: ProxyRequest) ?*Upstream {
        if (upstreams.len == 0) return null;

        return switch (self.method) {
            .round_robin => self.selectRoundRobin(upstreams),
            .least_connections => self.selectLeastConnections(upstreams),
            .ip_hash => self.selectByIpHash(upstreams, request.client_ip),
            .random => self.selectRandom(upstreams),
            .weighted => self.selectWeighted(upstreams),
        };
    }

    fn selectRoundRobin(self: *Self, upstreams: []*Upstream) *Upstream {
        const index = self.round_robin_index.fetchAdd(1, .SeqCst) % upstreams.len;
        return upstreams[index];
    }

    fn selectLeastConnections(self: *Self, upstreams: []*Upstream) *Upstream {
        _ = self;
        var best_upstream = upstreams[0];
        var min_connections = best_upstream.active_connections.load(.SeqCst);

        for (upstreams[1..]) |upstream| {
            const connections = upstream.active_connections.load(.SeqCst);
            if (connections < min_connections) {
                min_connections = connections;
                best_upstream = upstream;
            }
        }

        return best_upstream;
    }

    fn selectByIpHash(self: *Self, upstreams: []*Upstream, client_ip: ?[]const u8) *Upstream {
        _ = self;
        if (client_ip) |ip| {
            const hash = std.hash_map.hashString(ip);
            const index = hash % upstreams.len;
            return upstreams[index];
        }
        // Fallback to first upstream
        return upstreams[0];
    }

    fn selectRandom(self: *Self, upstreams: []*Upstream) *Upstream {
        _ = self;
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();
        const index = random.int(usize) % upstreams.len;
        return upstreams[index];
    }

    fn selectWeighted(self: *Self, upstreams: []*Upstream) *Upstream {
        _ = self;
        var total_weight: u32 = 0;
        for (upstreams) |upstream| {
            total_weight += upstream.weight;
        }

        if (total_weight == 0) return upstreams[0];

        var prng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        const random = prng.random();
        var target = random.int(u32) % total_weight;

        for (upstreams) |upstream| {
            if (target < upstream.weight) {
                return upstream;
            }
            target -= upstream.weight;
        }

        return upstreams[upstreams.len - 1];
    }
};

pub const HealthChecker = struct {
    allocator: Allocator,
    config: HealthCheckConfig,

    const Self = @This();

    pub fn init(allocator: Allocator, config: HealthCheckConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn checkUpstream(self: *Self, upstream: *Upstream) !bool {
        if (!self.config.enabled) {
            return true; // Always healthy if health checks disabled
        }

        // Create HTTP client for health check
        var client = zquic.Http3Client.Http3Client.init(self.allocator);
        defer client.deinit();

        const addr = try std.fmt.allocPrint(self.allocator, "{s}:{}", .{ upstream.address, upstream.port });
        defer self.allocator.free(addr);

        // Connect with timeout
        client.connect(addr) catch |err| {
            std.log.warn("Health check failed for {s}: {}", .{ addr, err });
            return false;
        };

        // Send health check request
        const response = client.sendRequest(.{
            .method = "GET",
            .path = self.config.path,
            .headers = std.StringHashMap([]const u8).init(self.allocator),
            .body = "",
        }) catch |err| {
            std.log.warn("Health check request failed for {s}: {}", .{ addr, err });
            return false;
        };

        const is_healthy = response.status == self.config.expected_status;

        if (is_healthy) {
            std.log.debug("Health check passed for {s}", .{addr});
        } else {
            std.log.warn("Health check failed for {s}: status {}", .{ addr, response.status });
        }

        return is_healthy;
    }
};

pub const ProxyConfig = struct {
    upstreams: []const UpstreamConfig,
    method: LoadBalancingMethod = .round_robin,
    health_check: HealthCheckConfig = .{},
    connection_pool: ConnectionPoolConfig = .{},
};

pub const UpstreamConfig = struct {
    name: []const u8,
    address: []const u8,
    port: u16,
    weight: u32 = 1,
    max_fails: u32 = 3,
    fail_timeout: u32 = 30,
    backup: bool = false,
};

pub const HealthCheckConfig = struct {
    enabled: bool = true,
    interval: u32 = 10,
    timeout: u32 = 5,
    path: []const u8 = "/health",
    expected_status: u16 = 200,
};

pub const ProxyRequest = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    client_ip: ?[]const u8,
};

pub const ProxyResponse = struct {
    status: u16,
    body: []const u8,
    headers: std.StringHashMap([]const u8),
};

pub const ProxyStats = struct {
    total_requests: u64,
    upstream_requests: u64,
    active_connections: u32,
    healthy_upstreams: u32,
    total_upstreams: u32,
    pool_hits: u64,
    pool_misses: u64,
};

// High-performance connection pool for HTTP/3 clients
pub const ConnectionPool = struct {
    allocator: Allocator,
    connections: std.HashMap([]const u8, *PooledConnection, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    max_connections_per_host: u32,
    max_idle_time: u64,
    hits: std.atomic.Value(u64),
    misses: std.atomic.Value(u64),

    const Self = @This();

    const PooledConnection = struct {
        client: *zquic.Http3Client.Http3Client,
        last_used: i64,
        is_healthy: bool,
    };

    pub fn init(allocator: Allocator, config: ConnectionPoolConfig) !Self {
        return Self{
            .allocator = allocator,
            .connections = std.HashMap([]const u8, *PooledConnection, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .max_connections_per_host = config.max_connections_per_host,
            .max_idle_time = config.max_idle_time,
            .hits = std.atomic.Value(u64).init(0),
            .misses = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.client.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.connections.deinit();
    }

    pub fn getConnection(self: *Self, addr: []const u8) !*zquic.Http3Client.Http3Client {
        const now = std.time.timestamp();

        // Try to get existing connection
        if (self.connections.get(addr)) |pooled| {
            if (pooled.is_healthy and (now - pooled.last_used) < self.max_idle_time) {
                pooled.last_used = now;
                _ = self.hits.fetchAdd(1, .SeqCst);
                return pooled.client;
            } else {
                // Connection expired or unhealthy, remove it
                _ = self.connections.remove(addr);
                pooled.client.deinit();
                self.allocator.destroy(pooled);
            }
        }

        // Create new connection
        _ = self.misses.fetchAdd(1, .SeqCst);
        const client = try self.allocator.create(zquic.Http3Client.Http3Client);
        client.* = zquic.Http3Client.Http3Client.init(self.allocator);
        
        // Configure for high performance and post-quantum crypto
        try client.setConfig(.{
            .enable_post_quantum = true,
            .congestion_control = .blockchain_optimized,
            .zero_copy_enabled = true,
            .max_concurrent_streams = 1000,
        });

        try client.connect(addr);

        const pooled = try self.allocator.create(PooledConnection);
        pooled.* = PooledConnection{
            .client = client,
            .last_used = now,
            .is_healthy = true,
        };

        const addr_copy = try self.allocator.dupe(u8, addr);
        try self.connections.put(addr_copy, pooled);

        return client;
    }

    pub fn returnConnection(self: *Self, addr: []const u8, client: *zquic.Http3Client.Http3Client) void {
        _ = client;
        if (self.connections.getPtr(addr)) |pooled| {
            pooled.*.last_used = std.time.timestamp();
        }
    }

    pub fn getStats(self: *Self) struct { hits: u64, misses: u64 } {
        return .{
            .hits = self.hits.load(.SeqCst),
            .misses = self.misses.load(.SeqCst),
        };
    }
};

pub const ConnectionPoolConfig = struct {
    max_connections_per_host: u32 = 100,
    max_idle_time: u64 = 300, // 5 minutes
};
