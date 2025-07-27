const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const Insertion = struct {
    b_idx: usize,
    length: usize,
};

pub const Deletion = struct {
    a_idx: usize,
    length: usize,
};

pub const Traverse = struct {
    a_idx: usize,
    b_idx: usize,
    length: usize,
};

/// Tracks:
///     insertions from `b`
///     removals from `a`
///     traversals, no changes made to `a`
pub const DiffAction = union(enum) {
    /// an insertion into a
    insertion: Insertion,
    deletion: Deletion,
    traversal: Traverse,
};

pub const DiffActionList = std.ArrayList(DiffAction);

const DiffBuilder = struct {
    allocator: Allocator,
    list: DiffActionList,

    fn init(allocator: Allocator) !DiffBuilder {
        return .{
            .allocator = allocator,
            .list = try .initCapacity(allocator, 16),
        };
    }

    fn pushTraversal(self: *DiffBuilder, a_idx: usize, b_idx: usize) !void {
        if (self.list.getLastOrNull()) |action| switch (action) {
            .traversal => |trv| {
                // if new traversal is a continuation of previous, append it
                if (trv.a_idx == a_idx + 1 and trv.b_idx == b_idx + 1) {
                    self.list.items[self.list.items.len - 1] = .{
                        .traversal = .{
                            .a_idx = trv.a_idx - 1,
                            .b_idx = trv.b_idx - 1,
                            .length = trv.length + 1,
                        },
                    };
                    return;
                }
            },
            else => {},
        };

        try self.list.append(.{
            .traversal = .{
                .a_idx = a_idx,
                .b_idx = b_idx,
                .length = 1,
            },
        });
    }

    fn pushDeletion(self: *DiffBuilder, a_idx: usize) !void {
        if (self.list.getLastOrNull()) |action| switch (action) {
            .deletion => |del| {
                // if new deletion is a continuation of previous, append it
                if (del.a_idx == a_idx + 1) {
                    self.list.items[self.list.items.len - 1] = .{
                        .deletion = .{
                            .a_idx = del.a_idx - 1,
                            .length = del.length + 1,
                        },
                    };
                    return;
                }
            },
            else => {},
        };

        try self.list.append(.{
            .deletion = .{
                .a_idx = a_idx,
                .length = 1,
            },
        });
    }

    fn pushInsertion(self: *DiffBuilder, b_idx: usize) !void {
        if (self.list.getLastOrNull()) |action| switch (action) {
            .insertion => |ins| {
                // if new insertion is a continuation of previous, append it
                if (ins.b_idx == b_idx + 1) {
                    self.list.items[self.list.items.len - 1] = .{
                        .insertion = .{
                            .b_idx = ins.b_idx - 1,
                            .length = ins.length + 1,
                        },
                    };
                    return;
                }
            },
            else => {},
        };

        try self.list.append(.{
            .insertion = .{
                .b_idx = b_idx,
                .length = 1,
            },
        });
    }
};

pub const MyersTrace = struct {
    data: []i32,
    allocator: Allocator,

    pub fn init(allocator: Allocator, a_len: usize, b_len: usize) !MyersTrace {
        const max_d = a_len + b_len;

        // todo maybe add a max_size param to this
        const len = (max_d + 1) * (max_d + 2) / 2;

        const data = try allocator.alloc(i32, len);
        @memset(data, 0);

        return .{ .data = data, .allocator = allocator };
    }

    pub fn get(self: *const MyersTrace, d: i32, k: i32) i32 {
        assert(k >= -d and k <= d);

        const k_start = @divTrunc(d * (d + 1), 2);
        const k_u = k + d;
        const idx: usize = @intCast(k_start + @divTrunc(k_u, 2));

        return self.data[idx];
    }

    /// pointers are only invalidated after calling `deinit()`
    pub fn get_ptr(self: *const MyersTrace, d: i32, k: i32) *i32 {
        assert(k >= -d and k <= d);

        const k_start = @divTrunc(d * (d + 1), 2);
        const k_u = k + d;
        const idx: usize = @intCast(k_start + @divTrunc(k_u, 2));

        return &self.data[idx];
    }

    pub fn deinit(self: *MyersTrace) void {
        self.allocator.free(self.data);
    }
};

