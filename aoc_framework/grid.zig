const std = @import("std");
const max_usize = std.math.maxInt(usize);
const Allocator = std.mem.Allocator;

pub const BuildGridError = error{
    NoItems,
    RowTooShort,
    RowTooLong,
};

fn indexCast(index: anytype) ?usize {
    return std.math.cast(usize, index);
}

fn coordCast(coord: anytype) ?[2]usize {
    const x = indexCast(coord[0]) orelse return null;
    const y = indexCast(coord[1]) orelse return null;
    return [2]usize{ x, y };
}

pub fn DenseGrid(T: type) type {
    return struct {
        const Self = @This();
        pub const Builder = DenseGridBuilder(T);
        pub const Item = T;

        pub const empty = Self{
            .items = &.{},
            .width = 0,
            .height = 0,
        };

        items: []T,
        width: usize,
        height: usize,

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.items);
            self.* = empty;
        }

        pub fn indexFromCoordOrIndex(self: Self, coord_or_index: anytype) ?usize {
            if (@typeInfo(@TypeOf(coord_or_index)) == .int) {
                const index = indexCast(coord_or_index) orelse return null;
                return if (index < self.items.len) index else null;
            } else return self.indexFromCoord(coord_or_index);
        }

        pub fn indexFromCoord(self: Self, coord: anytype) ?usize {
            const v = coordCast(coord) orelse return null;
            return if (v[0] < self.width and v[1] < self.height)
                (v[1] * self.width + v[0])
            else
                null;
        }

        pub fn coordFromIndex(self: Self, index: anytype) ?[2]@TypeOf(index) {
            std.debug.assert(@typeInfo(@TypeOf(index)) == .int);
            const v = indexCast(index) orelse return null;
            if (v >= self.items.len) {
                return null;
            }
            const x: @TypeOf(index) = @intCast(v % self.width);
            const y: @TypeOf(index) = @intCast(v / self.width);
            return .{ x, y };
        }

        pub fn tryGet(self: Self, coord_or_index: anytype) ?*T {
            return if (indexFromCoordOrIndex(self, coord_or_index)) |index|
                &self.items[index]
            else
                null;
        }

        pub fn get(self: Self, coord_or_index: anytype) *T {
            return self.tryGet(coord_or_index) orelse unreachable;
        }
    };
}

pub fn DenseGridBuilder(T: type) type {
    const Grid = DenseGrid(T);
    return ConsecutiveGridBuilderImpl(T, Grid, struct {
        const Self = @This();

        items: std.ArrayList(T),
        fn init(allocator: Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
            };
        }

        fn deinit(self: *Self) void {
            self.items.deinit();
        }

        fn push(self: *Self, value: T) void {
            (self.items.addOne() catch @panic("OOM")).* = value;
        }

        fn len(self: Self) usize {
            return self.items.items.len;
        }

        fn toOwned(self: *Self, width: usize, height: usize) BuildGridError!Grid {
            return Grid{
                .items = self.items.toOwnedSlice() catch @panic("OOM"),
                .width = width,
                .height = height,
            };
        }
    });
}

