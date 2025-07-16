//! Wraith - Modern QUIC/HTTP3 Reverse Proxy
//! Built on zquic, ghostnet, zcrypto, and zsync for high-performance proxying
//! Includes TLS termination, routing, and access control

const std = @import("std");

// Import core dependencies
pub const zquic = @import("zquic");
pub const ghostnet = @import("ghostnet");
pub const zcrypto = @import("zcrypto");
pub const zsync = @import("zsync");

// Re-export core modules for convenience
pub const QuicServer = zquic.Server;
pub const Http3Handler = zquic.Http3;
pub const NetworkManager = ghostnet.Manager;
pub const TlsProvider = zcrypto.Tls;
pub const AsyncRuntime = zsync.Runtime;
pub const CryptoProvider = zcrypto.Provider;

// Wraith-specific proxy and routing functionality
pub const WraithProxy = struct {
    allocator: std.mem.Allocator,
    runtime: AsyncRuntime,
    network: NetworkManager,
    tls: TlsProvider,

    pub fn init(allocator: std.mem.Allocator) !WraithProxy {
        return WraithProxy{
            .allocator = allocator,
            .runtime = try AsyncRuntime.init(allocator),
            .network = try NetworkManager.init(allocator),
            .tls = try TlsProvider.init(allocator),
        };
    }

    pub fn deinit(self: *WraithProxy) void {
        self.tls.deinit();
        self.network.deinit();
        self.runtime.deinit();
    }

    pub fn setupTls(self: *WraithProxy, cert_path: []const u8, key_path: []const u8) !void {
        return self.tls.loadCertificate(cert_path, key_path);
    }

    pub fn addRoute(self: *WraithProxy, pattern: []const u8, upstream: []const u8) !void {
        // Route management functionality
        _ = self;
        _ = pattern;
        _ = upstream;
    }
};

// Legacy module re-exports (to be migrated)
pub const server = @import("server.zig");
pub const config = @import("config.zig");
pub const router = @import("router.zig");
pub const proxy = @import("proxy.zig");
pub const static_files = @import("static.zig");
pub const tls = @import("tls.zig");
pub const rate_limiter = @import("rate_limiter.zig");

// Re-export for convenience
pub const Config = config.Config;
pub const Router = router.Router;
pub const StaticFileServer = static_files.StaticFileServer;
pub const ServerConfig = server.ServerConfig;
pub const WraithServer = server.WraithServer;
pub const ProxyConfig = server.ProxyConfig;

// Version information
pub const version = "0.5.0";

test {
    std.testing.refAllDecls(@This());
}
