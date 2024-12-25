const std = @import("std");
const fw = @import("fw");

const BitGrid = fw.grid.BitGrid;
pub fn parse(ctx: fw.p.ParseContext) ?[]BitGrid {
    const p = fw.p;
    const cell = p.oneOfValues(.{
        .{ p.literal('.'), false },
        .{ p.literal('#'), true },
    });
    const grid = p.grid(BitGrid, cell, p.noOp, p.nl);
    return grid.sepBy(p.literal("\n\n")).execute(ctx);
}

const Heights = [5]u8;
const top_mask: u64 = 0b11111;
const bot_mask: u64 = top_mask << 30;
const col_mask: u64 = 0b1000010000100001000010000100001;
pub fn pts(input: []BitGrid, allocator: std.mem.Allocator) !usize {
    for (input) |grid| {
        if (grid.width != 5 or grid.height != 7) {
            return error.InvalidInput;
        }
        const is_top = grid.bitset[0] & top_mask == top_mask;
        const is_bot = grid.bitset[0] & bot_mask == bot_mask;
        if (is_top == is_bot) return error.InvalidInput;
    }

    var heights = try allocator.alloc(Heights, input.len);
    var lock_count: usize = 0;
    var key_count: usize = 0;

    for (input) |grid| {
        if (grid.bitset[0] & top_mask != top_mask) continue;
        heights[lock_count] = calcHeights(grid);
        lock_count += 1;
    }
    for (input) |grid| {
        if (grid.bitset[0] & bot_mask != bot_mask) continue;
        heights[lock_count + key_count] = calcHeights(grid);
        key_count += 1;
    }

    std.debug.assert(lock_count + key_count == heights.len);
    const locks = heights[0..lock_count];
    const keys = heights[lock_count..];

    var count: usize = 0;
    for (locks) |lock| {
        next_key: for (keys) |key| {
            for (lock, key) |height_lock, height_key| {
                if (height_lock + height_key > 5) {
                    continue :next_key;
                }
            }
            count += 1;
        }
    }

    return count;
}

fn calcHeights(grid: BitGrid) Heights {
    const data = grid.bitset[0];
    var heights: Heights = undefined;
    var mask = col_mask;
    for (heights[0..]) |*height| {
        height.* = @popCount(data & mask) - 1;
        mask <<= 1;
    }
    return heights;
}

const test_input =
    \\#####
    \\.####
    \\.####
    \\.####
    \\.#.#.
    \\.#...
    \\.....
    \\
    \\#####
    \\##.##
    \\.#.##
    \\...##
    \\...#.
    \\...#.
    \\.....
    \\
    \\.....
    \\#....
    \\#....
    \\#...#
    \\#.#.#
    \\#.###
    \\#####
    \\
    \\.....
    \\.....
    \\#.#..
    \\###..
    \\###.#
    \\###.#
    \\#####
    \\
    \\.....
    \\.....
    \\.....
    \\#....
    \\#.#..
    \\#.#.#
    \\#####
;
test "day25::pts" {
    try fw.t.simple(@This(), pts, 3, test_input);
}
