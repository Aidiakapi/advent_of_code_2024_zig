const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const BitGrid = fw.grid.BitGrid;
const Coord = fw.grid.Coord;
const Vec2 = @Vector(2, i32);
const POIs = struct {
    start: Coord,
    end: Coord,
};
const Input = struct { BitGrid, POIs };

pub fn parse(ctx: fw.p.ParseContext) ?Input {
    const p = fw.p;
    const cell = p.oneOfValues(.{ .{ p.literal('.'), false }, .{ p.literal('#'), true } });
    const walls = p.gridWithPOIs(
        BitGrid,
        cell,
        p.noOp,
        p.nl,
        POIs,
        false,
        .{ p.literal('S'), p.literal('E') },
    );
    return walls.execute(ctx);
}

const Direction = enum {
    left,
    right,
    up,
    down,

    pub fn tryStep(self: Direction, grid: BitGrid, pos: Coord) ?Coord {
        return switch (self) {
            .left => if (pos[0] == 0) null else .{ pos[0] - 1, pos[1] },
            .right => if (pos[0] + 1 == grid.width) null else .{ pos[0] + 1, pos[1] },
            .up => if (pos[1] == 0) null else .{ pos[0], pos[1] - 1 },
            .down => if (pos[1] + 1 == grid.height) null else .{ pos[0], pos[1] + 1 },
        };
    }

    pub fn rotCw(self: Direction) Direction {
        return switch (self) {
            .left => .up,
            .right => .down,
            .up => .right,
            .down => .left,
        };
    }
    pub fn rotCcw(self: Direction) Direction {
        return switch (self) {
            .left => .down,
            .right => .up,
            .up => .left,
            .down => .right,
        };
    }
};
const Context = struct {
    pub const Node = struct {
        pos: Coord,
        dir: Direction,
    };
    pub const Cost = usize;

    grid: BitGrid,
    end: Coord,
    edges: [3]struct { Node, Cost },

    pub fn init(input: Input) Context {
        return .{
            .grid = input[0],
            .end = input[1].end,
            .edges = undefined,
        };
    }

    pub fn isTarget(self: Context, node: Node) bool {
        return @reduce(.And, node.pos == self.end);
    }

    pub fn heuristic(self: Context, node: Node) Cost {
        const delta = @max(node.pos, self.end) - @min(node.pos, self.end);
        return delta[0] + delta[1] + 1000;
    }

    pub fn getEdges(self: *Context, node: Node) []struct { Node, Cost } {
        self.edges[0] = .{ .{ .pos = node.pos, .dir = node.dir.rotCw() }, 1000 };
        self.edges[1] = .{ .{ .pos = node.pos, .dir = node.dir.rotCcw() }, 1000 };
        if (node.dir.tryStep(self.grid, node.pos)) |new_pos| {
            if (!self.grid.get(new_pos)) {
                self.edges[2] = .{ .{ .pos = new_pos, .dir = node.dir }, 1 };
                return &self.edges;
            }
        }
        return self.edges[0..2];
    }
};

const AStarPt1 = fw.astar.AStar(Context, .{ .path = .none });
const AStarPt2 = fw.astar.AStar(Context, .{ .path = .all });

pub fn pt1(input: Input, allocator: Allocator) !usize {
    var astar = AStarPt1.init(allocator, Context.init(input));
    defer astar.deinit();

    const initial_node = Context.Node{ .pos = input[1].start, .dir = .right };
    const res = try astar.shortestPath(initial_node) orelse return error.NoSolution;
    return res[1];
}

const Visited = struct {
    any: BitGrid,
    left: BitGrid,
    right: BitGrid,
    up: BitGrid,
    down: BitGrid,
};
pub fn pt2(input: Input, allocator: Allocator) !usize {
    var visited: Visited = undefined;
    inline for (@typeInfo(Visited).@"struct".fields) |field| {
        @field(visited, field.name) = try BitGrid.init(input[0].width, input[0].height, allocator);
    }

    var astar = AStarPt2.init(allocator, Context.init(input));
    defer astar.deinit();

    const initial_node = Context.Node{ .pos = input[1].start, .dir = .right };
    const res = try astar.shortestPath(initial_node) orelse return error.NoSolution;

    pt2Visit(&visited, astar.parents, res[0]);

    return visited.any.countOnes();
}

fn pt2Visit(visited: *Visited, parents: AStarPt2.Parents, node: Context.Node) void {
    const grid = switch (node.dir) {
        .left => &visited.left,
        .right => &visited.right,
        .up => &visited.up,
        .down => &visited.down,
    };
    if (grid.get(node.pos)) return;
    const index = grid.indexFromCoord(node.pos) orelse unreachable;
    grid.set(index, true);
    visited.any.set(index, true);

    var iterator = parents.iterator(node);
    while (iterator.next()) |from| {
        pt2Visit(visited, parents, from);
    }
}

const test_input1 =
    \\###############
    \\#.......#....E#
    \\#.#.###.#.###.#
    \\#.....#.#...#.#
    \\#.###.#####.#.#
    \\#.#.#.......#.#
    \\#.#.#####.###.#
    \\#...........#.#
    \\###.#.#####.#.#
    \\#...#.....#.#.#
    \\#.#.#.###.#.#.#
    \\#.....#...#.#.#
    \\#.###.#.#.#.#.#
    \\#S..#.....#...#
    \\###############
;
const test_input2 =
    \\#################
    \\#...#...#...#..E#
    \\#.#.#.#.#.#.#.#.#
    \\#.#.#.#...#...#.#
    \\#.#.#.#.###.#.#.#
    \\#...#.#.#.....#.#
    \\#.#.#.#.#.#####.#
    \\#.#...#.#.#.....#
    \\#.#.#####.#.###.#
    \\#.#.#.......#...#
    \\#.#.###.#####.###
    \\#.#.#...#.....#.#
    \\#.#.#.#####.###.#
    \\#.#.#.........#.#
    \\#.#.#.#########.#
    \\#S#.............#
    \\#################
;
test "day16::pt1" {
    try fw.t.simple(@This(), pt1, 7036, test_input1);
    try fw.t.simple(@This(), pt1, 11048, test_input2);
}
test "day16::pt2" {
    try fw.t.simple(@This(), pt2, 45, test_input1);
    try fw.t.simple(@This(), pt2, 64, test_input2);
}
