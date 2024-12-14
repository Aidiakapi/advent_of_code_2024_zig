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

const Grid = fw.grid.BitGrid;
pub fn pt2(robots: []Robot, allocator: std.mem.Allocator) !usize {
    // try generateImages(robots, allocator);
    var grid = try Grid.init(101, 103, allocator);
    defer grid.deinit(allocator);

    // We're looking for a little Christmas tree, which is in a 31x33 rectangle,
    // with a solid outline, and a tree drawn inside.
    //
    // We use three heuristics to detect which one matches, all based on the
    // density of bits set within the bitset.
    // 1. Within 128-bit windows, there are at least 2 cases with 31-bits set.
    //    These are for the top and bottom border.
    // 2. Below at least one of these windows, there is another window with at
    //    least 31 bits set 32 rows below it. Top and bottom border are a pair.
    // 2. Within 128-bit windows, there are at least 11 cases with 15 bits set.
    //    Two for top and bottom, and 9 for within the contents of the tree.
    var match: ?usize = null;
    const bitset = grid.getBitSetSlice();
    for (1..101 * 103) |steps| {
        fillGrid(robots, &grid, @intCast(steps));
        var t15: u32 = 0;
        var t31: u32 = 0;
        var has_31_at_offset = false;
        var prev: u32 = @popCount(bitset[0]);
        for (bitset[1..], 0..) |currData, i| {
            const curr: u32 = @popCount(currData);
            const bits_in_window = prev + curr;
            prev = curr;
            if (bits_in_window < 15) continue;
            t15 += 1;
            if (bits_in_window < 31) continue;
            t31 += 1;
            // We look 32 rows down, and count if we also find a pattern of
            // at least 31 bits there.
            const bits_beg_min = 32 * 101 + i * 64;
            const bits_end_max = 32 * 101 + i * 64 + 127;
            const index_max = @min(bitset.len, bits_end_max / 64 + 1);
            const index_min = @min(index_max, bits_beg_min / 64);
            var bits: u32 = 0;
            for (index_min..index_max) |j|
                bits += @popCount(bitset[j]);
            if (bits >= 31) has_31_at_offset = true;
        }
        if (has_31_at_offset and t15 >= 11 and t31 >= 2) {
            if (match) |_| return error.MultiplePotentialSolutions;
            match = steps;
        }
    }
    return match orelse error.NoSolution;
}

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

    const scan_line_size = (std.math.divCeil(comptime_int, 101, 8 * 4) catch unreachable) * 4;
    const pixel_data_byte_count = scan_line_size * 103;
    const headers_size_base = 14 + 40 + 4 * 2;
    const headers_size = (std.math.divCeil(comptime_int, headers_size_base, 4) catch unreachable) * 4;
    const file_size = headers_size + pixel_data_byte_count;

    var bmp = try std.ArrayList(u8).initCapacity(allocator, file_size);
    defer bmp.deinit();
    const writer = bmp.fixedWriter();
    // BITMAPFILEHEADER
    try writer.writeByte('B');
    try writer.writeByte('M');
    try writer.writeInt(u32, file_size, .little); // FileSize
    try writer.writeInt(u32, 0, .little); // reserved
    try writer.writeInt(u32, headers_size, .little); // DataOffset
    // BITMAPINFOHEADER
    try writer.writeInt(u32, 40, .little); // Size of InfoHeader
    try writer.writeInt(u32, 101, .little); // Width
    try writer.writeInt(u32, 103, .little); // Height
    try writer.writeInt(u16, 1, .little); // Planes
    try writer.writeInt(u16, 1, .little); // BitsPerPixel
    try writer.writeInt(u32, 0, .little); // Compression, BI_RGB/no compression
    try writer.writeInt(u32, 0, .little); // ImageSize, dummy 0 because uncompressed
    try writer.writeInt(u32, 1024, .little); // XpixelsPerM
    try writer.writeInt(u32, 1024, .little); // YpixelsPerM
    try writer.writeInt(u32, 2, .little); // ColorsUsed
    try writer.writeInt(u32, 0, .little); // ImportantColors
    // ColorTable
    try writer.writeAll(&[4]u8{ 0, 0, 0, 0 }); // black
    try writer.writeAll(&[4]u8{ 255, 255, 255, 0 }); // white
    // padding
    for (0..headers_size - headers_size_base) |_| try writer.writeByte(0);

    std.debug.assert(bmp.items.len == headers_size);
    try bmp.resize(file_size);

    const pixel_data = bmp.items[headers_size..];

    const cwd = std.fs.cwd();
    cwd.makeDir("day14_images") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const out_dir = try cwd.openDir("day14_images", .{});
    for (0..101 * 103) |steps| {
        fillGrid(robots, &grid, @intCast(steps));

        @memset(pixel_data, 0);
        for (0..103) |y| {
            const fy = 103 - 1 - y;
            const scan_line_data = pixel_data[fy * scan_line_size .. fy * scan_line_size + scan_line_size];
            for (0..101) |x| {
                if (grid.get(.{ x, y })) {
                    scan_line_data[x / 8] |= @as(u8, 1) << @truncate(7 - x % 8);
                }
            }
        }

        var file_name_buf: [9]u8 = undefined;
        const file_name = try std.fmt.bufPrint(&file_name_buf, "{:0>5}.bmp", .{steps});
        const out_file = try out_dir.createFile(file_name, .{});
        try out_file.writeAll(bmp.items);
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
test "day14::pt2" {
    try fw.t.simple(@This(), pt2, void{}, test_input);
}
