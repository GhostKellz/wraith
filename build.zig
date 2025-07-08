//! Wraith - Modern Web Gateway with Shroud Framework
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add Shroud framework dependency
    const shroud_dep = b.dependency("shroud", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the main Wraith module
    const mod = b.addModule("wraith", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "shroud", .module = shroud_dep.module("shroud") },
        },
    });

    // Create the Wraith executable
    const exe = b.addExecutable(.{
        .name = "wraith",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wraith", .module = mod },
                .{ .name = "shroud", .module = shroud_dep.module("shroud") },
            },
        }),
    });

    // Install the executable
    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run Wraith server");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // Pass arguments to the application
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test steps
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Development helpers
    const dev_step = b.step("dev", "Run in development mode with hot reload");
    const dev_cmd = b.addRunArtifact(exe);
    dev_cmd.addArg("--dev");
    dev_step.dependOn(&dev_cmd.step);

    const check_step = b.step("check", "Check code without building");
    const check_exe = b.addExecutable(.{
        .name = "check-wraith",
        .root_module = exe.root_module,
    });
    check_step.dependOn(&check_exe.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
