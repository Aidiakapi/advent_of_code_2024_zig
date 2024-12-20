const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const BitGrid = fw.grid.BitGrid;
const Coord = fw.grid.Coord;
const Points = struct {
    start: Coord,
    end: Coord,
};

const DistGrid = fw.grid.DenseGrid(u32);

pub fn parse(ctx: fw.p.ParseContext) ?struct { BitGrid, Points } {
    const p = fw.p;
    return p.gridWithPOIs(
        BitGrid,
        p.oneOfValues(.{ .{ p.literal('.'), false }, .{ p.literal('#'), true } }),
        p.noOp,
        p.nl,
        Points,
        false,
        .{ p.literal('S'), p.literal('E') },
    )
        .execute(ctx);
}

pub fn pt1(input: struct { BitGrid, Points }, allocator: Allocator) !u32 {
    const grid, const points = input;
    var dists = try createDistGrid(allocator, grid, points);
    defer dists.deinit(allocator);

    var count_saved_100: u32 = 0;
    var iterator = dists.iterate();
    while (iterator.next()) |entry| {
        if (entry.value.* != max_dist) continue;

        const x = entry.x;
        const y = entry.y;
        if (x == 0 or x == dists.width - 1) continue;
        if (y == 0 or y == dists.height - 1) continue;

        if (x % 2 == 0) {
            const saved = calcTimeSaved(dists, entry.index - 1, entry.index + 1);
            if (saved >= 100) count_saved_100 += 1;
        }
        if (y % 2 == 0) {
            const saved = calcTimeSaved(dists, entry.index - dists.width, entry.index + dists.width);
            if (saved >= 100) count_saved_100 += 1;
        }
    }

    return count_saved_100;
}

fn calcTimeSaved(dists: DistGrid, a: usize, b: usize) DistGrid.Item {
    const ca = dists.get(a);
    const cb = dists.get(b);
    if (ca.* == max_dist or cb.* == max_dist) return 0;
    const delta = @max(ca.*, cb.*) - @min(ca.*, cb.*);
    return if (delta > 2) delta - 2 else 0;
}

pub fn pt2(input: struct { BitGrid, Points }, allocator: Allocator) !u32 {
    const grid, const points = input;
    var dists = try createDistGrid(allocator, grid, points);
    defer dists.deinit(allocator);

    var count_saved_100: u32 = 0;
    var iterator = dists.iterate();
    while (iterator.next()) |entry| {
        const source_dist = entry.value.*;
        if (source_dist == max_dist) continue;

        const sx: isize = @intCast(entry.x);
        const sy: isize = @intCast(entry.y);

        const tx_min = @max(sx - 20, 1);
        const tx_max = @min(sx + 20, @as(isize, @intCast(dists.width - 2)));
        const ty_min = @max(sy - 20, 1);
        const ty_max = @min(sy + 20, @as(isize, @intCast(dists.height - 2)));
        var ty = ty_min;
        while (ty <= ty_max) : (ty += 1) {
            const dy = @abs(sy - ty);
            const index_y = @as(usize, @intCast(ty)) * dists.width;
            var tx = tx_min;
            while (tx <= tx_max) : (tx += 1) {
                const dx = @abs(sx - tx);
                const cheat_len = dx + dy;
                if (cheat_len > 20) continue;
                const target_dist = dists.get(index_y + @as(usize, tx)).*;
                if (target_dist == max_dist) continue;
                const cheat_dist = source_dist + cheat_len;
                if (cheat_dist > target_dist) continue;
                const saved = target_dist - cheat_dist;
                if (saved >= 100) count_saved_100 += 1;
            }
        }
    }

    return count_saved_100;
}

const max_dist = std.math.maxInt(DistGrid.Item);
fn createDistGrid(allocator: Allocator, grid: BitGrid, points: Points) !DistGrid {
    var dists = try DistGrid.init(grid.width, grid.height, max_dist, allocator);
    createDistGridVisit(grid, &dists, points.end, 0);
    return dists;
}
fn createDistGridVisit(grid: BitGrid, dists: *DistGrid, pos: Coord, dist: DistGrid.Item) void {
    const index = grid.indexFromCoord(pos) orelse unreachable;
    const cell = dists.get(index);
    if (cell.* != max_dist) return;
    if (grid.get(index)) return;
    cell.* = dist;
    const next_dist = dist + 1;
    if (pos[0] > 0) createDistGridVisit(grid, dists, .{ pos[0] - 1, pos[1] }, next_dist);
    if (pos[1] > 0) createDistGridVisit(grid, dists, .{ pos[0], pos[1] - 1 }, next_dist);
    if (pos[0] + 1 < grid.width) createDistGridVisit(grid, dists, .{ pos[0] + 1, pos[1] }, next_dist);
    if (pos[1] + 1 < grid.height) createDistGridVisit(grid, dists, .{ pos[0], pos[1] + 1 }, next_dist);
}

const test_input =
    \\###############
    \\#...#...#.....#
    \\#.#.#.#.#.###.#
    \\#S#...#.#.#...#
    \\#######.#.#.###
    \\#######.#.#...#
    \\#######.#.###.#
    \\###..E#...#...#
    \\###.#######.###
    \\#...###...#...#
    \\#.#####.#.###.#
    \\#.#...#.#.#...#
    \\#.#.#.#.#.#.###
    \\#...#...#...###
    \\###############
;
test "day20::pt1" {
    try fw.t.simple(@This(), pt1, 0, test_input);
}
test "day20::pt2" {
    try fw.t.simple(@This(), pt2, 0, test_input);
}
