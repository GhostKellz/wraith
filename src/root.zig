//! Wraith - Modern Web2/Web3/Web5 Gateway
//! Built on the Shroud framework for unified QUIC/HTTP3/WebSocket/gRPC support
//! Includes crypto primitives, domain resolution, and identity management

const std = @import("std");

// Import Shroud framework
pub const shroud = @import("shroud");

// Re-export Shroud modules for convenience
pub const GhostWire = shroud.GhostWire;
pub const GhostCipher = shroud.GhostCipher;
pub const Sigil = shroud.Sigil;
pub const ZNS = shroud.ZNS;
pub const Keystone = shroud.Keystone;
pub const Guardian = shroud.Guardian;
pub const Covenant = shroud.Covenant;
pub const ShadowCraft = shroud.ShadowCraft;
pub const GWallet = shroud.GWallet;

// Wraith-specific wrappers and extensions
pub const WraithGateway = struct {
    ghostwire: GhostWire,
    sigil: Sigil,
    zns: ZNS,

    pub fn init(allocator: std.mem.Allocator) !WraithGateway {
        return WraithGateway{
            .ghostwire = try GhostWire.init(allocator),
            .sigil = try Sigil.init(allocator),
            .zns = try ZNS.init(allocator),
        };
    }

    pub fn deinit(self: *WraithGateway) void {
        self.ghostwire.deinit();
        self.sigil.deinit();
        self.zns.deinit();
    }

    pub fn resolve_domain(self: *WraithGateway, domain: []const u8) ![]const u8 {
        return self.zns.resolve(domain);
    }

    pub fn authenticate_request(self: *WraithGateway, request: anytype) !bool {
        return self.sigil.verify(request);
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

// Version information
pub const version = "0.2.0";

test {
    std.testing.refAllDecls(@This());
}