pub const BitGrid = struct {
    const Self = @This();
    pub const Builder = BitGridBuilder;
    pub const Item = bool;

    pub const empty = Self{
        .bitset = &empty_bitset,
        .width = 0,
        .height = 0,
        .len = 0,
    };

    var empty_bitset: [2]u64 = .{ 0, undefined };

    bitset: [*]u64,
    width: usize,
    height: usize,
    len: usize,

    pub fn init(width: usize, height: usize, allocator: Allocator) !Self {
        const len = width * height;
        const groups = (len + 63) / 64;
        const bitset = try allocator.alloc(u64, groups);
        @memset(bitset, 0);
        return .{
            .bitset = bitset.ptr,
            .width = width,
            .height = height,
            .len = len,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.getBitSetSlice());
        self.* = empty;
    }

    pub fn getBitSetSlice(self: Self) []u64 {
        return self.bitset[0 .. (self.len + 63) / 64];
    }

    pub fn indexFromCoordOrIndex(self: Self, coord_or_index: anytype) ?usize {
        if (@typeInfo(@TypeOf(coord_or_index)) == .int) {
            const index = indexCast(coord_or_index) orelse return null;
            return if (index < self.len) index else null;
        } else return self.indexFromCoord(coord_or_index);
    }

    pub fn indexFromCoord(self: Self, coord: anytype) ?usize {
        const v = coordCast(coord) orelse return null;
        return if (v[0] < self.width and v[1] < self.height)
            (v[1] * self.width + v[0])
        else
            null;
    }

    pub fn coordFromIndex(self: Self, index: anytype) ?[2]@TypeOf(index) {
        std.debug.assert(@typeInfo(@TypeOf(index)) == .int);
        const v = indexCast(index) orelse return null;
        if (v >= self.len) {
            return null;
        }
        const x: @TypeOf(index) = @intCast(v % self.width);
        const y: @TypeOf(index) = @intCast(v / self.width);
        return .{ x, y };
    }

    pub fn tryGet(self: Self, coord_or_index: anytype) ?bool {
        return if (indexFromCoordOrIndex(self, coord_or_index)) |index|
            (self.bitset[index >> 6] & (@as(u64, 1) << @truncate(index))) != 0
        else
            null;
    }

    pub fn get(self: Self, coord_or_index: anytype) bool {
        return self.tryGet(coord_or_index) orelse unreachable;
    }

    pub fn trySet(self: Self, coord_or_index: anytype, value: bool) bool {
        if (indexFromCoordOrIndex(self, coord_or_index)) |index| {
            const group = &self.bitset[index >> 6];
            const mask = @as(u64, 1) << @truncate(index);
            if (value) group.* |= mask else group.* &= ~mask;
            return true;
        } else return false;
    }

    pub fn set(self: Self, coord_or_index: anytype, value: bool) void {
        if (!self.trySet(coord_or_index, value)) {
            unreachable;
        }
    }

    pub fn countOnes(self: Self) usize {
        var total: usize = 0;
        for (self.getBitSetSlice()) |bits| {
            total += @popCount(bits);
        }
        return total;
    }
};

pub const BitGridBuilder = ConsecutiveGridBuilderImpl(bool, BitGrid, struct {
    const Self = @This();

    items: std.ArrayList(u64),
    bit_index: u6,
    fn init(allocator: Allocator) Self {
        return .{
            .items = std.ArrayList(u64).init(allocator),
            .bit_index = 0,
        };
    }

    fn deinit(self: *Self) void {
        self.items.deinit();
    }

    fn push(self: *Self, value: bool) void {
        if (self.bit_index == 0) {
            _ = self.items.addOne() catch @panic("OOM");
        }
        if (value) {
            const i = self.items.items;
            i[i.len - 1] |= @as(u64, 1) << self.bit_index;
        }
        self.bit_index +%= 1;
    }

    fn len(self: Self) usize {
        return self.items.items.len * 64 + self.bit_index;
    }

    fn toOwned(self: *Self, width: usize, height: usize) BuildGridError!BitGrid {
        return BitGrid{
            .items = self.items.toOwnedSlice() catch @panic("OOM"),
            .width = width,
            .height = height,
        };
    }
});

fn ConsecutiveGridBuilderImpl(T: type, TGrid: type, Context: type) type {
    return struct {
        const Self = @This();
        const Grid = TGrid;
        const Item = T;

        x: usize,
        width: ?usize,
        context: Context,

        pub fn init(allocator: Allocator) Self {
            return .{
                .context = Context.init(allocator),
                .x = 0,
                .width = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.context.deinit();
        }

        pub fn pushItem(self: *Self, value: T) BuildGridError!void {
            if (self.width) |width| {
                if (self.x >= width) {
                    return BuildGridError.RowTooLong;
                }
            }
            self.context.push(value);
            self.x += 1;
        }

        pub fn advanceToNextRow(self: *Self) BuildGridError!void {
            if (self.width) |width| {
                if (self.x != width) {
                    return BuildGridError.RowTooShort;
                }
            } else if (self.x == 0) {
                return BuildGridError.NoItems;
            } else {
                self.width = self.x;
            }
            self.x = 0;
        }

        pub fn toOwned(self: *Self) BuildGridError!Grid {
            errdefer self.deinit();
            if (self.x != 0) {
                try self.advanceToNextRow();
            }

            const width = self.width.?;
            const len: usize = self.context.len();
            std.debug.assert(len % width == 0);
            const height = len / width;
            return self.context.toOwned(width, height);
        }
    };
}
