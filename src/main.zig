const std = @import("std");
const libdiff = @import("diff.zig");
const DiffAction = libdiff.DiffAction;

fn lines(gpa: std.mem.Allocator, str: []const u8) ![]Line {
    const line_count = std.mem.count(u8, str, "\n") + 1;
    const lines_buf = try gpa.alloc(Line, line_count);
    var iter = std.mem.splitScalar(u8, str, '\n');
    var i: usize = 0;
    while (iter.next()) |line| {
        lines_buf[i] = .{ .bytes = line };
        i += 1;
    }
    return lines_buf;
}

const Line = struct {
    bytes: []const u8,

    pub fn equal(self: Line, other: Line) bool {
        return std.mem.eql(u8, self.bytes, other.bytes);
    }
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_allocator.allocator();
    const a = @embedFile("a.gd");
    const b = @embedFile("b.gd");

    const a_lines = try lines(gpa, a);
    const b_lines = try lines(gpa, b);

    const diffs = try libdiff.diff(Line, gpa, a_lines, b_lines);
    for (diffs) |diff| switch (diff) {
        .traversal => |trv| {
            for (trv.a_idx..trv.a_idx + trv.length) |i| {
                std.debug.print(" {s}\n", .{ a_lines[i].bytes });
            }
        },
        .insertion => |ins| {
            for (ins.b_idx..ins.b_idx + ins.length) |i| {
                std.debug.print("\x1b[32m+ {s}\x1b[m\n", .{ b_lines[i].bytes });
            }
        },
        .deletion => |del| {
            for (del.a_idx..del.a_idx + del.length) |i| {
                std.debug.print("\x1b[31m- {s}\x1b[m\n", .{ a_lines[i].bytes });
            }
        },
    };

    for (diffs) |diff| {
        const processed = try process_diff(diff, a_lines, b_lines);
        _ = processed;
    }
}

fn process_diff(diff: DiffAction, a: []Line, b: []Line) !void {
    switch (diff) {
        .traversal => |trv| {
            const a_idx_offset = @as(i32, @intCast(trv.a_idx)) - @as(i32, @intCast(trv.b_idx));

            for (b[trv.b_idx..trv.b_idx + trv.length], trv.b_idx..) |line, i| {
                write_line_numbers(@intCast(a_idx_offset + @as(i32, @intCast(i))), i);
                std.debug.print("{s}\n", .{ line.bytes });
            }
        },
        .insertion => |ins| {
            for (b[ins.b_idx..ins.b_idx + ins.length], ins.b_idx..) |line, i| {
                write_line_numbers(null, i);
                std.debug.print("\x1b[32m+{s}\x1b[m\n", .{ line.bytes });
            }
        },
        .deletion => |del| {
            for (a[del.a_idx..del.a_idx + del.length], del.a_idx..) |line, i| {
                write_line_numbers(i, null);
                std.debug.print("\x1b[31m-{s}\x1b[m\n", .{ line.bytes });
            }
        },
    }
}

fn write_line_numbers(a: ?usize, b: ?usize) void {
    if (a) |a_| {
        std.debug.print("{d:4}", .{ a_ });
    } else {
        std.debug.print("    ", .{});
    }
    std.debug.print("|", .{});

    if (b) |b_| {
        std.debug.print("{d:4}", .{ b_ });
    } else {
        std.debug.print("    ", .{});
    }

    std.debug.print("  ", .{});
}
