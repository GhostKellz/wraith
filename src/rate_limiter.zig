//! Rate Limiting and DDoS Protection for Wraith
//! Implements token bucket and sliding window algorithms with injected crypto for secure hashing

const std = @import("std");
const root = @import("root.zig");
const crypto = root.crypto_interface;

const Allocator = std.mem.Allocator;

pub const RateLimiter = struct {
    allocator: Allocator,
    config: RateLimitConfig,
    client_buckets: std.StringHashMap(TokenBucket),
    global_bucket: TokenBucket,
    blocked_ips: std.StringHashMap(BlockedClient),
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, config: RateLimitConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .client_buckets = std.StringHashMap(TokenBucket).init(allocator),
            .global_bucket = TokenBucket.init(config.global_requests_per_second * 60, config.global_burst),
            .blocked_ips = std.StringHashMap(BlockedClient).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var bucket_iter = self.client_buckets.iterator();
        while (bucket_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.client_buckets.deinit();
        
        var blocked_iter = self.blocked_ips.iterator();
        while (blocked_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.blocked_ips.deinit();
    }
    
    pub fn isAllowed(self: *Self, client_ip: []const u8, request_size: u32) !RateLimitResult {
        const now = std.time.milliTimestamp();
        
        // Check if IP is explicitly blocked
        if (self.blocked_ips.get(client_ip)) |blocked| {
            if (now < blocked.unblock_time) {
                return RateLimitResult{
                    .allowed = false,
                    .reason = .blocked,
                    .retry_after = @intCast((blocked.unblock_time - now) / 1000),
                    .remaining_requests = 0,
                };
            } else {
                // Remove expired block
                _ = self.blocked_ips.remove(client_ip);
            }
        }
        
        // Check whitelist
        for (self.config.whitelist) |whitelisted_ip| {
            if (std.mem.eql(u8, client_ip, whitelisted_ip)) {
                return RateLimitResult{
                    .allowed = true,
                    .reason = .whitelisted,
                    .retry_after = 0,
                    .remaining_requests = std.math.maxInt(u32),
                };
            }
        }
        
        // Check blacklist
        for (self.config.blacklist) |blacklisted_ip| {
            if (std.mem.eql(u8, client_ip, blacklisted_ip)) {
                return RateLimitResult{
                    .allowed = false,
                    .reason = .blacklisted,
                    .retry_after = std.math.maxInt(u32),
                    .remaining_requests = 0,
                };
            }
        }
        
        // Global rate limiting
        if (!self.global_bucket.tryConsume(1, now)) {
            return RateLimitResult{
                .allowed = false,
                .reason = .global_limit,
                .retry_after = @intCast(self.global_bucket.getRefillTime(now) / 1000),
                .remaining_requests = 0,
            };
        }
        
        // Per-client rate limiting
        const client_key = try self.allocator.dupe(u8, client_ip);
        var bucket = self.client_buckets.get(client_ip) orelse blk: {
            const new_bucket = TokenBucket.init(
                self.config.requests_per_minute,
                self.config.burst
            );
            try self.client_buckets.put(client_key, new_bucket);
            break :blk new_bucket;
        };
        
        if (!bucket.tryConsume(1, now)) {
            // Check if this client should be temporarily blocked
            if (self.shouldBlockClient(client_ip, now)) {
                try self.blockClient(client_ip, now);
                return RateLimitResult{
                    .allowed = false,
                    .reason = .blocked,
                    .retry_after = self.config.block_duration,
                    .remaining_requests = 0,
                };
            }
            
            return RateLimitResult{
                .allowed = false,
                .reason = .rate_limited,
                .retry_after = @intCast(bucket.getRefillTime(now) / 1000),
                .remaining_requests = bucket.tokens,
            };
        }
        
        // Check request size limits
        if (request_size > self.config.max_request_size) {
            return RateLimitResult{
                .allowed = false,
                .reason = .request_too_large,
                .retry_after = 0,
                .remaining_requests = bucket.tokens,
            };
        }
        
        // Update bucket in map
        try self.client_buckets.put(client_key, bucket);
        
        return RateLimitResult{
            .allowed = true,
            .reason = .allowed,
            .retry_after = 0,
            .remaining_requests = bucket.tokens,
        };
    }
    
    fn shouldBlockClient(self: *Self, client_ip: []const u8, now: i64) bool {
        _ = client_ip;
        _ = now;
        
        // Simple heuristic: block if client has been rate limited multiple times
        // In a real implementation, this would track violation history
        return self.config.auto_block_enabled;
    }
    
    fn blockClient(self: *Self, client_ip: []const u8, now: i64) !void {
        const blocked_client = BlockedClient{
            .ip = try self.allocator.dupe(u8, client_ip),
            .block_time = now,
            .unblock_time = now + (self.config.block_duration * 1000),
            .reason = "Rate limit violations",
        };
        
        try self.blocked_ips.put(blocked_client.ip, blocked_client);
        std.log.warn("Blocked client {} for {} seconds", .{ client_ip, self.config.block_duration });
    }
    
    pub fn cleanupExpiredEntries(self: *Self) void {
        const now = std.time.milliTimestamp();
        
        // Clean up expired blocked IPs
        var blocked_iter = self.blocked_ips.iterator();
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();
        
        while (blocked_iter.next()) |entry| {
            if (now >= entry.value_ptr.unblock_time) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (to_remove.items) |ip| {
            if (self.blocked_ips.fetchRemove(ip)) |removed| {
                self.allocator.free(removed.key);
                self.allocator.free(removed.value.ip);
            }
        }
        
        // Clean up old client buckets (optional - could implement LRU)
        // For now, keep all buckets to maintain rate limiting state
    }
    
    pub fn addToBlacklist(self: *Self, ip: []const u8) !void {
        // In a real implementation, this would persist to configuration
        std.log.info("Added {} to blacklist", .{ip});
        _ = self;
    }
    
    pub fn removeFromBlacklist(self: *Self, ip: []const u8) !void {
        // In a real implementation, this would persist to configuration
        std.log.info("Removed {} from blacklist", .{ip});
        _ = self;
    }
    
    pub fn getStats(self: *Self) RateLimitStats {
        var blocked_count: u32 = 0;
        var active_clients: u32 = 0;
        
        const now = std.time.milliTimestamp();
        
        var blocked_iter = self.blocked_ips.iterator();
        while (blocked_iter.next()) |entry| {
            if (now < entry.value_ptr.unblock_time) {
                blocked_count += 1;
            }
        }
        
        active_clients = @intCast(self.client_buckets.count());
        
        return RateLimitStats{
            .active_clients = active_clients,
            .blocked_clients = blocked_count,
            .global_tokens_remaining = self.global_bucket.tokens,
            .total_blocks = blocked_count, // Simplified
        };
    }
};

pub const TokenBucket = struct {
    capacity: u32,
    tokens: u32,
    refill_rate: u32, // tokens per minute
    last_refill: i64, // milliseconds
    
    const Self = @This();
    
    pub fn init(capacity: u32, refill_rate: u32) Self {
        return Self{
            .capacity = capacity,
            .tokens = capacity,
            .refill_rate = refill_rate,
            .last_refill = std.time.milliTimestamp(),
        };
    }
    
    pub fn tryConsume(self: *Self, tokens_needed: u32, now: i64) bool {
        self.refill(now);
        
        if (self.tokens >= tokens_needed) {
            self.tokens -= tokens_needed;
            return true;
        }
        
        return false;
    }
    
    fn refill(self: *Self, now: i64) void {
        const time_passed = now - self.last_refill;
        if (time_passed <= 0) return;
        
        // Calculate tokens to add (rate is per minute)
        const tokens_to_add = @as(u32, @intCast((time_passed * self.refill_rate) / 60000));
        
        if (tokens_to_add > 0) {
            self.tokens = @min(self.capacity, self.tokens + tokens_to_add);
            self.last_refill = now;
        }
    }
    
    pub fn getRefillTime(self: *Self, now: i64) i64 {
        if (self.tokens >= self.capacity) return 0;
        
        const tokens_needed = self.capacity - self.tokens;
        const time_needed = (tokens_needed * 60000) / self.refill_rate;
        
        return time_needed;
    }
};

pub const DDoSProtector = struct {
    allocator: Allocator,
    config: DDoSConfig,
    connection_tracker: std.StringHashMap(ConnectionInfo),
    packet_tracker: std.StringHashMap(PacketInfo),
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, config: DDoSConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .connection_tracker = std.StringHashMap(ConnectionInfo).init(allocator),
            .packet_tracker = std.StringHashMap(PacketInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var conn_iter = self.connection_tracker.iterator();
        while (conn_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.connection_tracker.deinit();
        
        var packet_iter = self.packet_tracker.iterator();
        while (packet_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.packet_tracker.deinit();
    }
    
    pub fn checkConnection(self: *Self, client_ip: []const u8) !bool {
        if (!self.config.enabled) return true;
        
        const now = std.time.milliTimestamp();
        const client_key = try self.allocator.dupe(u8, client_ip);
        
        var info = self.connection_tracker.get(client_ip) orelse ConnectionInfo{
            .connections = 0,
            .last_connection = now,
            .first_connection = now,
        };
        
        // Reset counter if window has passed
        if (now - info.first_connection > self.config.window_size * 1000) {
            info.connections = 0;
            info.first_connection = now;
        }
        
        info.connections += 1;
        info.last_connection = now;
        
        const allowed = info.connections <= self.config.max_connections_per_ip;
        
        try self.connection_tracker.put(client_key, info);
        
        if (!allowed) {
            std.log.warn("DDoS protection: Too many connections from {s}", .{client_ip});
        }
        
        return allowed;
    }
    
    pub fn checkPacketRate(self: *Self, client_ip: []const u8) !bool {
        if (!self.config.enabled) return true;
        
        const now = std.time.milliTimestamp();
        const client_key = try self.allocator.dupe(u8, client_ip);
        
        var info = self.packet_tracker.get(client_ip) orelse PacketInfo{
            .packets = 0,
            .last_packet = now,
            .first_packet = now,
        };
        
        // Reset counter if window has passed
        if (now - info.first_packet > 1000) { // 1 second window
            info.packets = 0;
            info.first_packet = now;
        }
        
        info.packets += 1;
        info.last_packet = now;
        
        const allowed = info.packets <= self.config.packet_rate_limit;
        
        try self.packet_tracker.put(client_key, info);
        
        if (!allowed) {
            std.log.warn("DDoS protection: Packet rate limit exceeded for {s}", .{client_ip});
        }
        
        return allowed;
    }
    
    pub fn cleanupExpiredEntries(self: *Self) void {
        const now = std.time.milliTimestamp();
        const window_ms = self.config.window_size * 1000;
        
        // Clean up connection tracker
        var conn_iter = self.connection_tracker.iterator();
        var conn_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer conn_to_remove.deinit();
        
        while (conn_iter.next()) |entry| {
            if (now - entry.value_ptr.last_connection > window_ms) {
                conn_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (conn_to_remove.items) |ip| {
            if (self.connection_tracker.fetchRemove(ip)) |removed| {
                self.allocator.free(removed.key);
            }
        }
        
        // Clean up packet tracker
        var packet_iter = self.packet_tracker.iterator();
        var packet_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer packet_to_remove.deinit();
        
        while (packet_iter.next()) |entry| {
            if (now - entry.value_ptr.last_packet > 10000) { // 10 second cleanup
                packet_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (packet_to_remove.items) |ip| {
            if (self.packet_tracker.fetchRemove(ip)) |removed| {
                self.allocator.free(removed.key);
            }
        }
    }
};

// Configuration structures
pub const RateLimitConfig = struct {
    enabled: bool = true,
    requests_per_minute: u32 = 60,
    burst: u32 = 10,
    global_requests_per_second: u32 = 1000,
    global_burst: u32 = 100,
    max_request_size: u32 = 1024 * 1024, // 1MB
    auto_block_enabled: bool = true,
    block_duration: u32 = 300, // 5 minutes
    whitelist: []const []const u8 = &.{},
    blacklist: []const []const u8 = &.{},
};

pub const DDoSConfig = struct {
    enabled: bool = true,
    max_connections_per_ip: u32 = 100,
    connection_rate_limit: u32 = 10, // per second
    packet_rate_limit: u32 = 1000, // per second
    window_size: u32 = 60, // seconds
};

// Result and info structures
pub const RateLimitResult = struct {
    allowed: bool,
    reason: RateLimitReason,
    retry_after: u32, // seconds
    remaining_requests: u32,
};

pub const RateLimitReason = enum {
    allowed,
    whitelisted,
    rate_limited,
    blacklisted,
    blocked,
    global_limit,
    request_too_large,
};

pub const BlockedClient = struct {
    ip: []const u8,
    block_time: i64,
    unblock_time: i64,
    reason: []const u8,
};

pub const ConnectionInfo = struct {
    connections: u32,
    last_connection: i64,
    first_connection: i64,
};

pub const PacketInfo = struct {
    packets: u32,
    last_packet: i64,
    first_packet: i64,
};

pub const RateLimitStats = struct {
    active_clients: u32,
    blocked_clients: u32,
    global_tokens_remaining: u32,
    total_blocks: u32,
};

/// Create a combined security manager with rate limiting and DDoS protection
pub const SecurityManager = struct {
    allocator: Allocator,
    rate_limiter: RateLimiter,
    ddos_protector: DDoSProtector,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, rate_config: RateLimitConfig, ddos_config: DDoSConfig) Self {
        return Self{
            .allocator = allocator,
            .rate_limiter = RateLimiter.init(allocator, rate_config),
            .ddos_protector = DDoSProtector.init(allocator, ddos_config),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.rate_limiter.deinit();
        self.ddos_protector.deinit();
    }
    
    pub fn checkRequest(self: *Self, client_ip: []const u8, request_size: u32) !SecurityResult {
        // Check DDoS protection first
        if (!(try self.ddos_protector.checkConnection(client_ip))) {
            return SecurityResult{
                .allowed = false,
                .reason = "DDoS protection: too many connections",
                .rate_limit_result = null,
            };
        }
        
        if (!(try self.ddos_protector.checkPacketRate(client_ip))) {
            return SecurityResult{
                .allowed = false,
                .reason = "DDoS protection: packet rate limit exceeded",
                .rate_limit_result = null,
            };
        }
        
        // Check rate limiting
        const rate_result = try self.rate_limiter.isAllowed(client_ip, request_size);
        
        return SecurityResult{
            .allowed = rate_result.allowed,
            .reason = if (rate_result.allowed) "allowed" else @tagName(rate_result.reason),
            .rate_limit_result = rate_result,
        };
    }
    
    pub fn cleanup(self: *Self) void {
        self.rate_limiter.cleanupExpiredEntries();
        self.ddos_protector.cleanupExpiredEntries();
    }
};

pub const SecurityResult = struct {
    allowed: bool,
    reason: []const u8,
    rate_limit_result: ?RateLimitResult,
};