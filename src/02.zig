const std = @import("std");
const fw = @import("fw");

const Parsed = [][]u32;

pub fn parse(ctx: fw.p.ParseContext) ?Parsed {
    const p = fw.p;
    const line = p.nr(u32).sepBy(p.literal(' '));
    return line.sepBy(p.nl).execute(ctx);
}

fn isSafePt1(line: []const u32) bool {
    if (line.len < 2) {
        return true;
    }
    const is_asc = line[0] < line[1];
    for (line[0 .. line.len - 1], line[1..]) |a, b| {
        if (a == b) {
            return false;
        }
        const curr_asc = a < b;
        if (curr_asc != is_asc) {
            return false;
        }
        const delta = if (is_asc) b - a else a - b;
        if (delta > 3) {
            return false;
        }
    }
    return true;
}

fn isSafePt2(line: []const u32) bool {
    std.debug.assert(line.len <= 128);
    var buf: [128]u32 = undefined;
    for (0..line.len) |i| {
        @memcpy(buf[0..i], line[0..i]);
        @memcpy(buf[i .. line.len - 1], line[i + 1 ..]);
        if (isSafePt1(buf[0 .. line.len - 1])) {
            return true;
        }
    }
    return false;
}

fn pts(input: Parsed, isSafeFn: fn (line: []const u32) bool) usize {
    var safeLineCount: usize = 0;
    for (input) |line| {
        if (isSafeFn(line)) {
            safeLineCount += 1;
        }
    }
    return safeLineCount;
}

pub fn pt1(input: Parsed) usize {
    return pts(input, isSafePt1);
}

pub fn pt2(input: Parsed) usize {
    return pts(input, isSafePt2);
}

const test_input =
    \\7 6 4 2 1
    \\1 2 7 8 9
    \\9 7 6 2 1
    \\1 3 2 4 5
    \\8 6 4 4 1
    \\1 3 6 7 9
;
test "day02::pt1" {
    try fw.t.simple(@This(), pt1, 2, test_input);
}
test "day02::pt2" {
    try fw.t.simple(@This(), pt2, 4, test_input);
}
