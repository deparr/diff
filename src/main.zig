const std = @import("std");
const builtin = @import("builtin");
const zd = @import("zd");
const DiffAction = zd.DiffAction;
const Line = zd.Line;

const usage =
    \\Usage:
    \\  zd [options] [file_a] [file_b]
    \\
    \\  -h, --help                          Print this message and exit
    \\
    \\OPTIONS
    \\  -n, --line-numbers                  Print line numbers alongside diffs
    \\      --color                         Use colors to differentiate actions.
    \\
;

const Options = struct {
    file_a: ?[:0]const u8 = null,
    file_b: ?[:0]const u8 = null,
    color: bool = true,
    colors: Colors = .none,
    @"line-numbers": bool = false,

    const When = enum {
        always,
        never,
        auto,
    };

    const Colors = struct {
        reset: []const u8,
        line_numbers: []const u8,
        traversal: []const u8,
        insertion: []const u8,
        deletion: []const u8,

        const none: Colors = .{
            .reset = "",
            .line_numbers = "",
            .traversal = "",
            .insertion = "",
            .deletion = "",
        };

        const default: Colors = .{
            .reset = _reset,
            .line_numbers = gray,
            .traversal = fg,
            .insertion = green,
            .deletion = red,
        };

        const _reset = "\x1b[m";
        const red = "\x1b[31m";
        const green = "\x1b[32m";
        const yellow = "\x1b[33m";
        const blue = "\x1b[34m";
        const purple = "\x1b[35m";
        const cyan = "\x1b[36m";
        const gray = "\x1b[90m";
        const fg = "\x1b[37m";
    };
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const stderr = std.io.getStdErr().writer();
    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    var opts = Options{};
    var args = try std.process.argsWithAllocator(arena.allocator());
    _ = args.next();
    while (args.next()) |arg| {
        switch (optKind(arg)) {
            .short => {
                const str = arg[1..];
                for (str) |b| {
                    switch (b) {
                        'n' => opts.@"line-numbers" = true,
                        'h' => {
                            try stderr.writeAll(usage);
                            std.process.exit(0);
                        },
                        else => {
                            try stderr.print("Invalid option: '{c}'\n", .{b});
                            std.process.exit(1);
                        },
                    }
                }
            },
            .long => {
                var split = std.mem.splitScalar(u8, arg[2..], '=');
                const opt = split.first();
                const val = split.rest();
                if (eql(opt, "color")) {
                    opts.color = parseArgBool(val) orelse {
                        try stderr.print("Invalid color option: '{s}'\n", .{val});
                        std.process.exit(1);
                    };
                } else if (eql(opt, "line-numbers")) {
                    opts.@"line-numbers" = parseArgBool(val) orelse {
                        try stderr.print("Invalid boolean option: '{s}'\n", .{val});
                        std.process.exit(1);
                    };
                } else if (eql(opt, "help")) {
                    try stderr.writeAll(usage);
                    std.process.exit(0);
                } else {
                    try stderr.print("Invalid option: '{s}'\n", .{opt});
                    std.process.exit(1);
                }
            },
            .positional => {
                if (opts.file_a == null) {
                    opts.file_a = arg;
                } else if (opts.file_b == null) {
                    opts.file_b = arg;
                } else {
                    try stderr.writeAll("more than two diff targets\n");
                    std.process.exit(1);
                }
            },
        }
    }

    if (opts.color) {
        opts.colors = Options.Colors.default;
    }

    const file_a = opts.file_a orelse {
        try stderr.writeAll("missing diff target 'a'");
        std.process.exit(1);
    };
    const file_b = opts.file_b orelse {
        try stderr.writeAll("missing diff target 'b'");
        std.process.exit(1);
    };

    if (eql(file_a, file_b)) {
        return;
    }

    const a_bytes = try getFileOrStdin(arena.allocator(), file_a);
    const b_bytes = try getFileOrStdin(arena.allocator(), file_b);

    const a_lines = try zd.splitString(arena.allocator(), a_bytes);
    const b_lines = try zd.splitString(arena.allocator(), b_bytes);

    const diffs = try zd.diffLines(gpa, a_lines, b_lines);
    defer gpa.free(diffs);

    const writer = bw.writer();
    for (diffs) |diff| {
        const processed = try processDiff(diff, a_lines, b_lines);

        for (processed.lines, 0..) |line, offset| {
            const offseti32 = @as(i32, @intCast(offset));

            if (opts.@"line-numbers") {
                try writer.writeAll(opts.colors.line_numbers);
                if (processed.line_a_start) |a| {
                    try writer.print("{d:4}", .{@as(u32, @intCast(a + offseti32 + (processed.line_b_start orelse 0)))});
                } else {
                    try writer.writeByteNTimes(' ', 4);
                }
                try writer.writeByte('|');
                if (processed.line_b_start) |b| {
                    try writer.print("{d:4}", .{@as(u32, @intCast(b + offseti32))});
                } else {
                    try writer.writeByteNTimes(' ', 4);
                }
                try writer.writeAll(opts.colors.reset);

                try writer.writeByteNTimes(' ', 2);
            }

            const color, const tag: u8 = switch (processed.action) {
                .traversal => .{ opts.colors.traversal, ' ' },
                .insertion => .{ opts.colors.insertion, '+' },
                .deletion => .{ opts.colors.deletion, '-' },
            };

            try writer.print("{s}{c}{s}{s}\n", .{ color, tag, line.bytes, opts.colors.reset });
        }
    }

    try bw.flush();
}

