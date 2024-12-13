const std = @import("std");
const fw = @import("fw");

pub fn parse(ctx: fw.p.ParseContext) ?[]u4 {
    const p = fw.p;
    return p.digit.sepBy(p.noOp).execute(ctx);
}

pub fn pt1(numbers: []u4) u64 {
    std.debug.assert(numbers.len % 2 == 1);
    const Remainder = struct {
        items: []u4,
        value: u64,
        quantity: u64 = 0,
    };
    var remainder = Remainder{
        .items = numbers,
        .value = numbers.len / 2 + 1,
    };

    var value: u64 = 0;
    var output = Output{};
    outer: while (true) {
        output.append(remainder.items[0], value);
        value += 1;
        if (remainder.items.len == 1) {
            break;
        }

        var empty_spots: u64 = remainder.items[1];
        remainder.items = remainder.items[2..];
        while (empty_spots > 0) {
            if (remainder.quantity == 0) {
                if (remainder.items.len <= 1) {
                    continue :outer;
                }
                remainder.value -= 1;
                remainder.quantity = remainder.items[remainder.items.len - 1];
                remainder.items = remainder.items[0 .. remainder.items.len - 2];
            }

            const count = @min(remainder.quantity, empty_spots);
            output.append(count, remainder.value);
            empty_spots -= count;
            remainder.quantity -= count;
        }
    }
    output.append(remainder.quantity, remainder.value);
    return output.checksum;
}

pub fn pt2(numbers: []u4, allocator: std.mem.Allocator) !u64 {
    const Block = struct {
        index: u32,
        size: u32,
    };
    const half_len = numbers.len / 2;

    const disk_indices = try allocator.alloc(u32, numbers.len);
    defer allocator.free(disk_indices);

    {
        var disk_index: u32 = 0;
        for (numbers, disk_indices) |number, *out| {
            out.* = disk_index;
            disk_index += number;
        }
    }

    const open_blocks = try allocator.alloc(Block, half_len);
    defer allocator.free(open_blocks);

    for (open_blocks, 0..) |*open_block, i| {
        const number_index = i * 2 + 1;
        const size = numbers[number_index];
        const index = disk_indices[number_index];
        open_block.* = .{ .index = index, .size = size };
    }

    var checksum: u64 = 0;
    outer: for (0..half_len) |segment| {
        const value = half_len - segment;
        const number_index = numbers.len - 1 - segment * 2;
        const size = numbers[number_index];
        const disk_index = disk_indices[number_index];
        for (open_blocks) |*open_block| {
            if (open_block.*.index > disk_index) {
                break;
            }
            if (size <= open_block.*.size) {
                checksum += partialChecksum(open_block.*.index, size, value);
                open_block.*.index += size;
                open_block.*.size -= size;
                continue :outer;
            }
        }
        checksum += partialChecksum(disk_index, size, value);
    }

    return checksum;
}

const Output = struct {
    checksum: u64 = 0,
    length: u64 = 0,

    fn append(self: *Output, count: u64, value: u64) void {
        self.checksum += partialChecksum(self.length, count, value);
        self.length += count;
    }
};

fn partialChecksum(start: u64, count: u64, value: u64) u64 {
    const factor = triangleSub1(start + count) - triangleSub1(start);
    return factor * value;
}

fn triangleSub1(v: u64) u64 {
    return if (v == 0) 0 else triangle(v - 1);
}
fn triangle(v: u64) u64 {
    return v * (v + 1) / 2;
}

const test_input = "2333133121414131402";
test "day09::pt1" {
    try fw.t.simple(@This(), pt1, 1928, test_input);
}
test "day09::pt2" {
    try fw.t.simple(@This(), pt2, 2858, test_input);
}
