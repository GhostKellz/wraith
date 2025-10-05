const std = @import("std");
const zhttp = @import("zhttp");

/// HTTP request forwarder
pub const Forwarder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Forwarder {
        return .{ .allocator = allocator };
    }

    /// Forward an HTTP request to an upstream server
    pub fn forward(
        self: *Forwarder,
        client_stream: std.net.Stream,
        upstream_addr: std.net.Address,
    ) !void {
        _ = self;

        // TODO: Implement with zhttp
        // For MVP, establish connection and forward raw bytes

        // Connect to upstream
        const upstream_stream = try std.net.tcpConnectToAddress(upstream_addr);
        defer upstream_stream.close();

        std.debug.print("✓ Connected to upstream {any}\n", .{upstream_addr});

        // Read request from client
        var buf: [4096]u8 = undefined;
        const n = try client_stream.read(&buf);

        if (n == 0) {
            return error.ClientClosedConnection;
        }

        std.debug.print("✓ Received {d} bytes from client\n", .{n});

        // Forward request to upstream
        _ = try upstream_stream.writeAll(buf[0..n]);

        std.debug.print("✓ Forwarded request to upstream\n", .{});

        // Read response from upstream
        const response_n = try upstream_stream.read(&buf);

        if (response_n == 0) {
            return error.UpstreamClosedConnection;
        }

        std.debug.print("✓ Received {d} bytes from upstream\n", .{response_n});

        // Forward response to client
        _ = try client_stream.writeAll(buf[0..response_n]);

        std.debug.print("✓ Forwarded response to client\n", .{});
    }

    /// Copy headers from request to upstream request
    pub fn copyHeaders(
        self: *Forwarder,
        source_headers: []const u8,
        dest_headers: *std.ArrayList(u8),
    ) !void {
        _ = self;
        // TODO: Parse and copy headers
        // For now, just copy everything
        try dest_headers.appendSlice(source_headers);
    }

    /// Copy body from request to upstream request
    pub fn copyBody(
        self: *Forwarder,
        source_stream: std.net.Stream,
        dest_stream: std.net.Stream,
        content_length: usize,
    ) !void {
        _ = self;

        var buf: [8192]u8 = undefined;
        var remaining = content_length;

        while (remaining > 0) {
            const to_read = @min(remaining, buf.len);
            const n = try source_stream.read(buf[0..to_read]);

            if (n == 0) break;

            _ = try dest_stream.writeAll(buf[0..n]);
            remaining -= n;
        }
    }
};