fn getFileOrStdin(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const max_file_size = 1 << 26;
    if (eql(path, "-")) {
        return std.io.getStdIn().readToEndAlloc(allocator, max_file_size);
    }

    return std.fs.cwd().readFileAlloc(allocator, path, max_file_size);
}

const ProcessedDiff = struct {
    line_a_start: ?i32 = null,
    line_b_start: ?i32 = null,
    lines: []zd.Line,
    action: std.meta.Tag(zd.DiffAction),
};

fn processDiff(diff: DiffAction, a: []zd.Line, b: []zd.Line) !ProcessedDiff {
    return switch (diff) {
        .traversal => |trv| .{
            .line_a_start = @as(i32, @intCast(trv.a_idx)) - @as(i32, @intCast(trv.b_idx)),
            .line_b_start = @intCast(trv.b_idx),
            .lines = b[trv.b_idx .. trv.b_idx + trv.length],
            .action = .traversal,
        },
        .insertion => |ins| .{
            .line_b_start = @intCast(ins.b_idx),
            .lines = b[ins.b_idx .. ins.b_idx + ins.length],
            .action = .insertion,
        },
        .deletion => |del| .{
            .line_a_start = @intCast(del.a_idx),
            .lines = a[del.a_idx .. del.a_idx + del.length],
            .action = .deletion,
        },
    };
}

fn writeLineNumbers(a: ?usize, b: ?usize, writer: anytype) !void {
    if (a) |a_| {
        try writer.print("{d:4}", .{a_});
    } else {
        try writer.print("    ", .{});
    }
    try writer.print("|", .{});

    if (b) |b_| {
        try writer.print("{d:4}", .{b_});
    } else {
        try writer.print("    ", .{});
    }

    try writer.print("  ", .{});
}

fn parseArgBool(val: []const u8) ?bool {
    if (val.len == 0) return true;

    if (std.ascii.eqlIgnoreCase(val, "true")) return true;
    if (std.ascii.eqlIgnoreCase(val, "false")) return false;
    if (eql(val, "1")) return true;
    if (eql(val, "0")) return false;

    return null;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn optKind(a: []const u8) enum { short, long, positional } {
    if (std.mem.startsWith(u8, a, "--")) return .long;
    if (std.mem.startsWith(u8, a, "-") and a.len > 1) return .short;
    return .positional;
}
