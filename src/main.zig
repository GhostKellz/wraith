const std = @import("std");
const cli = @import("cli/commands.zig");
const config_mod = @import("config/config.zig");
const server_mod = @import("server/http_server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments
    const args = try cli.parseArgs(allocator);

    std.debug.print("Wraith v0.0.1 - Next-Gen Web Server & Reverse Proxy\n", .{});
    std.debug.print("Command: {s}\n", .{@tagName(args.command)});
    std.debug.print("Config: {s}\n\n", .{args.config_path});

    switch (args.command) {
        .serve => {
            // Load configuration
            const cfg = try config_mod.Config.loadFromFile(allocator, args.config_path);
            try cfg.validate();

            std.debug.print("Loaded configuration:\n", .{});
            std.debug.print("  Listen addresses: {d}\n", .{cfg.server.listen.len});
            std.debug.print("  Worker threads: {d}\n", .{cfg.server.worker_threads});
            std.debug.print("  Log level: {s}\n", .{cfg.logging.level});
            std.debug.print("  Log format: {s}\n\n", .{cfg.logging.format});

            // Parse first listen address
            if (cfg.server.listen.len > 0) {
                const listen_addr = cfg.server.listen[0];
                std.debug.print("Parsing address: {s}\n", .{listen_addr});

                // Parse host:port format
                const colon_idx = std.mem.indexOf(u8, listen_addr, ":") orelse return error.InvalidListenAddress;
                const host = listen_addr[0..colon_idx];
                const port_str = listen_addr[colon_idx + 1 ..];
                const port = try std.fmt.parseInt(u16, port_str, 10);

                const addr = try std.net.Address.parseIp(host, port);

                // Parse upstream address if configured
                var upstream_addr: ?std.net.Address = null;
                if (cfg.upstreams.len > 0 and cfg.upstreams[0].servers.len > 0) {
                    const upstream_url = cfg.upstreams[0].servers[0].host;
                    std.debug.print("Upstream: {s}\n", .{upstream_url});

                    // Simple parsing for http://host:port format
                    if (std.mem.startsWith(u8, upstream_url, "http://")) {
                        const without_proto = upstream_url[7..];
                        const upstream_colon = std.mem.indexOf(u8, without_proto, ":") orelse return error.InvalidUpstreamAddress;
                        const upstream_host = without_proto[0..upstream_colon];
                        const upstream_port_str = without_proto[upstream_colon + 1 ..];
                        const upstream_port = try std.fmt.parseInt(u16, upstream_port_str, 10);

                        upstream_addr = try std.net.Address.parseIp(upstream_host, upstream_port);
                        std.debug.print("Parsed upstream: {s}:{}\n", .{ upstream_host, upstream_port });
                    }
                }

                // Start HTTP server
                var http_server = server_mod.HttpServer.init(allocator, addr, upstream_addr);
                try http_server.start();
            } else {
                std.debug.print("No listen addresses configured\n", .{});
                return error.NoListenAddresses;
            }
        },
        .version => {
            // Version from build.zig.zon
            const version = "0.0.0"; // TODO: Read from build.zig.zon at compile time
            std.debug.print("Wraith v{s}\n", .{version});
            std.debug.print("Built with Zig 0.16.0-dev\n", .{});
            std.debug.print("Next-Gen Web Server & Reverse Proxy\n", .{});
        },
        .test_config => {
            const cfg = try config_mod.Config.loadFromFile(allocator, args.config_path);
            try cfg.validate();
            std.debug.print("Configuration is valid!\n", .{});
        },
        else => {
            std.debug.print("Command not yet implemented: {s}\n", .{@tagName(args.command)});
            return error.NotImplemented;
        },
    }
}
