const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Int = u64;

pub fn parse(ctx: fw.p.ParseContext) ?[]Int {
    const p = fw.p;
    return p.nr(Int).sepBy(p.literal(' ')).execute(ctx);
}

pub fn pt1(numbers: []Int, allocator: Allocator) Int {
    return pts(numbers, 25, allocator);
}

pub fn pt2(numbers: []Int, allocator: Allocator) Int {
    return pts(numbers, 75, allocator);
}

const Cache = std.AutoHashMap(struct { Int, u32 }, Int);
fn pts(numbers: []Int, steps: u32, allocator: Allocator) Int {
    var cache = Cache.init(allocator);
    var total: Int = 0;
    for (numbers) |number| {
        total += countStones(number, steps, &cache);
    }
    return total;
}

fn countStones(number: Int, steps: u32, cache: *Cache) Int {
    if (steps == 0) {
        return 1;
    }
    if (cache.get(.{ number, steps })) |cached| {
        return cached;
    }
    const stone_count = countStonesCore(number, steps, cache);
    _ = cache.getOrPutValue(.{ number, steps }, stone_count) catch @panic("OOM");
    return stone_count;
}

fn countStonesCore(number: Int, steps: u32, cache: *Cache) Int {
    if (number == 0) {
        return countStones(1, steps - 1, cache);
    }
    const digit_count = std.math.log10_int(number);
    if (digit_count % 2 == 0) {
        return countStones(number * 2024, steps - 1, cache);
    }
    var base: Int = 10;
    var rem = digit_count / 2;
    while (rem > 0) : (rem -= 1) {
        base *= 10;
    }
    const left = number / base;
    const right = number % base;
    return countStones(left, steps - 1, cache) +
        countStones(right, steps - 1, cache);
}

fn ptTest(comptime steps: Int) fn (numbers: []Int, allocator: Allocator) Int {
    return struct {
        fn f(numbers: []Int, allocator: Allocator) Int {
            return pts(numbers, steps, allocator);
        }
    }.f;
}
test "day11::pts" {
    try fw.t.simple(@This(), ptTest(1), 7, "0 1 10 99 999");
    try fw.t.simple(@This(), ptTest(6), 22, "125 17");
    try fw.t.simple(@This(), ptTest(25), 55312, "125 17");
}
