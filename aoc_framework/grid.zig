const std = @import("std");
const max_usize = std.math.maxInt(usize);

pub const BuildGridError = error{
    NoItems,
    RowTooShort,
    RowTooLong,
};

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

        fn tryGetImpl(self: *Self, x: usize, y: usize) ?*T {
            return if (x < self.width or y < self.height)
                (self.items.ptr + (y * self.width + x))
            else
                null;
        }

        pub fn tryGet(self: *Self, index: anytype) ?*T {
            return if (index[0] >= 0 and index[0] <= max_usize and index[1] >= 0 and index[1] <= max_usize)
                tryGetImpl(self, @intCast(index[0]), @intCast(index[1]))
            else
                null;
        }

        pub fn get(self: *Self, index: anytype) *T {
            return self.tryGet(index) orelse unreachable;
        }

        pub fn free(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
            self.* = empty;
        }
    };
}

pub fn DenseGridBuilder(T: type) type {
    return struct {
        const Self = @This();
        const Grid = DenseGrid(T);
        const Item = T;

        items: std.ArrayList(T),
        x: usize,
        width: ?usize,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .x = 0,
                .width = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn pushItem(self: *Self, value: T) BuildGridError!void {
            if (self.width) |width| {
                if (self.x >= width) {
                    return BuildGridError.RowTooLong;
                }
            }
            (self.items.addOne() catch @panic("OOM")).* = value;
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
            const items = self.items.toOwnedSlice() catch @panic("OOM");
            std.debug.assert(items.len % width == 0);
            const height = items.len / width;
            return Grid{
                .items = items,
                .width = width,
                .height = height,
            };
        }
    };
}
