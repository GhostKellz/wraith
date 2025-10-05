const std = @import("std");

/// Global shutdown flag
var should_shutdown = std.atomic.Value(bool).init(false);
var should_reload = std.atomic.Value(bool).init(false);

/// Signal handler state
var signal_handlers_installed = false;

/// Install signal handlers for graceful shutdown and hot reload
pub fn installSignalHandlers() void {
    if (signal_handlers_installed) return;

    const empty_sigset = std.mem.zeroes(std.posix.sigset_t);

    // SIGTERM, SIGINT -> graceful shutdown
    std.posix.sigaction(std.posix.SIG.TERM, &std.posix.Sigaction{
        .handler = .{ .handler = handleShutdownSignal },
        .mask = empty_sigset,
        .flags = 0,
    }, null);

    std.posix.sigaction(std.posix.SIG.INT, &std.posix.Sigaction{
        .handler = .{ .handler = handleShutdownSignal },
        .mask = empty_sigset,
        .flags = 0,
    }, null);

    // SIGHUP -> hot reload
    std.posix.sigaction(std.posix.SIG.HUP, &std.posix.Sigaction{
        .handler = .{ .handler = handleReloadSignal },
        .mask = empty_sigset,
        .flags = 0,
    }, null);

    signal_handlers_installed = true;
    std.debug.print("✓ Signal handlers installed (SIGTERM, SIGINT, SIGHUP)\n", .{});
}

fn handleShutdownSignal(_: c_int) callconv(.c) void {
    should_shutdown.store(true, .seq_cst);
}

fn handleReloadSignal(_: c_int) callconv(.c) void {
    should_reload.store(true, .seq_cst);
}

/// Check if shutdown has been requested
pub fn shouldShutdown() bool {
    return should_shutdown.load(.seq_cst);
}

/// Check if reload has been requested
pub fn shouldReload() bool {
    return should_reload.load(.seq_cst);
}

/// Reset reload flag after processing
pub fn resetReload() void {
    should_reload.store(false, .seq_cst);
}
