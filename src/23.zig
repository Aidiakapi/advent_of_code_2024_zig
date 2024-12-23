const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Computer = [2]u8;
const Edge = [2]Computer;

pub fn parse(ctx: fw.p.ParseContext) ?[]Edge {
    const p = fw.p;
    const c = p.allOf(Computer, .{ p.any, p.any });
    const e = p.allOf(Edge, .{ c, p.literal('-').then(c) });
    return e.sepBy(p.nl).execute(ctx);
}

const Graph = struct {
    const Connections = std.AutoHashMap(Edge, void);
    computers: []Computer,
    connections: Connections,

    pub fn init(edges: []Edge, allocator: Allocator) !Graph {
        var computers: []Computer = undefined;
        {
            const ComputerMap = std.AutoHashMap(Computer, void);
            var computer_map = ComputerMap.init(allocator);
            defer computer_map.deinit();
            for (edges) |edge| {
                try computer_map.put(edge[0], void{});
                try computer_map.put(edge[1], void{});
            }
            computers = try allocator.alloc(Computer, computer_map.count());
            var iter = computer_map.keyIterator();
            var i: usize = 0;
            while (iter.next()) |entry| {
                computers[i] = entry.*;
                i += 1;
            }
            std.debug.assert(i == computers.len);
        }

        var connections = Connections.init(allocator);
        errdefer connections.deinit();
        for (edges) |edge| {
            try connections.put(try normalize(edge), void{});
        }
        return .{
            .computers = computers,
            .connections = connections,
        };
    }

    fn normalize(edge: Edge) !Edge {
        return switch (compOrder(edge[0], edge[1])) {
            .lt => edge,
            .gt => .{ edge[1], edge[0] },
            .eq => error.SelfConnection,
        };
    }

    pub fn deinit(self: *Graph) void {
        const allocator = self.connections.allocator;
        self.connections.deinit();
        allocator.free(self.computers);
        self.* = undefined;
    }

    pub fn solvePt1(self: *const Graph) usize {
        var count: usize = 0;
        var edges = self.connections.keyIterator();
        while (edges.next()) |edge| {
            for (self.computers) |computer| {
                if (compOrder(edge.*[1], computer) != .lt) continue;
                const e0 = normalize(.{ computer, edge.*[0] }) catch unreachable;
                const e1 = normalize(.{ computer, edge.*[1] }) catch unreachable;
                if (!self.connections.contains(e0) or !self.connections.contains(e1))
                    continue;
                if (edge.*[0][0] == 't' or edge.*[1][0] == 't' or computer[0] == 't')
                    count += 1;
            }
        }
        return count;
    }

    pub fn solvePt2(self: *const Graph) ![]const u8 {
        var groups2 = List.init(self.connections.allocator);
        defer groups2.deinit();
        try groups2.ensureTotalCapacityPrecise(self.connections.count() * 2);
        var iter = self.connections.keyIterator();
        while (iter.next()) |edge| {
            groups2.addOneAssumeCapacity().* = edge.*[0];
            groups2.addOneAssumeCapacity().* = edge.*[1];
            compSort(groups2.items[groups2.items.len - 2 ..]);
        }

        const base = 3;
        const max = 14;
        var groups: [max - base]List = undefined;
        var group_index: usize = 0;
        defer for (groups[0..group_index]) |*group| {
            group.deinit();
        };

        while (group_index < groups.len) {
            const prev = if (group_index == 0) groups2 else groups[group_index - 1];
            const group_size = group_index + base;
            const group = try self.makeGroups(prev, group_size);
            groups[group_index] = group;
            group_index += 1;

            if (group.items.len == group_size) {
                const res = try self.connections.allocator.alloc(u8, 3 * group.items.len - 1);
                for (group.items, 0..) |computer, i| {
                    res[i * 3] = computer[0];
                    res[i * 3 + 1] = computer[1];
                    if (i * 3 + 2 < res.len) res[i * 3 + 2] = ',';
                }
                return res;
            }
        }

        return error.NoSolution;
    }

    const List = std.ArrayList(Computer);
    fn makeGroups(self: *const Graph, prev_groups: List, new_size: usize) !List {
        var groups = List.init(self.connections.allocator);
        errdefer groups.deinit();

        const prev_size = new_size - 1;
        std.debug.assert(prev_groups.items.len % prev_size == 0);
        var i: usize = 0;
        while (i < prev_groups.items.len) : (i += prev_size) {
            const prev = prev_groups.items[i .. i + prev_size];
            next_computer: for (self.computers) |new| {
                for (prev) |existing| {
                    const edge = normalize(.{ existing, new }) catch continue :next_computer;
                    if (!self.connections.contains(edge))
                        continue :next_computer;
                }
                try groups.ensureUnusedCapacity(new_size);
                groups.appendSliceAssumeCapacity(prev);
                groups.appendAssumeCapacity(new);
                compSort(groups.items[groups.items.len - new_size ..]);
            }
        }

        sortGroups(groups.items, new_size);
        dedupGroups(&groups, new_size);

        return groups;
    }

    fn sortGroups(groups: []Computer, size: usize) void {
        std.mem.sortUnstableContext(0, groups.len / size, struct {
            const Self = @This();
            groups: []Computer,
            size: usize,

            pub fn swap(self: Self, a: usize, b: usize) void {
                const ga: []Computer = self.groups[a * self.size .. a * self.size + self.size];
                const gb: []Computer = self.groups[b * self.size .. b * self.size + self.size];
                for (0..self.size) |i| {
                    std.mem.swap(Computer, &ga[i], &gb[i]);
                }
            }

            pub fn lessThan(self: Self, a: usize, b: usize) bool {
                const ga: []Computer = self.groups[a * self.size .. a * self.size + self.size];
                const gb: []Computer = self.groups[b * self.size .. b * self.size + self.size];
                const ba: []u8 = @as([*]u8, @ptrCast(ga.ptr))[0 .. self.size * 2];
                const bb: []u8 = @as([*]u8, @ptrCast(gb.ptr))[0 .. self.size * 2];
                return std.mem.order(u8, ba, bb) == .lt;
            }
        }{
            .groups = groups,
            .size = size,
        });
    }

    fn dedupGroups(groups: *List, size: usize) void {
        if (groups.items.len == 0) return;
        const count = groups.items.len / size;
        var read: usize = 1;
        var write: usize = 1;
        while (read < count) : (read += 1) {
            const curr = groups.items[read * size .. read * size + size];
            const last = groups.items[write * size - size .. write * size];
            if (std.mem.eql(Computer, curr, last)) continue;

            if (read != write) {
                const target = groups.items[write * size .. write * size + size];
                @memcpy(target, curr);
            }
            write += 1;
        }
        groups.shrinkAndFree(write * size);
    }
};

