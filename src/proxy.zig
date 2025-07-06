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
    request_counter: std.atomic.Atomic(u64),

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
                .active_connections = std.atomic.Atomic(u32).init(0),
                .total_requests = std.atomic.Atomic(u64).init(0),
            };
            try upstreams.append(upstream);
        }

        return Self{
            .allocator = allocator,
            .upstreams = upstreams,
            .load_balancer = LoadBalancer.init(config.method),
            .health_checker = HealthChecker.init(allocator, config.health_check),
            .request_counter = std.atomic.Atomic(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.upstreams.items) |upstream| {
            self.allocator.free(upstream.address);
        }
        self.upstreams.deinit();
        self.health_checker.deinit();
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
        // Create HTTP/3 client connection using zquic
        var client = zquic.Http3Client.Http3Client.init(self.allocator);
        defer client.deinit();

        // Connect to upstream
        const addr = try std.fmt.allocPrint(self.allocator, "{s}:{}", .{ upstream.address, upstream.port });
        defer self.allocator.free(addr);

        try client.connect(addr);

        // Send request
        const upstream_response = try client.sendRequest(.{
            .method = request.method,
            .path = request.path,
            .headers = request.headers,
            .body = request.body,
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

        return ProxyResponse{
            .status = upstream_response.status,
            .body = try self.allocator.dupe(u8, upstream_response.body),
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

        return ProxyStats{
            .total_requests = self.request_counter.load(.SeqCst),
            .upstream_requests = total_requests,
            .active_connections = active_connections,
            .healthy_upstreams = healthy_count,
            .total_upstreams = @intCast(self.upstreams.items.len),
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
    active_connections: std.atomic.Atomic(u32),
    total_requests: std.atomic.Atomic(u64),
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
    round_robin_index: std.atomic.Atomic(u32),

    const Self = @This();

    pub fn init(method: LoadBalancingMethod) Self {
        return Self{
            .method = method,
            .round_robin_index = std.atomic.Atomic(u32).init(0),
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
};
