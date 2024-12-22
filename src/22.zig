const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

pub fn parse(ctx: fw.p.ParseContext) ?[]u24 {
    const p = fw.p;
    return p.nr(u24).sepBy(p.nl).execute(ctx);
}

pub fn pt1(numbers: []u24) u64 {
    var sum: u64 = 0;
    for (numbers) |initial| {
        var n = initial;
        for (0..2000) |_| {
            n = getNextSecretNr(n);
        }
        sum += n;
    }
    return sum;
}

const Delta = u8;
const PackedDelta = u32;
const delta_bits = 8;

pub fn pt2(numbers: []u24, allocator: Allocator) !u32 {
    var seen_deltas = std.AutoHashMap(PackedDelta, void).init(allocator);
    defer seen_deltas.deinit();
    try seen_deltas.ensureTotalCapacity(2000 - 3);
    var gains = std.AutoHashMap(PackedDelta, u32).init(allocator);
    defer gains.deinit();

    for (numbers) |initial| {
        var window = Window.init(initial);

        var deltas: PackedDelta = 0;
        for (0..3) |_| {
            deltas <<= delta_bits;
            deltas |= window.delta();
            window = window.move();
        }

        seen_deltas.clearRetainingCapacity();
        for (0..2000 - 3) |_| {
            const gain = window.b;
            deltas <<= delta_bits;
            deltas |= window.delta();
            window = window.move();
            const res = try seen_deltas.getOrPut(deltas);
            if (res.found_existing) continue;
            const entry = try gains.getOrPutValue(deltas, 0);
            entry.value_ptr.* += gain;
        }
    }

    var max: u32 = 0;
    var iter = gains.valueIterator();
    while (iter.next()) |value| {
        max = @max(max, value.*);
    }

    return max;
}

const Window = struct {
    n: u24,
    a: u4,
    b: u4,

    fn delta(self: Window) Delta {
        return @bitCast(@as(i8, self.b) - @as(i8, self.a));
    }

    fn init(initial: u24) Window {
        const next = getNextSecretNr(initial);
        return Window{
            .a = @truncate(initial % 10),
            .b = @truncate(next % 10),
            .n = next,
        };
    }

    fn move(self: Window) Window {
        const next = getNextSecretNr(self.n);
        return Window{
            .a = self.b,
            .b = @truncate(next % 10),
            .n = next,
        };
    }
};

fn getNextSecretNr(n: u24) u24 {
    const a = n ^ (n << 6);
    const b = a ^ (a >> 5);
    const c = b ^ (b << 11);
    return @truncate(c);
}

test "day22::mixing" {
    const t = std.testing;
    var n: u24 = 123;
    for (&[_]u24{
        15887950,
        16495136,
        527345,
        704524,
        1553684,
        12683156,
        11100544,
        12249484,
        7753432,
        5908254,
    }) |expected| {
        n = getNextSecretNr(n);
        try t.expectEqual(expected, n);
    }
}
test "day22::pt1" {
    try fw.t.simple(@This(), pt1, 37327623, "1\n10\n100\n2024");
}
test "day22::pt2" {
    try fw.t.simple(@This(), pt2, 23, "1\n2\n3\n2024");
}
