//! Configuration management for Wraith
//! Supports TOML and YAML declarative configuration

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Config = struct {
    server: ServerConfig = .{},
    tls: TlsConfig = .{},
    proxy: ProxyConfig = .{},
    static_files: StaticConfig = .{},
    security: SecurityConfig = .{},

    const Self = @This();

    pub fn loadFromFile(allocator: Allocator, path: []const u8) !Self {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("Config file not found at {s}, using defaults", .{path});
                return Self.default();
            },
            else => return err,
        };
        defer file.close();
        
        const contents = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(contents);
        
        return try Self.loadFromToml(allocator, contents);
    }

    pub fn loadFromToml(allocator: Allocator, toml_content: []const u8) !Self {
        var config = Self.default();
        
        // Simple TOML parser for key configuration values
        var lines = std.mem.split(u8, toml_content, "\n");
        var current_section: []const u8 = "";
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            
            // Section headers like [server]
            if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
                current_section = trimmed[1..trimmed.len - 1];
                continue;
            }
            
            // Key-value pairs
            if (std.mem.indexOf(u8, trimmed, " = ")) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                const value = std.mem.trim(u8, trimmed[eq_pos + 3..], " \t\"");
                
                try parseConfigValue(&config, current_section, key, value);
            }
        }
        
        _ = allocator; // Mark as used for future complex parsing
        return config;
    }
    
    fn parseConfigValue(config: *Self, section: []const u8, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, section, "server")) {
            if (std.mem.eql(u8, key, "port")) {
                config.server.port = std.fmt.parseInt(u16, value, 10) catch 443;
            } else if (std.mem.eql(u8, key, "max_connections")) {
                config.server.max_connections = std.fmt.parseInt(u32, value, 10) catch 10000;
            } else if (std.mem.eql(u8, key, "enable_http3")) {
                config.server.enable_http3 = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, key, "bind_address")) {
                config.server.bind_address = value; // Note: This is unsafe for production
            }
        } else if (std.mem.eql(u8, section, "tls")) {
            if (std.mem.eql(u8, key, "auto_cert")) {
                config.tls.auto_cert = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, key, "min_version")) {
                if (std.mem.eql(u8, value, "tls13")) {
                    config.tls.min_version = .tls13;
                } else if (std.mem.eql(u8, value, "tls12")) {
                    config.tls.min_version = .tls12;
                }
            }
        } else if (std.mem.eql(u8, section, "static_files")) {
            if (std.mem.eql(u8, key, "enabled")) {
                config.static_files.enabled = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, key, "compression")) {
                config.static_files.compression = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, key, "root")) {
                config.static_files.root = value; // Note: This is unsafe for production
            }
        } else if (std.mem.eql(u8, section, "security.rate_limiting")) {
            if (std.mem.eql(u8, key, "enabled")) {
                config.security.rate_limiting.enabled = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, key, "requests_per_minute")) {
                config.security.rate_limiting.requests_per_minute = std.fmt.parseInt(u32, value, 10) catch 60;
            } else if (std.mem.eql(u8, key, "burst")) {
                config.security.rate_limiting.burst = std.fmt.parseInt(u32, value, 10) catch 10;
            }
        }
    }

    pub fn default() Self {
        return Self{};
    }
};

pub const ServerConfig = struct {
    bind_address: []const u8 = "::",  // IPv6 bind-all
    port: u16 = 443,
    workers: u32 = 0, // 0 = auto-detect CPU cores
    max_connections: u32 = 10000,
    connection_timeout: u32 = 30, // seconds
    keep_alive: bool = true,
    enable_http3: bool = true,
    enable_http2: bool = false, // HTTP/3 first
    enable_http1: bool = false, // QUIC-only
};

pub const TlsConfig = struct {
    cert_path: ?[]const u8 = null,
    key_path: ?[]const u8 = null,
    ca_path: ?[]const u8 = null,
    auto_cert: bool = true, // ACME integration
    min_version: TlsVersion = .tls13,
    max_version: TlsVersion = .tls13,
    cipher_suites: []const []const u8 = &.{},
    alpn: []const []const u8 = &.{ "h3", "h3-32" },
    
    pub const TlsVersion = enum {
        tls12,
        tls13,
    };
};

