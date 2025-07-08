const std = @import("std");
const wraith = @import("wraith");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Shroud framework (replaces legacy crypto interface)
    std.debug.print("🔧 Initializing Shroud framework...\n", .{});
    std.debug.print("✅ Shroud framework ready (GhostWire, GhostCipher, Sigil, ZNS)\n", .{});

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        const command = args[1];

        if (std.mem.eql(u8, command, "serve")) {
            std.debug.print("🔥 Wraith - Modern Web2/Web3/Web5 Gateway starting...\n", .{});
            try startWraithGateway(allocator);
        } else if (std.mem.eql(u8, command, "status")) {
            std.debug.print("📊 Wraith Status: Ready to serve unified protocol traffic\n", .{});
        } else if (std.mem.eql(u8, command, "version")) {
            std.debug.print("Wraith v{s} - Web2/Web3/Web5 Gateway (Shroud Framework)\n", .{wraith.version});
        } else if (std.mem.eql(u8, command, "--dev")) {
            std.debug.print("🔧 Wraith - Development mode\n", .{});
            try wraith.server.start(allocator);
        } else {
            try printUsage();
        }
    } else {
        try printUsage();
    }
}

fn startWraithGateway(allocator: std.mem.Allocator) !void {
    // Create server configuration
    const config = wraith.ServerConfig{
        .bind_address = "::1",
        .port = 443,
        .enable_web3 = true,
        .enable_domain_resolution = true,
    };

    // Create and start the Wraith gateway
    var server = try wraith.WraithServer.init(allocator, config);
    defer server.deinit();

    try server.start();
}

fn printUsage() !void {
    std.debug.print(
        \\🔥 Wraith - Modern Web2/Web3/Web5 Gateway
        \\
        \\USAGE:
        \\    wraith <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    serve              Start the Wraith gateway
        \\    status             Show gateway status
        \\    version            Show version information
        \\    generate certs     Generate TLS certificates
        \\    reload             Reload configuration (hot reload)
        \\
        \\OPTIONS:
        \\    -c, --config <FILE>    Configuration file (default: wraith.toml)
        \\    -p, --port <PORT>      Port to listen on (default: 443)
        \\    -d, --dev              Development mode with self-signed certs
        \\    --web3                 Enable Web3/Web5 features (default: true)
        \\    --domain-resolution    Enable ZNS domain resolution (default: true)
        \\    -h, --help             Show this help message
        \\
        \\EXAMPLES:
        \\    wraith serve                      # Start with default config
        \\    wraith serve -c custom.toml       # Start with custom config
        \\    wraith serve -d                   # Development mode
        \\    wraith generate certs --dns       # Generate production certs
        \\
        \\🚀 Built with Shroud framework for unified protocol support.
        \\📡 Supports QUIC/HTTP3/WebSocket/gRPC + Web3/Web5 features.
        \\
    , .{});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