pub fn pt1(edges: []Edge, allocator: Allocator) !usize {
    var graph = try Graph.init(edges, allocator);
    defer graph.deinit();
    return graph.solvePt1();
}

pub fn pt2(edges: []Edge, allocator: Allocator) ![]const u8 {
    var graph = try Graph.init(edges, allocator);
    defer graph.deinit();
    return graph.solvePt2();
}

fn compEql(a: Computer, b: Computer) bool {
    return std.mem.eql(u8, &a, &b);
}

fn compOrder(a: Computer, b: Computer) std.math.Order {
    return std.mem.order(u8, &a, &b);
}

fn compSort(computers: []Computer) void {
    std.mem.sort(Computer, computers, void{}, struct {
        fn f(_: void, a: Computer, b: Computer) bool {
            return compOrder(a, b) == .lt;
        }
    }.f);
}

const test_input =
    \\kh-tc
    \\qp-kh
    \\de-cg
    \\ka-co
    \\yn-aq
    \\qp-ub
    \\cg-tb
    \\vc-aq
    \\tb-ka
    \\wh-tc
    \\yn-cg
    \\kh-ub
    \\ta-co
    \\de-co
    \\tc-td
    \\tb-wq
    \\wh-td
    \\ta-ka
    \\td-qp
    \\aq-cg
    \\wq-ub
    \\ub-vc
    \\de-ta
    \\wq-aq
    \\wq-vc
    \\wh-yn
    \\ka-de
    \\kh-ta
    \\co-tc
    \\wh-qp
    \\tb-vc
    \\td-yn
;
test "day::pt1" {
    try fw.t.simple(@This(), pt1, 7, test_input);
}
test "day::pt2" {
    try fw.t.simple(@This(), pt2, "co,de,ka,ta", test_input);
}
