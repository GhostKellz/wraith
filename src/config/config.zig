const std = @import("std");
const flare = @import("flare");

pub const ServerConfig = struct {
    listen: []const []const u8,
    listen_tls: []const []const u8,
    worker_threads: usize,
};

pub const TlsConfig = struct {
    cert_dir: []const u8,
    acme_enabled: bool,
    acme_email: ?[]const u8,
};

pub const LoggingConfig = struct {
    level: []const u8,
    format: []const u8,
    output: []const u8,
};

pub const UpstreamServer = struct {
    host: []const u8,
    weight: u32,
};

pub const UpstreamConfig = struct {
    name: []const u8,
    servers: []const UpstreamServer,
    load_balancing: []const u8,
    health_check_interval: u64,
    health_check_timeout: u64,
    health_check_path: []const u8,
};

pub const RouteConfig = struct {
    host: []const u8,
    path: []const u8,
    upstream: []const u8,
};

pub const Config = struct {
    server: ServerConfig,
    tls: TlsConfig,
    logging: LoggingConfig,
    upstreams: []const UpstreamConfig,
    routes: []const RouteConfig,

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        _ = allocator;
        _ = path;
        // TODO: Implement flare TOML parsing
        // For MVP, return default config
        const listen_addrs = [_][]const u8{"0.0.0.0:9000"};
        const listen_tls_addrs = [_][]const u8{};

        const upstream_servers = [_]UpstreamServer{
            UpstreamServer{
                .host = "http://127.0.0.1:8080",
                .weight = 1,
            },
        };

        const upstreams = [_]UpstreamConfig{
            UpstreamConfig{
                .name = "localhost",
                .servers = &upstream_servers,
                .load_balancing = "round_robin",
                .health_check_interval = 10,
                .health_check_timeout = 5,
                .health_check_path = "/",
            },
        };

        const routes = [_]RouteConfig{
            RouteConfig{
                .host = "*",
                .path = "/",
                .upstream = "localhost",
            },
        };

        return Config{
            .server = ServerConfig{
                .listen = &listen_addrs,
                .listen_tls = &listen_tls_addrs,
                .worker_threads = 0,
            },
            .tls = TlsConfig{
                .cert_dir = "/etc/wraith/certs",
                .acme_enabled = false,
                .acme_email = null,
            },
            .logging = LoggingConfig{
                .level = "info",
                .format = "json",
                .output = "stdout",
            },
            .upstreams = &upstreams,
            .routes = &routes,
        };
    }

    pub fn validate(self: *const Config) !void {
        if (self.server.listen.len == 0 and self.server.listen_tls.len == 0) {
            return error.NoListenAddresses;
        }
    }
};
