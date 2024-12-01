const fw = @import("fw");
const std = @import("std");

pub fn parse(ctx: fw.p.ParseContext) ?[]struct { u32, u32 } {
    const p = fw.p;
    const n = p.nr(u32);
    const line = n.with(p.literal("   ").then(n));
    return line.sepBy(p.nl).execute(ctx);
}

fn sortInputLists(input: []const struct { u32, u32 }, allocator: std.mem.Allocator) !struct { []const u32, []const u32 } {
    const mem = try allocator.alloc(u32, input.len * 2);

    const r1 = mem[0..input.len];
    const r2 = mem[input.len..];
    for (input, r1, r2) |t, *v1, *v2| {
        v1.* = t[0];
        v2.* = t[1];
    }

    std.mem.sortUnstable(u32, r1, void{}, std.sort.asc(u32));
    std.mem.sortUnstable(u32, r2, void{}, std.sort.asc(u32));
    return .{ r1, r2 };
}

pub fn pt1(input: []const struct { u32, u32 }, allocator: std.mem.Allocator) !u32 {
    const lists = try sortInputLists(input, allocator);
    var total: u32 = 0;
    for (lists[0], lists[1]) |v1, v2| {
        total += if (v1 > v2) v1 - v2 else v2 - v1;
    }
    return total;
}

fn Run(comptime T: type) type {
    return struct {
        len: usize,
        value: T,
    };
}

fn RunIterator(comptime T: type) type {
    return struct {
        data: []const T,
        index: usize,

        pub fn next(self: *@This()) ?Run(T) {
            if (self.index >= self.data.len) {
                return null;
            }
            const start = self.index;
            while (self.index < self.data.len and self.data[start] == self.data[self.index]) {
                self.index += 1;
            }
            return .{ .len = self.index - start, .value = self.data[start] };
        }
    };
}

fn runs(comptime T: type, data: []const T) RunIterator(T) {
    return .{
        .data = data,
        .index = 0,
    };
}

pub fn pt2(input: []const struct { u32, u32 }, allocator: std.mem.Allocator) !usize {
    const lists = try sortInputLists(input, allocator);
    var iter1 = runs(u32, lists[0]);
    var iter2 = runs(u32, lists[1]);

    var total: usize = 0;
    var run1 = iter1.next() orelse return total;
    var run2 = iter2.next() orelse return total;
    while (true) {
        while (true) {
            if (run1.value < run2.value) {
                run1 = iter1.next() orelse return total;
                continue;
            }
            if (run1.value > run2.value) {
                run2 = iter2.next() orelse return total;
                continue;
            }
            break;
        }
        total += run1.len * run2.len * run1.value;
        run1 = iter1.next() orelse return total;
        run2 = iter2.next() orelse return total;
    }
}

const test_input =
    \\3   4
    \\4   3
    \\2   5
    \\1   3
    \\3   9
    \\3   3
;
test "day01::pt1" {
    try fw.t.simple(@This(), pt1, 11, test_input);
}
test "day01::pt2" {
    try fw.t.simple(@This(), pt2, 31, test_input);
}
