const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const lib_mod = b.addModule("zd", .{
        .root_source_file = b.path("src/diff.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const test_step = b.step("test", "Run tests");
    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    const exe_mod = b.addModule("zd-bin", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("zd", lib_mod);

    const exe = b.addExecutable(.{
        .name = "zd",
        .root_module = exe_mod,
    });

    const check_only = b.option(bool, "check", "check only") orelse false;

    const check_step = b.step("check", "check only");
    check_step.dependOn(&exe.step);

    if (check_only) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);
    }
}
