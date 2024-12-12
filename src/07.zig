const std = @import("std");
const fw = @import("fw");

const Entry = struct {
    total: u64,
    nrs: []u64,
};

pub fn parse(ctx: fw.p.ParseContext) ?[]Entry {
    const p = fw.p;
    const nr = p.nr(u64);
    const entry = p.allOf(Entry, .{ nr, p.literal(": ").then(nr.sepBy(p.literal(' '))) });
    return entry.sepBy(p.nl).execute(ctx);
}

pub fn pt1(entries: []Entry) u64 {
    return pts(false, entries);
}

pub fn pt2(entries: []Entry) u64 {
    return pts(true, entries);
}

fn pts(comptime allow_concat: bool, entries: []Entry) u64 {
    var total: u64 = 0;
    for (entries) |entry| {
        if (canMakeCorrect(allow_concat, entry)) total += entry.total;
    }
    return total;
}

fn canMakeCorrect(comptime allow_concat: bool, entry: Entry) bool {
    if (entry.nrs.len == 1) {
        return entry.total == entry.nrs[0];
    }

    const v = entry.nrs[entry.nrs.len - 1];
    if (v > entry.total) {
        return false;
    }
    const rem = entry.nrs[0 .. entry.nrs.len - 1];
    if (entry.total % v == 0) {
        if (canMakeCorrect(allow_concat, .{ .total = entry.total / v, .nrs = rem })) {
            return true;
        }
    }
    if (allow_concat) {
        const digit_count = std.math.log10_int(v) + 1;
        const base = std.math.powi(u64, 10, digit_count) catch unreachable;
        const mask = entry.total % base;
        if (mask == v and canMakeCorrect(allow_concat, .{ .total = entry.total / base, .nrs = rem })) {
            return true;
        }
    }

    return @call(
        .always_tail,
        canMakeCorrect,
        .{ allow_concat, .{ .total = entry.total - v, .nrs = rem } },
    );
}

const test_input =
    \\190: 10 19
    \\3267: 81 40 27
    \\83: 17 5
    \\156: 15 6
    \\7290: 6 8 6 15
    \\161011: 16 10 13
    \\192: 17 8 14
    \\21037: 9 7 18 13
    \\292: 11 6 16 20
;
test "day07::pt1" {
    try fw.t.simple(@This(), pt1, 3749, test_input);
}
test "day07::pt2" {
    try fw.t.simple(@This(), pt2, 11387, test_input);
}
