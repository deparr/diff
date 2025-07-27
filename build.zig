const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe_mod = b.addModule("diff", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "diff",
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
