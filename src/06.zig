const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const BitGrid = fw.grid.BitGrid;
const Grid = fw.grid.DenseGrid(Cell);
const Cell = enum(u8) {
    obstacle,
    empty,
    left,
    right,
    up,
    down,
};

pub fn parse(ctx: fw.p.ParseContext) ?Grid {
    const p = fw.p;
    const cell = p.oneOfValues(.{
        .{ p.literal('.'), Cell.empty },
        .{ p.literal('#'), Cell.obstacle },
        .{ p.literal('<'), Cell.left },
        .{ p.literal('>'), Cell.right },
        .{ p.literal('^'), Cell.up },
        .{ p.literal('v'), Cell.down },
    });
    const grid = p.grid(Grid, cell, p.noOp, p.nl);
    return grid.execute(ctx);
}

const Locomotion = struct {
    x: i32,
    y: i32,
    dx: i2,
    dy: i2,

    pub fn tryStep(self: *Locomotion, walls: BitGrid) bool {
        while (walls.tryGet(.{ self.x + self.dx, self.y + self.dy }) orelse return false) {
            const ox = self.dx;
            self.dx = -self.dy;
            self.dy = ox;
        }
        self.x += self.dx;
        self.y += self.dy;
        return true;
    }
};

pub fn pt1(grid: Grid, allocator: Allocator) !usize {
    const start_pos, var walls = try getInitialPosAndWalls(grid, allocator);
    defer walls.deinit(allocator);

    var visited = try getInitialVisited(start_pos, walls, allocator);
    defer visited.deinit(allocator);

    return visited.countOnes();
}

pub fn pt2(grid: Grid, allocator: Allocator) !usize {
    const start_pos, var walls = try getInitialPosAndWalls(grid, allocator);
    const start_index = grid.indexFromCoord(.{ start_pos.x, start_pos.y }) orelse unreachable;
    defer walls.deinit(allocator);

    var visited = try getInitialVisited(start_pos, walls, allocator);
    defer visited.deinit(allocator);

    var seen_dirs = fw.grid.DenseGrid(u4){
        .items = try allocator.alloc(u4, walls.len),
        .width = walls.width,
        .height = walls.height,
    };
    defer allocator.free(seen_dirs.items);

    var looping_count: usize = 0;
    for (0..visited.len) |index| {
        if (index == start_index or !visited.get(index)) {
            continue;
        }
        walls.set(index, true);
        defer walls.set(index, false);
        @memset(seen_dirs.items, 0);
        var locomotion = start_pos;
        while (true) {
            const dir_mask = toBit(locomotion.dx, 0) | toBit(locomotion.dy, 2);
            std.debug.assert(@popCount(dir_mask) == 1);
            const seen = seen_dirs.get(.{ locomotion.x, locomotion.y });
            if ((seen.* & dir_mask) != 0) {
                looping_count += 1;
                break;
            }
            seen.* |= dir_mask;
            if (!locomotion.tryStep(walls)) {
                break;
            }
        }
    }

    return looping_count;
}

fn toBit(dir: i2, offset: comptime_int) u4 {
    // three input pattrens: 00, 01, 11
    const unsigned: u2 = @bitCast(dir);
    const single_bit = unsigned ^ ((unsigned & 2) >> 1); // 11 => 10
    return @as(u4, single_bit) << offset;
}

fn getInitialPosAndWalls(grid: Grid, allocator: Allocator) !struct { Locomotion, BitGrid } {
    var walls = try BitGrid.init(grid.width, grid.height, allocator);
    errdefer walls.deinit(allocator);

    var locomotion = Locomotion{
        .x = -1,
        .y = -1,
        .dx = 0,
        .dy = 0,
    };
    for (grid.items, 0..) |cell, index| {
        switch (cell) {
            .obstacle => {
                walls.set(index, true);
                continue;
            },
            .empty => continue,
            .left => locomotion.dx = -1,
            .right => locomotion.dx = 1,
            .up => locomotion.dy = -1,
            .down => locomotion.dy = 1,
        }
        if (locomotion.x != -1) {
            return error.InvalidInput;
        }
        const start_pos = grid.coordFromIndex(@as(i32, @intCast(index))) orelse unreachable;
        locomotion.x = start_pos[0];
        locomotion.y = start_pos[1];
    }
    if (locomotion.x == -1) {
        return error.InvalidInput;
    }
    return .{ locomotion, walls };
}

fn getInitialVisited(start_pos: Locomotion, walls: BitGrid, allocator: Allocator) !BitGrid {
    var visited = try BitGrid.init(walls.width, walls.height, allocator);
    var locomotion = start_pos;
    while (true) {
        const index = visited.indexFromCoord(.{
            locomotion.x,
            locomotion.y,
        }) orelse unreachable;
        if (!visited.get(index)) {
            visited.set(index, true);
        }
        if (!locomotion.tryStep(walls)) {
            return visited;
        }
    }
}

const test_input =
    \\....#.....
    \\.........#
    \\..........
    \\..#.......
    \\.......#..
    \\..........
    \\.#..^.....
    \\........#.
    \\#.........
    \\......#...
;
test "day06::pt1" {
    try fw.t.simple(@This(), pt1, 41, test_input);
}
test "day06::pt2" {
    try fw.t.simple(@This(), pt2, 6, test_input);
}