pub fn diff(gpa: Allocator, a: []const u8, b: []const u8) !DiffActionList {
    const max_dist = a.len + b.len;

    if (max_dist == 0) {
        var res: DiffActionList = try .initCapacity(gpa, 1);
        res.appendAssumeCapacity(.{ .traversal = .{ .a_idx = 0, .b_idx = 0, .length = 0 } });
        return res;
    }

    var trace: MyersTrace = try .init(gpa, a.len, b.len);
    defer trace.deinit();
    var min_edit_distance: i32 = 0;
    const a_len_i32: i32 = @intCast(a.len);
    const b_len_i32: i32 = @intCast(b.len);

    var d: i32 = 0;
    outer: while (d <= max_dist) : (d += 1) {
        var k = -d;
        while (k <= d) : (k += 2) {
            var x: i32 = undefined;
            if (d == 0) {
                x = 0;
            } else if (k == -d) {
                x = trace.get(d - 1, k + 1);
            } else if (k == d) {
                x = trace.get(d - 1, k - 1) + 1;
            } else {
                const left = trace.get(d - 1, k - 1);
                const right = trace.get(d - 1, k + 1);
                x = if (left < right) right else left + 1;
            }

            var y = x - k;

            assert(x >= 0);
            assert(y >= 0);
            while (x < a_len_i32 and y < b_len_i32 and a[@intCast(x)] == b[@intCast(y)]) {
                x += 1;
                y += 1;
            }

            trace.get_ptr(d, k).* = x;

            if (x >= a_len_i32 and y >= b_len_i32) {
                // we found the minimal d value
                min_edit_distance = d;
                break :outer;
            }
        }
    }

    var builder: DiffBuilder = try .init(gpa);
    var x: i32 = @intCast(a.len);
    var y: i32 = @intCast(b.len);

    // todo isn't his the same as breaking above?
    // d = min_edit_distance;
    // backtrack through the trace to build the diff
    while (d >= 0) : (d -= 1) {
        const k = x - y;
        var prev_k: i32 = undefined;
        if (d == 0) {
            prev_k = 0;
        } else if (k == -d) {
            prev_k = k + 1;
        } else if (k == d) {
            prev_k = k - 1;
        } else {
            const left = trace.get(d - 1, k - 1);
            const right = trace.get(d - 1, k + 1);
            prev_k = if (left < right) k + 1 else k - 1;
        }

        const prev_x = if (d == 0) 0 else trace.get(d - 1, prev_k);
        const prev_y = prev_x - prev_k;

        while (x > prev_x and y > prev_y) {
            x -= 1;
            y = @max(y - 1, 0);
            // record a traversal
            try builder.pushTraversal(@intCast(x), @intCast(y));
        }

        if (d > 0) {
            // horizonal move, deletion
            if (prev_y == y) {
                try builder.pushDeletion(@intCast(prev_x));
                // vertical move, insertion
            } else if (prev_x == x) {
                try builder.pushInsertion(@intCast(prev_y));
            } else {
                return error.UnexpectedNoDiffAction;
            }
        }

        x = prev_x;
        y = prev_y;
    }

    std.mem.reverse(DiffAction, builder.list.items);
    return builder.list;
}

test "diff_same" {
    const actions = try diff(std.testing.allocator, "ABCDEF", "ABCDEF");
    defer actions.deinit();

    try std.testing.expect(actions.items.len == 1);
    const action = actions.items[0];
    try std.testing.expectEqualDeep(action, DiffAction{ .traversal = .{
        .a_idx = 0,
        .b_idx = 0,
        .length = 6,
    } });
}
