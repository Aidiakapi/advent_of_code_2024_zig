const std = @import("std");
const fw = @import("fw");

const Vec2 = @Vector(2, i32);
const Robot = struct {
    position: Vec2,
    velocity: Vec2,
};

pub fn parse(ctx: fw.p.ParseContext) ?[]Robot {
    const p = fw.p;
    const nr = p.nr(i32);
    const vec2 = p.allOf(Vec2, .{ nr, p.literal(',').then(nr) });
    const robot = p.allOf(Robot, .{ p.literal("p=").then(vec2), p.literal(" v=").then(vec2) });
    return robot.sepBy(p.nl).execute(ctx);
}

pub fn pt1(robots: []Robot) u32 {
    return pt1Impl(.{ 101, 103 })(robots);
}

fn pt1Impl(comptime size: Vec2) fn ([]Robot) u32 {
    std.debug.assert(size[0] % 2 == 1 and size[1] % 2 == 1);
    return struct {
        fn f(robots: []Robot) u32 {
            const mid = size / Vec2{ 2, 2 };
            var lt: u32, var lb: u32, var rt: u32, var rb: u32 = .{ 0, 0, 0, 0 };
            for (robots) |robot| {
                const p = positionAfter(size, robot, 100);
                if (p[0] == mid[0] or p[1] == mid[1]) continue;
                const l = p[0] < mid[0];
                const t = p[1] < mid[1];
                const counter = if (l) if (t) &lt else &lb else if (t) &rt else &rb;
                counter.* += 1;
            }
            return lt * lb * rt * rb;
        }
    }.f;
}

fn positionAfter(comptime size: Vec2, robot: Robot, steps: i32) Vec2 {
    const raw = robot.position + robot.velocity * Vec2{ steps, steps };
    return @mod(raw, size);
}

pub fn pt2(robots: []Robot, allocator: std.mem.Allocator) !usize {
    _ = allocator;
    // try generateImages(robots, allocator);

    const x = try getOffset(0, robots);
    const y = try getOffset(1, robots);

    // r = 101a + x = 103b + y
    // x + 101a = y mod 103
    // y + 103b = x mod 101
    // simplify and pull variables to left
    // 101a = y - x mod 103
    //   2b = x - y mod 101
    // 101^-1 mod 103 == 2^-1 mod 101 == 51
    // a = 51 * (y - x) mod 103
    // b = 51 * (x - y) mod 101
    if (x < y) {
        const a = @mod(51 * (y - x), 103);
        return a * 101 + x;
    } else {
        const b = @mod(51 * (x - y), 101);
        return b * 103 + y;
    }
}

fn getOffset(comptime coord_index: usize, robots: []Robot) !u32 {
    const image_size: i32 = 101 + coord_index * 2;

    // This uses the heuristic that for the correct solution, the pixels are
    // clustered much more densely. There will be many near-empty rows/columns,
    // and then some with *a lot* of robots.
    // By squaring the amount of robots per row/column, the dense rows are
    // weighted heavily, and the sparse rows are virtually irrelevant.
    var max_score: u32 = 0;
    var max_score_index: u32 = 0;

    var data: [image_size]u8 = undefined;
    for (0..image_size) |steps_usize| {
        const steps: i32 = @intCast(steps_usize);
        @memset(&data, 0);
        for (robots) |robot| {
            const pos = robot.position[coord_index] + steps * robot.velocity[coord_index];
            data[@intCast(@mod(pos, image_size))] += 1;
        }

        var score: u32 = 0;
        for (data) |value| {
            score += @as(u32, value) * @as(u32, value);
        }
        if (score < max_score) continue;
        max_score = score;
        max_score_index = @intCast(steps);
    }

    return max_score_index;
}

const Grid = fw.grid.BitGrid;
fn fillGrid(robots: []Robot, grid: *Grid, steps: i32) void {
    grid.clear();
    for (robots) |robot| {
        const p = positionAfter(.{ 101, 103 }, robot, steps);
        grid.set(p, true);
    }
}

fn generateImages(robots: []Robot, allocator: std.mem.Allocator) !void {
    var grid = try Grid.init(101, 103, allocator);
    defer grid.deinit(allocator);

    const cwd = std.fs.cwd();
    cwd.makeDir("day14_images") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const out_dir = try cwd.openDir("day14_images", .{});

    var buffer = try std.ArrayList(u8).initCapacity(allocator, grid.getBitmapByteCount());
    defer buffer.deinit();

    for (0..101 * 103) |steps| {
        fillGrid(robots, &grid, @intCast(steps));
        try grid.writeBitmap(buffer.fixedWriter());

        var file_name_buf: [9]u8 = undefined;
        const file_name = try std.fmt.bufPrint(&file_name_buf, "{:0>5}.bmp", .{steps});
        const out_file = try out_dir.createFile(file_name, .{});
        defer out_file.close();
        try out_file.writeAll(buffer.items);
        buffer.clearRetainingCapacity();
    }
}

const test_input =
    \\p=0,4 v=3,-3
    \\p=6,3 v=-1,-3
    \\p=10,3 v=-1,2
    \\p=2,0 v=2,-1
    \\p=0,0 v=1,3
    \\p=3,0 v=-2,-2
    \\p=7,6 v=-1,-3
    \\p=3,0 v=-1,-2
    \\p=9,3 v=2,3
    \\p=7,3 v=-1,2
    \\p=2,4 v=2,-3
    \\p=9,5 v=-3,-3
;

test "day14::pt1" {
    try fw.t.simple(@This(), pt1Impl(.{ 11, 7 }), 12, test_input);
}