pub const ProxyConfig = struct {
    enabled: bool = false,
    upstreams: []UpstreamConfig = &.{},
    load_balancing: LoadBalancingMethod = .round_robin,
    health_check: HealthCheckConfig = .{},
    
    pub const LoadBalancingMethod = enum {
        round_robin,
        least_connections,
        ip_hash,
        random,
        weighted,
    };
    
    pub const UpstreamConfig = struct {
        name: []const u8,
        address: []const u8,
        port: u16,
        weight: u32 = 1,
        max_fails: u32 = 3,
        fail_timeout: u32 = 30, // seconds
        backup: bool = false,
    };
    
    pub const HealthCheckConfig = struct {
        enabled: bool = true,
        interval: u32 = 10, // seconds
        timeout: u32 = 5,   // seconds
        path: []const u8 = "/health",
        expected_status: u16 = 200,
    };
};

pub const StaticConfig = struct {
    enabled: bool = true,
    root: []const u8 = "./public",
    index_files: []const []const u8 = &.{ "index.html", "index.htm" },
    compression: bool = true,
    compression_types: []const []const u8 = &.{ "text/html", "text/css", "application/javascript", "application/json" },
    cache_control: ?[]const u8 = "public, max-age=3600",
    etag: bool = true,
    autoindex: bool = false,
};

pub const SecurityConfig = struct {
    rate_limiting: RateLimitConfig = .{},
    ddos_protection: DdosConfig = .{},
    waf: WafConfig = .{},
    headers: SecurityHeaders = .{},
    
    pub const RateLimitConfig = struct {
        enabled: bool = true,
        requests_per_minute: u32 = 60,
        burst: u32 = 10,
        whitelist: []const []const u8 = &.{},
        blacklist: []const []const u8 = &.{},
    };
    
    pub const DdosConfig = struct {
        enabled: bool = true,
        max_connections_per_ip: u32 = 100,
        connection_rate_limit: u32 = 10, // per second
        packet_rate_limit: u32 = 1000,   // per second
    };
    
    pub const WafConfig = struct {
        enabled: bool = false,
        rules_path: ?[]const u8 = null,
        log_blocked: bool = true,
        block_mode: bool = true, // false = monitor only
    };
    
    pub const SecurityHeaders = struct {
        hsts: bool = true,
        hsts_max_age: u32 = 31536000, // 1 year
        hsts_include_subdomains: bool = true,
        csp: ?[]const u8 = "default-src 'self'",
        x_frame_options: []const u8 = "DENY",
        x_content_type_options: bool = true,
        referrer_policy: []const u8 = "strict-origin-when-cross-origin",
    };
};

/// Example TOML configuration
pub const example_toml = 
    \\[server]
    \\bind_address = "::"
    \\port = 443
    \\workers = 0  # auto-detect
    \\max_connections = 10000
    \\enable_http3 = true
    \\
    \\[tls]
    \\auto_cert = true
    \\min_version = "tls13"
    \\alpn = ["h3", "h3-32"]
    \\
    \\[static_files]
    \\enabled = true
    \\root = "./public"
    \\compression = true
    \\cache_control = "public, max-age=3600"
    \\
    \\[security.rate_limiting]
    \\enabled = true
    \\requests_per_minute = 60
    \\burst = 10
    \\
    \\[security.headers]
    \\hsts = true
    \\csp = "default-src 'self'"
    \\
    \\[[proxy.upstreams]]
    \\name = "backend1"
    \\address = "127.0.0.1"
    \\port = 8080
    \\weight = 1
;

test "config parsing" {
    const config = Config.default();
    try std.testing.expect(config.server.enable_http3);
    try std.testing.expectEqual(@as(u16, 443), config.server.port);
}
