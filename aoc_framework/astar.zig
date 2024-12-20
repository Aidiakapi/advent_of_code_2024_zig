const std = @import("std");
const Allocator = std.mem.Allocator;
const Order = std.math.Order;

pub const AStarConfig = struct {
    path: enum { none, single, all } = .single,
};

pub fn AStar(Context: type, comptime config: AStarConfig) type {
    const Node: type = Context.Node;
    const Cost: type = Context.Cost;
    const Entry = struct {
        node: Node,
        cost: Cost,
        cost_with_heuristic: Cost,

        pub fn heuristic(self: @This()) Cost {
            return self.cost_with_heuristic - self.cost;
        }
    };

    const CostMap = std.AutoHashMapUnmanaged(Node, Cost);
    const ParentMap = switch (config.path) {
        .none => struct {
            const Self = @This();
            inline fn init() Self {
                return .{};
            }
            inline fn add(_: Self, _: Allocator, _: Node, _: Node) !void {}
            inline fn overwrite(_: Self, _: Allocator, _: Node, _: Node) !void {}
            inline fn deinit(_: Self, _: Allocator) void {}
            inline fn clear(_: Self) void {}
        },
        .single => struct {
            const Self = @This();
            const Map = std.AutoHashMapUnmanaged(Node, Node);
            map: Map = Map.empty,
            inline fn add(self: *Self, allocator: Allocator, into: Node, from: Node) !void {
                return self.map.put(allocator, into, from);
            }
            inline fn overwrite(self: *Self, allocator: Allocator, into: Node, from: Node) !void {
                return self.add(allocator, into, from);
            }
            inline fn deinit(self: *Self, allocator: Allocator) void {
                self.map.deinit(allocator);
            }
            inline fn clear(self: *Self) void {
                self.map.clearRetainingCapacity();
            }
        },
        .all => struct {
            const Self = @This();
            const Storage = std.ArrayListUnmanaged(Record);
            const Record = struct {
                from: Node,
                next: u32,
            };
            const none = std.math.maxInt(u32);
            const Map = std.AutoHashMapUnmanaged(Node, u32);
            map: Map = Map.empty,
            storage: Storage = Storage.empty,
            inline fn add(self: *Self, allocator: Allocator, into: Node, from: Node) !void {
                const res = try self.map.getOrPut(allocator, into);
                const index: u32 = @intCast(self.storage.items.len);
                (try self.storage.addOne(allocator)).* = .{
                    .from = from,
                    .next = if (res.found_existing) res.value_ptr.* else none,
                };
                res.value_ptr.* = index;
            }
            inline fn overwrite(self: *Self, allocator: Allocator, into: Node, from: Node) !void {
                const res = try self.map.getOrPut(allocator, into);
                const record: Record = .{ .from = from, .next = none };
                if (res.found_existing) {
                    self.storage.items[res.value_ptr.*] = record;
                    return;
                }
                const index: u32 = @intCast(self.storage.items.len);
                (try self.storage.addOne(allocator)).* = record;
                res.value_ptr.* = index;
            }
            inline fn deinit(self: *Self, allocator: Allocator) void {
                self.map.deinit(allocator);
                self.storage.deinit(allocator);
            }
            inline fn clear(self: *Self) void {
                self.map.clearRetainingCapacity();
                self.storage.clearRetainingCapacity();
            }

            const Iterator = struct {
                data: *const Self,
                current: u32,

                pub fn next(self: *Iterator) ?Node {
                    if (self.current == none) return null;
                    const record = self.data.storage.items[self.current];
                    self.current = record.next;
                    return record.from;
                }
            };
            pub fn iterator(self: *const Self, into: Node) Iterator {
                const head = if (self.map.getPtr(into)) |p| p.* else none;
                return .{ .data = self, .current = head };
            }
        },
    };

    const MinHeap = std.PriorityQueue(Entry, void, struct {
        fn cmp(_: void, a: Entry, b: Entry) Order {
            return std.math.order(a.cost_with_heuristic, b.cost_with_heuristic);
        }
    }.cmp);

    const nodeEql = std.hash_map.getAutoEqlFn(Node, void);

    return struct {
        const Self = @This();
        pub const NodeCost = struct { Node, Cost };
        pub const Parents = ParentMap;

        context: Context,
        costs: CostMap,
        parents: ParentMap,
        min_heap: MinHeap,

        pub fn init(allocator: Allocator, context: Context) Self {
            return .{
                .context = context,
                .costs = CostMap.empty,
                .parents = .{},
                .min_heap = MinHeap.init(allocator, void{}),
            };
        }

        pub fn deinit(self: *Self) void {
            self.min_heap.deinit();
            self.costs.deinit(self.min_heap.allocator);
            self.parents.deinit(self.min_heap.allocator);
            self.* = undefined;
        }

        fn setInitialNode(self: *Self, initial: Node) !void {
            self.costs.clearRetainingCapacity();
            self.parents.clear();
            @memset(self.min_heap.items, undefined);
            self.min_heap.items.len = 0;

            try self.min_heap.add(Entry{
                .node = initial,
                .cost = 0,
                .cost_with_heuristic = self.context.heuristic(initial),
            });
            try self.costs.put(self.min_heap.allocator, initial, 0);
        }

        pub fn shortestPath(self: *Self, initial: Node) !?NodeCost {
            try self.setInitialNode(initial);

            var min: ?NodeCost = null;
            while (self.min_heap.removeOrNull()) |entry| {
                if (config.path == .all) {
                    if (min) |min_value| {
                        if (entry.cost_with_heuristic > min_value[1]) {
                            break;
                        }
                    }
                }

                if (self.context.isTarget(entry.node)) {
                    if (config.path != .all) {
                        return .{ entry.node, entry.cost };
                    }
                    if (min == null) {
                        min = .{ entry.node, entry.cost };
                    }
                    continue;
                }

                const edges: []NodeCost = self.context.getEdges(entry.node);
                next_edge: for (edges) |edge| {
                    const node = edge[0];
                    const cost = entry.cost + edge[1];
                    const cost_res = try self.costs.getOrPut(self.min_heap.allocator, node);
                    // Node not seen before
                    if (!cost_res.found_existing) {
                        cost_res.value_ptr.* = cost;
                        try self.parents.add(self.min_heap.allocator, node, entry.node);
                        try self.min_heap.add(Entry{
                            .node = node,
                            .cost = cost,
                            .cost_with_heuristic = cost + self.context.heuristic(node),
                        });
                        continue;
                    }

                    // Node has been seen before, but with a shorter or equal-length path
                    if (cost_res.value_ptr.* <= cost) {
                        if (config.path == .all and cost_res.value_ptr.* == cost) {
                            try self.parents.add(self.min_heap.allocator, node, entry.node);
                        }
                        continue;
                    }

                    // Node has been seen before, but with a longer path, this means that
                    // it must still be on the heap. Find it, remove it, re-insert it from
                    // this shorter route.
                    var entry_index: usize = 0;
                    while (!nodeEql(void{}, self.min_heap.items[entry_index].node, node)) {
                        entry_index += 1;
                        // Can only happen if there are things such as negative weights,
                        // but it's necessary for memory safety.
                        if (entry_index >= self.min_heap.items.len) {
                            continue :next_edge;
                        }
                    }
                    try self.parents.overwrite(self.min_heap.allocator, node, entry.node);
                    const heuristic = self.min_heap.removeIndex(entry_index).heuristic();
                    try self.min_heap.add(Entry{
                        .node = node,
                        .cost = cost,
                        .cost_with_heuristic = cost + heuristic,
                    });
                }
            }
            return min;
        }
    };
}
