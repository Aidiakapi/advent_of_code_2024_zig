const std = @import("std");
const fw = @import("fw");

const Parsed = [][]u32;

pub fn parse(ctx: fw.p.ParseContext) ?Parsed {
    const p = fw.p;
    const line = p.nr(u32).sepBy(p.literal(' '));
    return line.sepBy(p.nl).execute(ctx);
}

pub fn pt1(input: Parsed) usize {
    return pts(input, isSafePt1);
}

pub fn pt2(input: Parsed) usize {
    return pts(input, isSafePt2);
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

fn isSafePt1(line: []const u32) bool {
    if (line.len < 2) {
        return true;
    }
    const is_asc = line[0] < line[1];
    return if (is_asc) isSafeSeq(line, true) else isSafeSeq(line, false);
}

fn isSafePt2(line: []const u32) bool {
    return isSafePt2Core(line, true) or isSafePt2Core(line, false);
}

fn isSafePt2Core(line: []const u32, comptime is_asc: bool) bool {
    for (1..line.len) |i| {
        const a = line[i - 1];
        const b = line[i];
        if (isSafePair(a, b, is_asc)) {
            continue;
        }

        // from the sequence:
        // x y a b m n
        // `x y a` is guaranteed to be valid
        // `a b` is guaranteed to be invalid, one must be removed
        if (i + 1 == line.len) {
            return true; // sequence is actually `x y a b`, safe to remove `b`
        }
        if (!isSafeSeq(line[i + 1 ..], is_asc)) {
            return false; // sequence `m n` is not safe in any case
        }
        if (isSafePair(a, line[i + 1], is_asc)) {
            return true; // `a m` is legal, remove `b`
        }
        if (!isSafePair(b, line[i + 1], is_asc)) {
            return false; // `b m` is illegal, cannot remove either
        }
        if (i == 1) {
            return true; // sequence is actually `a b m n`, remove `a`
        }
        if (isSafePair(line[i - 2], b, is_asc)) {
            return true; // `y b` is legal, remove `a`
        }
        // neither `a` nor `b` can be removed safely
        return false;
    }
    return true;
}

fn isSafeSeq(line: []const u32, comptime is_asc: bool) bool {
    if (line.len < 2) {
        return true;
    }
    for (line[0 .. line.len - 1], line[1..]) |a, b| {
        if (!isSafePair(a, b, is_asc)) {
            return false;
        }
    }
    return true;
}

fn isSafePair(a: u32, b: u32, comptime is_asc: bool) bool {
    const max_delta = 3;
    return if (is_asc)
        a < b and (b - a) <= max_delta
    else
        b < a and (a - b) <= max_delta;
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
    try fw.t.simpleMulti(@This(), pt2, .{
        .{ 1, "30 40 41 42 43" },
        .{ 1, "50 40 41 42 43" },
        .{ 1, "40 30 41 42 43" },
        .{ 1, "40 50 41 42 43" },
        .{ 1, "40 41 30 42 43" },
        .{ 1, "40 41 50 42 43" },
        .{ 1, "40 41 42 30 43" },
        .{ 1, "40 41 42 50 43" },
        .{ 1, "40 41 42 43 30" },
        .{ 1, "40 41 42 43 50" },
        .{ 0, "40 40 41 42 43 30" },
        .{ 0, "40 41 41 42 43 50" },
    });
}
