const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Row = [3]u8;
const Rows = [5]Row;
const Vec2 = @Vector(2, i8);

pub fn parse(ctx: fw.p.ParseContext) ?Rows {
    const p = fw.p;
    const d = p.digit;
    const row = p.allOf(Row, .{ d, d, d }).trailed(p.literal('A'));
    const row_nl = row.trailed(p.nl);
    return p.allOf(Rows, .{ row_nl, row_nl, row_nl, row_nl, row }).execute(ctx);
}

pub fn pt1(rows: Rows, allocator: Allocator) !u64 {
    return pts(2, rows, allocator);
}

pub fn pt2(rows: Rows, allocator: Allocator) !u64 {
    return pts(25, rows, allocator);
}

fn pts(keypads: u8, rows: Rows, allocator: Allocator) !u64 {
    var visitor = Visitor.init(allocator);
    defer visitor.deinit();
    var res: u64 = 0;
    for (rows) |row| {
        const len = try visitor.calcSeqLen(row, keypads);
        const n = @as(usize, row[0]) * 100 + row[1] * 10 + row[2];
        res += len * n;
    }
    return res;
}

const Axis = enum { horizontal, vertical };
const Move = struct {
    delta: Vec2,
    first_axis: Axis,
};

const Visitor = struct {
    const Self = @This();

    const CacheKey = struct { u8, Move };
    const Cache = std.AutoHashMap(CacheKey, u64);

    cache: Cache,

    fn init(allocator: Allocator) Self {
        return .{ .cache = Cache.init(allocator) };
    }
    fn deinit(self: *Self) void {
        self.cache.deinit();
        self.* = undefined;
    }

    fn calcSeqLen(self: *Self, row: Row, keypads_left: u8) !u64 {
        var cost: u64 = 0;
        var targets: [4]Vec2 = undefined;
        for (row, targets[0..3]) |digit, *target| {
            target.* = switch (digit) {
                0 => Vec2{ 1, 3 },
                1 => Vec2{ 0, 2 },
                2 => Vec2{ 1, 2 },
                3 => Vec2{ 2, 2 },
                4 => Vec2{ 0, 1 },
                5 => Vec2{ 1, 1 },
                6 => Vec2{ 2, 1 },
                7 => Vec2{ 0, 0 },
                8 => Vec2{ 1, 0 },
                9 => Vec2{ 2, 0 },
                else => return error.InvalidInput,
            };
        }
        var pos = Vec2{ 2, 3 };
        targets[3] = pos;
        for (targets) |target| {
            const delta = target - pos;
            const axis = if (pos[1] == 3 and target[0] == 0)
                Axis.vertical
            else if (target[1] == 3 and pos[0] == 0)
                Axis.horizontal
            else
                null;

            cost += if (axis) |a|
                try self.countButtonPresses(keypads_left, Move{ .delta = delta, .first_axis = a })
            else
                try self.countButtonPressesNoDir(keypads_left, delta);

            cost += 1; // for actually pressing the button
            pos = target;
        }
        return cost;
    }

    fn countButtonPressesNoDir(self: *Self, keypads_left: u8, delta: Vec2) Allocator.Error!u64 {
        const h = try self.countButtonPresses(keypads_left, Move{ .delta = delta, .first_axis = .horizontal });
        const v = try self.countButtonPresses(keypads_left, Move{ .delta = delta, .first_axis = .vertical });
        return @min(h, v);
    }

    fn countButtonPresses(self: *Self, keypads_left: u8, move: Move) Allocator.Error!u64 {
        if (self.cache.get(.{ keypads_left, move })) |v| return v;
        const v = try self.countButtonPressesImpl(keypads_left, move);
        try self.cache.put(.{ keypads_left, move }, v);
        return v;
    }

    // Counts how many inputs it takes to perform a certain move through a keypad
    fn countButtonPressesImpl(self: *Self, keypads_left: u8, move: Move) Allocator.Error!u64 {
        const press_cost: u64 = @reduce(.Add, @abs(move.delta));
        if (keypads_left == 0) return press_cost;
        if (press_cost == 0) return 0;
        if (move.first_axis == .horizontal and move.delta[0] == 0) {
            return self.countButtonPresses(keypads_left, Move{ .delta = move.delta, .first_axis = .vertical });
        }
        if (move.first_axis == .vertical and move.delta[1] == 0) {
            return self.countButtonPresses(keypads_left, Move{ .delta = move.delta, .first_axis = .horizontal });
        }
        // Move horizontally first
        if (move.first_axis == .horizontal) {
            std.debug.assert(move.delta[0] != 0);
            const dx: i8 = if (move.delta[0] < 0) -2 else 0;
            // From A to < or >
            const move_to_hor = try self.countButtonPresses(keypads_left - 1, Move{ .delta = Vec2{ dx, 1 }, .first_axis = .vertical });
            if (move.delta[1] == 0) {
                // From < or > to A
                const move_back = try self.countButtonPresses(keypads_left - 1, Move{ .delta = Vec2{ -dx, -1 }, .first_axis = .horizontal });
                return move_to_hor + move_back + press_cost;
            }
            const move_to_ver = if (move.delta[0] > 0 and move.delta[1] < 0)
                // From > to ^
                try self.countButtonPressesNoDir(keypads_left - 1, Vec2{ -1, -1 })
            else
                // From < to ^ or v, or from > to v
                try self.countButtonPresses(keypads_left - 1, Move{
                    .delta = Vec2{ if (move.delta[0] < 0) 1 else -1, if (move.delta[1] < 0) -1 else 0 },
                    .first_axis = .horizontal,
                });
            const move_back = if (move.delta[1] > 0)
                // From v to A
                try self.countButtonPressesNoDir(keypads_left - 1, Vec2{ 1, -1 })
            else
                // From ^ to A
                try self.countButtonPresses(keypads_left - 1, Move{ .delta = Vec2{ 1, 0 }, .first_axis = .horizontal });
            return move_to_hor + move_to_ver + move_back + press_cost;
        }
        // Move vertically first
        else {
            std.debug.assert(move.delta[1] != 0);
            const move_to_ver = if (move.delta[1] > 0)
                // From A to v
                try self.countButtonPressesNoDir(keypads_left - 1, Vec2{ -1, 1 })
            else
                // From A to ^
                try self.countButtonPresses(keypads_left - 1, Move{ .delta = Vec2{ -1, 0 }, .first_axis = .horizontal });
            if (move.delta[0] == 0) {
                const move_back = if (move.delta[1] > 0)
                    // From v to A
                    try self.countButtonPressesNoDir(keypads_left - 1, Vec2{ 1, -1 })
                else
                    // From ^ to A
                    try self.countButtonPresses(keypads_left - 1, Move{ .delta = Vec2{ 1, 0 }, .first_axis = .horizontal });
                return move_to_ver + move_back + press_cost;
            }

            const move_to_hor = if (move.delta[0] > 0 and move.delta[1] < 0)
                // From ^ to >
                try self.countButtonPressesNoDir(keypads_left - 1, Vec2{ 1, 1 })
            else
                // From v to < or >, or from ^ to <
                try self.countButtonPresses(keypads_left - 1, Move{
                    .delta = Vec2{ if (move.delta[0] < 0) -1 else 1, if (move.delta[1] < 0) 1 else 0 },
                    .first_axis = .vertical,
                });
            const move_back = try self.countButtonPresses(keypads_left - 1, Move{
                .delta = Vec2{ if (move.delta[0] < 0) 2 else 0, -1 },
                .first_axis = .horizontal,
            });
            return move_to_ver + move_to_hor + move_back + press_cost;
        }
    }
};

const test_input =
    \\029A
    \\980A
    \\179A
    \\456A
    \\379A
;
test "day21::pt1" {
    try fw.t.simple(@This(), pt1, 126384, test_input);
}
