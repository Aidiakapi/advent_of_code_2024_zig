const std = @import("std");
const fw = @import("fw");

const Grid = fw.grid.DenseGrid(u8);

pub fn parse(ctx: fw.p.ParseContext) ?Grid {
    const p = fw.p;
    return p.grid(Grid, p.any.filter(notNl), p.noOp, p.nl)
        .execute(ctx);
}

fn notNl(v: u8) bool {
    return v != '\n';
}

pub fn pt1(input: Grid) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (std.mem.indexOfScalarPos(u8, input.items, index, 'X')) |x_pos| {
        index = x_pos + 1;
        if (isXmasTail(input, x_pos, 1, 0)) count += 1;
        if (isXmasTail(input, x_pos, -1, 0)) count += 1;
        if (isXmasTail(input, x_pos, 0, 1)) count += 1;
        if (isXmasTail(input, x_pos, 0, -1)) count += 1;
        if (isXmasTail(input, x_pos, 1, 1)) count += 1;
        if (isXmasTail(input, x_pos, -1, -1)) count += 1;
        if (isXmasTail(input, x_pos, 1, -1)) count += 1;
        if (isXmasTail(input, x_pos, -1, 1)) count += 1;
    }
    return count;
}

fn isXmasTail(input: Grid, index: usize, comptime ox: isize, comptime oy: isize) bool {
    const coord = input.coordFromIndex(index) orelse unreachable;
    return (input.tryGet(.{ coord[0] +% @as(usize, @bitCast(ox)), coord[1] +% @as(usize, @bitCast(oy)) }) orelse return false).* == 'M' and
        (input.tryGet(.{ coord[0] +% @as(usize, @bitCast(ox * 2)), coord[1] +% @as(usize, @bitCast(oy * 2)) }) orelse return false).* == 'A' and
        (input.tryGet(.{ coord[0] +% @as(usize, @bitCast(ox * 3)), coord[1] +% @as(usize, @bitCast(oy * 3)) }) orelse return false).* == 'S';
}

pub fn pt2(input: Grid) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (std.mem.indexOfScalarPos(u8, input.items, index, 'A')) |a_pos| {
        index = a_pos + 1;
        if (hasMsOnDiagonal(input, a_pos, 1, 1) and
            hasMsOnDiagonal(input, a_pos, 1, -1)) count += 1;
    }
    return count;
}

fn hasMsOnDiagonal(input: Grid, index: usize, comptime ox: isize, comptime oy: isize) bool {
    const coord = input.coordFromIndex(index) orelse unreachable;
    const a = (input.tryGet(.{ coord[0] +% @as(usize, @bitCast(ox)), coord[1] +% @as(usize, @bitCast(oy)) }) orelse return false).*;
    if (a != 'M' and a != 'S') return false;
    const b = (input.tryGet(.{ coord[0] +% @as(usize, @bitCast(-ox)), coord[1] +% @as(usize, @bitCast(-oy)) }) orelse return false).*;
    if (b != 'M' and b != 'S') return false;
    return (a == 'M') != (b == 'M');
}

const test_input =
    \\MMMSXXMASM
    \\MSAMXMSMSA
    \\AMXSXMAAMM
    \\MSAMASMSMX
    \\XMASAMXAMM
    \\XXAMMXXAMA
    \\SMSMSASXSS
    \\SAXAMASAAA
    \\MAMMMXMMMM
    \\MXMXAXMASX
;
test "day04::pt1" {
    try fw.t.simple(@This(), pt1, 18, test_input);
}
test "day04::pt2" {
    try fw.t.simple(@This(), pt2, 9, test_input);
}
