//! Wraith - Modern QUIC/HTTP3 Reverse Proxy
//! Built on zquic, tokioZ, and zcrypto for maximum performance

const std = @import("std");

// Import our high-performance libraries (managed by build system)
pub const zquic = @import("zquic");
pub const tokioZ = @import("tokioZ");
pub const zcrypto = @import("zcrypto");

// Core modules
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

// Version information
pub const version = "0.1.0";

test {
    std.testing.refAllDecls(@This());
}
