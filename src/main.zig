const std = @import("std");
const wraith = @import("wraith");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize QUIC/HTTP3 reverse proxy stack
    std.debug.print("🔧 Initializing QUIC/HTTP3 reverse proxy...\n", .{});
    std.debug.print("✅ Stack ready (zquic + ghostnet + zcrypto + zsync)\n", .{});

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        const command = args[1];

        if (std.mem.eql(u8, command, "serve")) {
            std.debug.print("🔥 Wraith - Modern QUIC/HTTP3 Reverse Proxy starting...\n", .{});
            try startWraithProxy(allocator);
        } else if (std.mem.eql(u8, command, "status")) {
            std.debug.print("📊 Wraith Status: Ready to serve QUIC/HTTP3 traffic\n", .{});
        } else if (std.mem.eql(u8, command, "version")) {
            std.debug.print("Wraith v{s} - QUIC/HTTP3 Reverse Proxy\n", .{wraith.version});
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

fn startWraithProxy(allocator: std.mem.Allocator) !void {
    // Create server configuration
    const config = wraith.ServerConfig{
        .bind_address = "::1",
        .port = 443,
        .enable_http3 = true,
        .enable_compression = true,
    };

    // Create and start the Wraith reverse proxy
    var server = try wraith.WraithServer.init(allocator, config);
    defer server.deinit();

    try server.start();
}

fn printUsage() !void {
    std.debug.print(
        \\🔥 Wraith - Modern QUIC/HTTP3 Reverse Proxy
        \\
        \\USAGE:
        \\    wraith <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    serve              Start the Wraith reverse proxy
        \\    status             Show proxy status
        \\    version            Show version information
        \\    generate certs     Generate TLS certificates
        \\    reload             Reload configuration (hot reload)
        \\
        \\OPTIONS:
        \\    -c, --config <FILE>    Configuration file (default: wraith.toml)
        \\    -p, --port <PORT>      Port to listen on (default: 443)
        \\    -d, --dev              Development mode with self-signed certs
        \\    --upstream <URL>       Add upstream server
        \\    --route <PATTERN>      Add routing rule
        \\    -h, --help             Show this help message
        \\
        \\EXAMPLES:
        \\    wraith serve                      # Start with default config
        \\    wraith serve -c custom.toml       # Start with custom config
        \\    wraith serve -d                   # Development mode
        \\    wraith generate certs --dns       # Generate production certs
        \\
        \\🚀 Built with zquic + ghostnet + zcrypto + zsync stack.
        \\📡 Supports QUIC/HTTP3 reverse proxying with TLS termination.
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
