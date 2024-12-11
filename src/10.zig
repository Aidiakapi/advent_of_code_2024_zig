const std = @import("std");
const fw = @import("fw");

const InputGrid = fw.grid.DenseGrid(u4);
pub fn parse(ctx: fw.p.ParseContext) ?InputGrid {
    const p = fw.p;
    return p.grid(InputGrid, p.digit, p.noOp, p.nl)
        .execute(ctx);
}

pub fn pt1(grid: InputGrid, allocator: std.mem.Allocator) u32 {
    const Context = struct {
        const Grid = fw.grid.DenseGrid(u256);
        current_bit: u256,

        pub inline fn init(self: *@This()) u256 {
            std.debug.assert(self.current_bit != 0);
            const res = self.current_bit;
            self.current_bit <<= 1;
            return res;
        }
        pub inline fn combine(a: u256, b: u256) u256 {
            return a | b;
        }
        pub inline fn finalize(v: u256) u32 {
            return @popCount(v);
        }
    };
    var context = Context{ .current_bit = 1 };
    return pts(grid, allocator, &context);
}

pub fn pt2(grid: InputGrid, allocator: std.mem.Allocator) u32 {
    const Context = struct {
        const Self = @This();
        const Grid = fw.grid.DenseGrid(u16);
        pub inline fn init(_: Self) u16 {
            return 1;
        }
        pub inline fn combine(a: u16, b: u16) u16 {
            return a + b;
        }
        pub inline fn finalize(v: u16) u32 {
            return v;
        }
    };
    return pts(grid, allocator, &Context{});
}

fn pts(grid: InputGrid, allocator: std.mem.Allocator, context: anytype) u32 {
    const Context = @TypeOf(context.*);
    var intermediate = Context.Grid{
        .items = allocator.alloc(Context.Grid.Item, grid.items.len) catch @panic("OOM"),
        .width = grid.width,
        .height = grid.height,
    };
    defer intermediate.deinit(allocator);
    @memset(intermediate.items, 0);

    for (grid.items, intermediate.items) |in, *out| {
        if (in == 9) {
            out.* = context.init();
        }
    }

    var i: usize = 9;
    while (i > 0) : (i -= 1) {
        for (grid.items, intermediate.items, 0..) |in, *out, cell_index| {
            if (i - 1 != in) {
                continue;
            }
            const position = grid.coordFromIndex(@as(isize, @intCast(cell_index))) orelse unreachable;
            const xs = Context.combine(
                getIfValid(i, grid, intermediate.items, .{ position[0] - 1, position[1] }),
                getIfValid(i, grid, intermediate.items, .{ position[0] + 1, position[1] }),
            );
            const ys = Context.combine(
                getIfValid(i, grid, intermediate.items, .{ position[0], position[1] - 1 }),
                getIfValid(i, grid, intermediate.items, .{ position[0], position[1] + 1 }),
            );
            out.* = Context.combine(xs, ys);
        }
    }

    var result: u32 = 0;
    for (grid.items, intermediate.items) |in, out| {
        if (in == 0) {
            result += Context.finalize(out);
        }
    }
    return result;
}

fn getIfValid(i: usize, grid: InputGrid, elements: anytype, position: struct { isize, isize }) @typeInfo(@TypeOf(elements)).pointer.child {
    const cell_index = grid.indexFromCoord(position) orelse return 0;
    return if (grid.items[cell_index] == i) elements[cell_index] else 0;
}

const test_input =
    \\89010123
    \\78121874
    \\87430965
    \\96549874
    \\45678903
    \\32019012
    \\01329801
    \\10456732
;
test "day10::pt1" {
    try fw.t.simple(@This(), pt1, 36, test_input);
}
test "day10::pt2" {
    try fw.t.simple(@This(), pt2, 81, test_input);
}
