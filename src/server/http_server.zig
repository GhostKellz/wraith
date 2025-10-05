const std = @import("std");
const zsync = @import("zsync");
const zhttp = @import("zhttp");
const signals = @import("signals.zig");
const forwarder_mod = @import("../proxy/forwarder.zig");

pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    addr: std.net.Address,
    upstream_addr: ?std.net.Address,
    forwarder: forwarder_mod.Forwarder,

    pub fn init(allocator: std.mem.Allocator, addr: std.net.Address, upstream_addr: ?std.net.Address) HttpServer {
        return .{
            .allocator = allocator,
            .addr = addr,
            .upstream_addr = upstream_addr,
            .forwarder = forwarder_mod.Forwarder.init(allocator),
        };
    }

    pub fn start(self: *HttpServer) !void {
        // Install signal handlers
        signals.installSignalHandlers();

        // TODO: Implement zhttp server
        // For MVP, just bind and accept connections
        var server = try self.addr.listen(.{
            .reuse_address = true,
        });
        defer server.deinit();

        // Get port for display
        const port = self.addr.getPort();
        std.debug.print("✓ Server listening on 0.0.0.0:{}\n", .{port});
        std.debug.print("✓ Press Ctrl+C for graceful shutdown\n", .{});

        while (!signals.shouldShutdown()) {
            // Check for reload signal
            if (signals.shouldReload()) {
                std.debug.print("✓ Reloading configuration...\n", .{});
                // TODO: Reload config with flare
                signals.resetReload();
            }

            // Accept connection (blocking)
            const conn = server.accept() catch |err| {
                // Handle shutdown during accept
                if (signals.shouldShutdown()) break;
                return err;
            };

            const client_port = conn.address.getPort();
            std.debug.print("✓ Accepted connection from 127.0.0.1:{}\n", .{client_port});

            // Proxy request to upstream if configured
            if (self.upstream_addr) |upstream| {
                self.forwarder.forward(conn.stream, upstream) catch |err| {
                    std.debug.print("✗ Proxy error: {any}\n", .{err});

                    // Send error response
                    const error_response =
                        \\HTTP/1.1 502 Bad Gateway
                        \\Content-Type: text/plain
                        \\Content-Length: 28
                        \\Server: Wraith/0.0.0
                        \\
                        \\502 Bad Gateway - Proxy Error
                    ;
                    _ = conn.stream.write(error_response) catch {};
                };
            } else {
                // No upstream configured, send default response
                const response =
                    \\HTTP/1.1 200 OK
                    \\Content-Type: text/plain
                    \\Content-Length: 45
                    \\Server: Wraith/0.0.0
                    \\
                    \\Wraith MVP - Your request was received! 🚀
                    \\
                ;

                _ = conn.stream.write(response) catch |err| {
                    std.debug.print("Failed to send response: {any}\n", .{err});
                };
            }

            conn.stream.close();
        }

        std.debug.print("\n✓ Server stopped gracefully\n", .{});
    }

    pub fn stop(self: *HttpServer) void {
        _ = self;
        std.debug.print("Stopping HTTP server\n", .{});
    }
};
