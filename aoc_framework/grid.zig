const std = @import("std");
const max_usize = std.math.maxInt(usize);

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

        pub fn tryGet(self: Self, coord: anytype) ?*T {
            return if (indexFromCoord(self, coord)) |index|
                &self.items[index]
            else
                null;
        }

        pub fn get(self: Self, coord: anytype) *T {
            return self.tryGet(coord) orelse unreachable;
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
