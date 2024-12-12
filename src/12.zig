const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Farm = fw.grid.DenseGrid(u8);
const BitGrid = fw.grid.BitGrid;
pub fn parse(ctx: fw.p.ParseContext) ?Farm {
    const p = fw.p;
    const letter = p.any.filter(std.ascii.isUpper);
    return p.grid(Farm, letter, p.noOp, p.nl).execute(ctx);
}

pub fn pt1(farm: Farm, allocator: Allocator) !u64 {
    return pts(false, farm, allocator);
}

pub fn pt2(farm: Farm, allocator: Allocator) !u64 {
    return pts(true, farm, allocator);
}

fn pts(comptime collapse_perimeter: bool, farm: Farm, allocator: Allocator) !u64 {
    var visitor = try Visitor(collapse_perimeter).init(allocator, farm);
    defer visitor.deinit(allocator);

    var total: u64 = 0;
    while (visitor.visitNextRegion()) |region| {
        total += @as(u64, region.area) * region.perimeter;
    }
    return total;
}

const Region = struct {
    area: u32 = 0,
    perimeter: u32 = 0,
};
const Vec2 = [2]i32;
fn Visitor(comptime collapse_perimeter: bool) type {
    return struct {
        const Self = @This();

        farm: Farm,
        visited: BitGrid,
        output: Region = .{},
        target: u8 = 0,

        pub fn init(allocator: Allocator, farm: Farm) !Self {
            return .{
                .farm = farm,
                .visited = try BitGrid.init(farm.width, farm.height, allocator),
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.visited.deinit(allocator);
            self.* = undefined;
        }

        pub fn visitNextRegion(self: *Self) ?Region {
            const leading_ones_count = self.visited.countLeadingOnes();
            if (leading_ones_count == self.visited.len) {
                return null;
            }
            const res = self.visit(leading_ones_count);
            return res;
        }

        pub fn visit(self: *Self, index: usize) Region {
            self.output = .{};
            self.target = self.farm.get(index).*;
            self.visitImpl(index);
            return self.output;
        }

        fn visitImpl(self: *Self, index: usize) void {
            if (self.visited.get(index)) {
                return;
            }
            self.visited.set(index, true);
            self.output.area += 1;
            const pos = self.farm.coordFromIndex(@as(i32, @intCast(index))).?;
            for ([4]Vec2{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |offset| {
                const neighbor: Vec2 = .{ pos[0] + offset[0], pos[1] + offset[1] };
                if (self.isPartOfRegion(neighbor)) |neighbor_index| {
                    self.visitImpl(neighbor_index);
                    continue;
                }
                if (!collapse_perimeter) {
                    self.output.perimeter += 1;
                    continue;
                }
                // Goal: Must only count each side once, only consider first
                //       segment of each perimeter.
                // For the case where offset is {1, 0}. We have this region:
                // XY
                // AB
                // A == pos, B == neighbor, X == prev, Y == prev_neighbor
                // It is a secondary segment on the same side iff, X == A and Y != X.
                const prev = .{ pos[0] + offset[1], pos[1] - offset[0] };
                if (self.isPartOfRegion(prev)) |_| {} else {
                    self.output.perimeter += 1;
                    continue;
                }
                const prev_neighbor = .{ prev[0] + offset[0], prev[1] + offset[1] };
                if (self.isPartOfRegion(prev_neighbor)) |_| {
                    self.output.perimeter += 1;
                }
            }
        }

        fn isPartOfRegion(self: *Self, pos: Vec2) ?usize {
            if (self.farm.indexFromCoord(pos)) |index| {
                return if (self.farm.get(index).* == self.target) index else null;
            }
            return null;
        }
    };
}

const test_input =
    \\RRRRIICCFF
    \\RRRRIICCCF
    \\VVRRRCCFFF
    \\VVRCCCJFFF
    \\VVVVCJJCFE
    \\VVIVCCJJEE
    \\VVIIICJJEE
    \\MIIIIIJJEE
    \\MIIISIJEEE
    \\MMMISSJEEE
;
test "day12::pt1" {
    try fw.t.simple(@This(), pt1, 1930, test_input);
}
test "day12::pt2" {
    try fw.t.simple(@This(), pt2, 1206, test_input);
}
