const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Int = u64;

pub fn parse(ctx: fw.p.ParseContext) ?[]Int {
    const p = fw.p;
    return p.nr(Int).sepBy(p.literal(' ')).execute(ctx);
}

pub fn pt1(numbers: []Int, allocator: Allocator) !Int {
    return pts(numbers, 25, allocator);
}

pub fn pt2(numbers: []Int, allocator: Allocator) !Int {
    return pts(numbers, 75, allocator);
}

const Table = std.AutoHashMap(Int, Int);
fn pts(numbers: []Int, steps: u32, allocator: Allocator) !Int {
    const initial_capacity: u32 = if (steps >= 75) 4096 else 256;
    var table1 = Table.init(allocator);
    defer table1.deinit();
    try table1.ensureTotalCapacity(initial_capacity);
    var table2 = Table.init(allocator);
    defer table2.deinit();
    try table2.ensureTotalCapacity(initial_capacity);
    for (numbers) |number| {
        (try table1.getOrPutValue(number, 0)).value_ptr.* += 1;
    }

    for (0..steps) |i| {
        const source: *Table, const target: *Table = if (i % 2 == 0) .{ &table1, &table2 } else .{ &table2, &table1 };
        target.clearRetainingCapacity();
        var iter = source.iterator();
        while (iter.next()) |entry| {
            try countStones(entry.key_ptr.*, entry.value_ptr.*, target);
        }
    }

    const result: *Table = if (steps % 2 == 0) &table1 else &table2;
    var count: u64 = 0;
    var iter = result.valueIterator();
    while (iter.next()) |value| {
        count += value.*;
    }

    return count;
}

fn countStones(number: Int, count: Int, table: *Table) !void {
    if (number == 0) {
        (try table.getOrPutValue(1, 0)).value_ptr.* += count;
        return;
    }
    const digit_count = std.math.log10_int(number);
    if (digit_count % 2 == 0) {
        (try table.getOrPutValue(number * 2024, 0)).value_ptr.* += count;
        return;
    }
    var base: Int = 10;
    var rem = digit_count / 2;
    while (rem > 0) : (rem -= 1) {
        base *= 10;
    }
    const left = number / base;
    const right = number % base;
    (try table.getOrPutValue(left, 0)).value_ptr.* += count;
    (try table.getOrPutValue(right, 0)).value_ptr.* += count;
}

fn ptTest(comptime steps: Int) fn (numbers: []Int, allocator: Allocator) anyerror!Int {
    return struct {
        fn f(numbers: []Int, allocator: Allocator) !Int {
            return pts(numbers, steps, allocator);
        }
    }.f;
}
test "day11::pts" {
    try fw.t.simple(@This(), ptTest(1), 7, "0 1 10 99 999");
    try fw.t.simple(@This(), ptTest(6), 22, "125 17");
    try fw.t.simple(@This(), ptTest(25), 55312, "125 17");
}
