const std = @import("std");
const fw = @import("fw");

fn parseNr(remainder: *[]const u8) ?u32 {
    var len: u32 = 0;
    var nr: u32 = 0;
    while (len < 3 and (remainder.*.len > 0 and std.ascii.isDigit(remainder.*[0]))) {
        nr = nr * 10 + (remainder.*[0] - '0');
        remainder.* = remainder.*[1..];
        len += 1;
    }
    return if (len != 0) nr else null;
}
fn parseChar(remainder: *[]const u8, c: u8) bool {
    if (remainder.*.len == 0 or remainder.*[0] != c) {
        return false;
    }
    remainder.* = remainder.*[1..];
    return true;
}

fn parseNrsParenClose(remainder: *[]const u8) ?struct { u32, u32 } {
    const a = if (parseNr(remainder)) |v| v else return null;
    if (!parseChar(remainder, ',')) return null;
    const b = if (parseNr(remainder)) |v| v else return null;
    if (!parseChar(remainder, ')')) return null;
    return .{ a, b };
}

pub fn pt1(input: []const u8) usize {
    var sum: usize = 0;
    var remainder = input;
    while (std.mem.indexOf(u8, remainder, "mul(")) |p| {
        remainder = remainder[p + 4 ..];
        const nr = if (parseNrsParenClose(&remainder)) |v| v else continue;
        sum += nr[0] * nr[1];
    }
    return sum;
}

pub fn pt2(input: []const u8) usize {
    var sum: usize = 0;
    var remainder = input;
    while (remainder.len > 0) {
        if (std.mem.indexOf(u8, remainder, "don't()")) |disable_at| {
            sum += pt1(remainder[0..disable_at]);
            if (std.mem.indexOfPos(u8, remainder, disable_at + 7, "do()")) |re_enable_at| {
                remainder = remainder[re_enable_at + 4 ..];
            } else {
                return sum;
            }
        } else {
            return sum + pt1(remainder);
        }
    }
    return sum;
}

test "day03::pt1" {
    try fw.t.simple(@This(), pt1, 161,
        \\xmul(2,4)%&mul[3,7]!@^do_not_mul(5,5)+mul(32,64]then(mul(11,8)mul(8,5))
    );
}
test "day03::pt2" {
    try fw.t.simple(@This(), pt2, 48,
        \\xmul(2,4)&mul[3,7]!^don't()_mul(5,5)+mul(32,64](mul(11,8)undo()?mul(8,5))
    );
}
