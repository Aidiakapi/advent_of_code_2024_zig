const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Grid = fw.grid.DenseGrid(u8);
const BitGrid = fw.grid.BitGrid;
pub fn parse(ctx: fw.p.ParseContext) ?Grid {
    const p = fw.p;
    const c = p.any.filter(struct {
        pub fn eval(v: u8) bool {
            return v != '\n';
        }
    });
    return p.grid(Grid, c, p.noOp, p.nl).execute(ctx);
}

pub fn pt1(grid: Grid, allocator: Allocator) !usize {
    return pts(false, grid, allocator);
}

pub fn pt2(grid: Grid, allocator: Allocator) !usize {
    return pts(true, grid, allocator);
}

const Vec2 = [2]i32;
fn pts(comptime repeating: bool, grid: Grid, allocator: Allocator) !usize {
    var visited = try BitGrid.init(grid.width, grid.height, allocator);
    defer visited.deinit(allocator);

    var unique_locations = try BitGrid.init(grid.width, grid.height, allocator);
    defer unique_locations.deinit(allocator);

    var antennas = std.ArrayList(Vec2).init(allocator);
    defer antennas.deinit();

    while (true) {
        var index = visited.countLeadingOnes();
        if (index == visited.len) break;
        antennas.clearRetainingCapacity();
        (try antennas.addOne()).* = grid.coordFromIndex(@as(i32, @intCast(index))).?;
        visited.set(index, true);

        const frequency = grid.items[index];
        if (frequency == '.') continue;

        while (std.mem.indexOfScalarPos(u8, grid.items, index + 1, frequency)) |next_index| {
            index = next_index;
            (try antennas.addOne()).* = grid.coordFromIndex(@as(i32, @intCast(index))).?;
            visited.set(index, true);
        }

        for (antennas.items, 0..antennas.items.len) |a, i| {
            if (repeating) _ = unique_locations.trySet(a, true);
            const a2: Vec2 = .{ a[0] * 2, a[1] * 2 };
            for (antennas.items, 0..antennas.items.len) |b, j| {
                if (i == j) continue;
                if (!repeating) {
                    const c: Vec2 = .{ a2[0] - b[0], a2[1] - b[1] };
                    _ = unique_locations.trySet(c, true);
                    continue;
                }
                const d: Vec2 = .{ b[0] - a[0], b[1] - a[1] };
                var c: Vec2 = b;
                while (true) {
                    c[0] += d[0];
                    c[1] += d[1];
                    if (!unique_locations.trySet(c, true)) {
                        break;
                    }
                }
            }
        }
    }

    return unique_locations.countOnes();
}

const test_input =
    \\............
    \\........0...
    \\.....0......
    \\.......0....
    \\....0.......
    \\......A.....
    \\............
    \\............
    \\........A...
    \\.........A..
    \\............
    \\............
;
test "day08::pt1" {
    try fw.t.simple(@This(), pt1, 14, test_input);
}
test "day08::pt2" {
    try fw.t.simple(@This(), pt2, 34, test_input);
}
