const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Coord = fw.grid.Coord;
const BitGrid = fw.grid.BitGrid;
pub fn parse(ctx: fw.p.ParseContext) ?[]Coord {
    const p = fw.p;
    const n = p.nr(usize);
    const coord = p.allOf(Coord, .{ n, p.literal(',').then(n) });
    return coord.sepBy(p.nl).execute(ctx);
}

pub fn pt1(coords: []Coord, allocator: Allocator) !usize {
    return pt1Impl(71, 1024)(coords, allocator);
}

pub fn pt2(coords: []Coord, allocator: Allocator) ![]u8 {
    return pt2Impl(71)(coords, allocator);
}

fn AStarContext(size: comptime_int) type {
    const max = size - 1;
    return struct {
        const Self = @This();
        pub const Node = Coord;
        pub const Cost = usize;
        const goal: Coord = .{ max, max };

        grid: *BitGrid,
        edge_count: usize = 0,
        edges: [4]struct { Node, Cost } = undefined,
        pub fn isTarget(_: Self, v: Coord) bool {
            return @reduce(.And, goal == v);
        }

        pub fn heuristic(_: Self, v: Coord) Cost {
            return @reduce(.Add, goal - v);
        }

        fn tryPushCell(self: *Self, new_coord: Coord) void {
            if (self.grid.get(new_coord)) return;
            self.edges[self.edge_count] = .{ new_coord, 1 };
            self.edge_count += 1;
        }
        pub fn getEdges(self: *Self, v: Coord) []struct { Node, Cost } {
            self.edge_count = 0;
            if (v[0] < max) self.tryPushCell(.{ v[0] + 1, v[1] });
            if (v[1] < max) self.tryPushCell(.{ v[0], v[1] + 1 });
            if (v[0] > 0) self.tryPushCell(.{ v[0] - 1, v[1] });
            if (v[1] > 0) self.tryPushCell(.{ v[0], v[1] - 1 });
            return self.edges[0..self.edge_count];
        }
    };
}

fn pt1Impl(size: comptime_int, steps: comptime_int) fn ([]Coord, Allocator) anyerror!usize {
    const Context = AStarContext(size);
    const AStar = fw.astar.AStar(Context, .{ .path = .none });
    return struct {
        fn f(coords: []Coord, allocator: Allocator) anyerror!usize {
            var grid = try BitGrid.init(size, size, allocator);
            defer grid.deinit(allocator);
            for (coords[0..@min(steps, coords.len)]) |coord| {
                grid.set(coord, true);
            }

            var astar = AStar.init(allocator, Context{ .grid = &grid });
            defer astar.deinit();
            const res = (try astar.shortestPath(Coord{ 0, 0 })) orelse
                return error.NoSolution;
            return res[1];
        }
    }.f;
}

fn pt2Impl(size: comptime_int) fn ([]Coord, Allocator) anyerror![]u8 {
    const Context = AStarContext(size);
    const AStar = fw.astar.AStar(Context, .{ .path = .none });
    return struct {
        fn f(coords: []Coord, allocator: Allocator) anyerror![]u8 {
            var grid = try BitGrid.init(size, size, allocator);
            defer grid.deinit(allocator);

            var astar = AStar.init(allocator, Context{ .grid = &grid });
            defer astar.deinit();

            var lo: usize = 0; // exclusive
            var hi = coords.len - 1; // inclusive
            while (lo < hi) {
                const mid = (hi - lo) / 2 + lo;
                grid.clear();
                for (coords[0 .. mid + 1]) |coord| {
                    grid.set(coord, true);
                }
                const has_path = try astar.shortestPath(Coord{ 0, 0 }) != null;
                if (has_path) {
                    lo = mid + 1;
                } else {
                    hi = mid;
                }
            }

            return std.fmt.allocPrint(allocator, "{},{}", .{ coords[hi][0], coords[hi][1] });
        }
    }.f;
}

const test_input =
    \\5,4
    \\4,2
    \\4,5
    \\3,0
    \\2,1
    \\6,3
    \\2,4
    \\1,5
    \\0,6
    \\3,3
    \\2,6
    \\5,1
    \\1,2
    \\5,5
    \\2,5
    \\6,5
    \\1,4
    \\0,4
    \\6,4
    \\1,1
    \\6,1
    \\1,0
    \\0,5
    \\1,6
    \\2,0
;
test "day18::pt1" {
    try fw.t.simple(@This(), pt1Impl(7, 12), 22, test_input);
}
test "day18::pt2" {
    try fw.t.simple(@This(), pt2Impl(7), "6,1", test_input);
}
