const std = @import("std");
const diff = @import("diff.zig");

fn lines(gpa: std.mem.Allocator, str: []const u8) ![][]const u8 {
    const line_count = std.mem.count(u8, str, "\n") + 1;
    const lines_buf = try gpa.alloc([]const u8, line_count);
    var iter = std.mem.splitScalar(u8, str, '\n');
    var i: usize = 0;
    while (iter.next()) |line| {
        lines_buf[i] = line;
        i += 1;
    }
    return lines_buf;
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_allocator.allocator();
    const a = @embedFile("a.gd");
    const b = @embedFile("b.gd");

    const a_lines = try lines(gpa, a);
    const b_lines = try lines(gpa, b);

    for (a_lines, b_lines) |a_line, b_line| {
        std.debug.print("diffing <<<< {s}\n", .{ a_line });
        std.debug.print("diffing >>>> {s}\n", .{ b_line });
        const line_diff = try diff.diff(gpa, a_line, b_line);
        defer line_diff.deinit();

        for (line_diff.items) |action| {
            switch (action) {
                // .traversal => |trv| std.debug.print("=\t{s}\n", .{a[trv.a_idx .. trv.a_idx + trv.length]}),
                .traversal => {},
                .insertion => |ins| std.debug.print("\x1b[32m+\t'{s}'\x1b[m\n", .{b_line[ins.b_idx .. ins.b_idx + ins.length]}),
                .deletion => |del| std.debug.print("\x1b[31m-\t'{s}'\x1b[m\n", .{a_line[del.a_idx .. del.a_idx + del.length]}),
            }
        }
    }
}
