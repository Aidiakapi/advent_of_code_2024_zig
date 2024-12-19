const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Input = struct {
    sources: [][]const u8,
    targets: [][]const u8,
};

pub fn parse(ctx: fw.p.ParseContext) ?Input {
    const p = fw.p;
    const word = p.takeWhile(std.ascii.isAlphabetic);
    const sources = word.sepBy(p.literal(", "));
    const targets = word.sepBy(p.nl);
    return p.allOf(
        Input,
        .{ sources, p.literal("\n\n").then(targets) },
    ).execute(ctx);
}

pub fn pt1(input: Input, allocator: Allocator) !u64 {
    return pts(false, input, allocator);
}

pub fn pt2(input: Input, allocator: Allocator) !u64 {
    return pts(true, input, allocator);
}

fn pts(comptime is_pt2: bool, input: Input, allocator: Allocator) !u64 {
    var visitor = try Visitor(is_pt2).init(allocator, input.sources);
    defer visitor.deinit();
    return try visitor.solve(input.targets);
}

fn Visitor(comptime count_ways: bool) type {
    const Res = if (count_ways) usize else bool;
    const Cache = std.AutoHashMap([*]const u8, Res);
    return struct {
        const Self = @This();
        set: InputSet,
        cache: Cache,

        pub fn init(allocator: Allocator, sources: [][]const u8) !Self {
            const set = try toSet(allocator, sources);
            return .{
                .set = set,
                .cache = Cache.init(allocator),
            };
        }
        pub fn deinit(self: *Self) void {
            self.cache.deinit();
            self.set.deinit();
            self.* = undefined;
        }

        pub fn solve(self: *Self, targets: [][]const u8) !u64 {
            var res: u64 = 0;
            for (targets) |target| {
                const ways = try self.canConstruct(target);
                if (count_ways) {
                    res += ways;
                } else if (ways) {
                    res += 1;
                }
            }
            return res;
        }

        pub fn canConstruct(self: *Self, target: []const u8) Allocator.Error!Res {
            if (target.len == 0) return if (count_ways) 1 else true;
            if (self.cache.get(target.ptr)) |cached| return cached;
            const res = try canConstructImpl(self, target);
            try self.cache.put(target.ptr, res);
            return res;
        }
        fn canConstructImpl(self: *Self, target: []const u8) Allocator.Error!Res {
            var window: u64 = 0;
            var ways: usize = 0;
            for (target[0..@min(8, target.len)], 0..) |byte, i| {
                window <<= 8;
                window |= byte;
                if (!self.set.contains(window)) continue;
                const child_ways = try canConstruct(self, target[i + 1 ..]);
                if (count_ways) {
                    ways += child_ways;
                    continue;
                }
                if (child_ways) return true;
            }
            return if (count_ways) ways else false;
        }
    };
}

const ConstructCache = std.AutoHashMap([*]const u8, bool);

const InputSet = std.AutoHashMap(u64, void);
fn toSet(allocator: Allocator, sources: [][]const u8) !InputSet {
    var set = InputSet.init(allocator);
    errdefer set.deinit();
    for (sources) |source| {
        if (source.len == 0 or source.len > 8) {
            return error.NotSupported;
        }
        var res: u64 = 0;
        for (source) |byte| {
            res <<= 8;
            res |= byte;
        }
        const getOrPutRes = try set.getOrPut(res);
        if (getOrPutRes.found_existing) {
            return error.DuplicateSource;
        }
    }
    return set;
}

const test_input =
    \\r, wr, b, g, bwu, rb, gb, br
    \\
    \\brwrr
    \\bggr
    \\gbbr
    \\rrbgbr
    \\ubwu
    \\bwurrg
    \\brgr
    \\bbrgwb
;
test "day19::pt1" {
    try fw.t.simple(@This(), pt1, 6, test_input);
}
test "day19::pt2" {
    try fw.t.simple(@This(), pt2, 16, test_input);
}
