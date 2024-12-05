const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const RulesAndLists = struct {
    rules: []Rule,
    lists: [][]u32,
};

const Rule = struct {
    a: u32,
    b: u32,
};

pub fn parse(ctx: fw.p.ParseContext) ?RulesAndLists {
    const p = fw.p;
    const nr = p.nr(u32);
    const rule = p.allOf(Rule, .{ nr, p.literal('|').then(nr) });
    const rules = rule.sepBy(p.nl);
    const lists = nr.sepBy(p.literal(',')).sepBy(p.nl);
    const rulesAndLists = p.allOf(RulesAndLists, .{ rules, p.literal("\n\n").then(lists) });
    return rulesAndLists.execute(ctx);
}

pub fn pt1(input: RulesAndLists, allocator: Allocator) u32 {
    var lookup = RuleLookup.init(input.rules, allocator);
    defer lookup.deinit(allocator);
    var result: u32 = 0;
    for (input.lists) |list| {
        if (lookup.isOrdered(list)) {
            result += list[list.len / 2];
        }
    }
    return result;
}

pub fn pt2(input: RulesAndLists, allocator: Allocator) u32 {
    var lookup = RuleLookup.init(input.rules, allocator);
    defer lookup.deinit(allocator);
    var result: u32 = 0;
    for (input.lists) |list| {
        if (lookup.isOrdered(list)) {
            continue;
        }
        const res = allocator.alloc(u32, list.len) catch @panic("OOM");
        defer allocator.free(res);
        @memcpy(res, list);
        lookup.reorder(res);
        result += res[res.len / 2];
    }
    return result;
}

const RuleList = std.SinglyLinkedList(u32);
const RuleLookup = struct {
    nodes: []RuleList.Node,
    lookup: std.AutoHashMapUnmanaged(u32, RuleList),

    pub fn init(rules: []Rule, allocator: Allocator) RuleLookup {
        var self = RuleLookup{
            .nodes = allocator.alloc(RuleList.Node, rules.len) catch @panic("OOM"),
            .lookup = std.AutoHashMapUnmanaged(u32, RuleList).empty,
        };
        self.lookup.ensureTotalCapacity(allocator, @intCast(rules.len / 2)) catch @panic("OOM");
        for (rules, self.nodes) |rule, *node| {
            node.* = .{ .data = rule.b };
            const res = self.lookup.getOrPut(allocator, rule.a) catch @panic("OOM");
            if (!res.found_existing) {
                res.value_ptr.* = .{};
            }
            res.value_ptr.prepend(node);
        }
        return self;
    }

    pub fn getNrsDisallowedBefore(self: RuleLookup, key: u32) ?*RuleList.Node {
        return (self.lookup.get(key) orelse return null).first;
    }

    pub fn deinit(self: *RuleLookup, allocator: Allocator) void {
        self.lookup.deinit(allocator);
        allocator.free(self.nodes);
        self.* = undefined;
    }

    pub fn isOrdered(self: RuleLookup, list: []const u32) bool {
        for (list, 1..) |nr, i| {
            const disallowed_head = self.getNrsDisallowedBefore(nr);
            for (list[0..i]) |predecessor| {
                var disallowed_node = disallowed_head;
                while (disallowed_node) |node| : (disallowed_node = node.*.next) {
                    if (node.data == predecessor) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    pub fn reorder(self: RuleLookup, reordered: []u32) void {
        var i: usize = 1;
        while (i < reordered.len) : (i += 1) {
            const nr = reordered[i];
            const disallowed_head = self.getNrsDisallowedBefore(nr);
            outer: for (0..i) |j| {
                const predecessor = reordered[j];
                var disallowed_node = disallowed_head;
                while (disallowed_node) |node| : (disallowed_node = node.*.next) {
                    if (node.data != predecessor) continue;
                    // The number at index i actually must be before the number at index j.
                    // Reorder the sequence, to achieve that. At this point, the sequence is,
                    // either still correctly ordered up until index i, or the input is invalid
                    // and specifies some indeterminate order. Regardless, we terminate.
                    std.mem.copyBackwards(u32, reordered[j + 1 .. i + 1], reordered[j..i]);
                    reordered[j] = nr;
                    break :outer;
                }
            }
        }
        std.debug.assert(self.isOrdered(reordered));
    }
};

const test_rules =
    \\47|53
    \\97|13
    \\97|61
    \\97|47
    \\75|29
    \\61|13
    \\75|53
    \\29|13
    \\97|29
    \\53|29
    \\61|53
    \\97|53
    \\61|29
    \\47|13
    \\75|47
    \\97|75
    \\47|61
    \\75|61
    \\47|29
    \\75|13
    \\53|13
    \\
    \\
;
test "day05::pt1" {
    try fw.t.simpleMulti(@This(), pt1, .{
        .{ 61, test_rules ++ "75,47,61,53,29" },
        .{ 53, test_rules ++ "97,61,53,29,13" },
        .{ 29, test_rules ++ "75,29,13" },
        .{ 0, test_rules ++ "75,97,47,61,53" },
        .{ 0, test_rules ++ "61,13,29" },
        .{ 0, test_rules ++ "97,13,75,29,47" },
    });
}
test "day05::pt2" {
    try fw.t.simpleMulti(@This(), pt2, .{
        .{ 0, test_rules ++ "75,47,61,53,29" },
        .{ 0, test_rules ++ "97,61,53,29,13" },
        .{ 0, test_rules ++ "75,29,13" },
        .{ 47, test_rules ++ "75,97,47,61,53" },
        .{ 29, test_rules ++ "61,13,29" },
        .{ 47, test_rules ++ "97,13,75,29,47" },
    });
}
