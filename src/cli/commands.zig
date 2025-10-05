const std = @import("std");
const flash = @import("flash");

pub const Command = enum {
    serve,
    test_config,
    reload,
    stop,
    quit,
    status,
    version,
};

pub fn parseArgs(allocator: std.mem.Allocator) !struct {
    command: Command,
    config_path: []const u8,
} {
    _ = allocator; // TODO: Use allocator when implementing flash CLI parsing
    // For MVP, return default values
    return .{
        .command = .serve,
        .config_path = "wraith.toml",
    };
}
