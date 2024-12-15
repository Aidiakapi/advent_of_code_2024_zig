const std = @import("std");
const max_usize = std.math.maxInt(usize);
const Allocator = std.mem.Allocator;

pub const BuildGridError = error{
    NoItems,
    RowTooShort,
    RowTooLong,
};

pub const Coord = @Vector(2, usize);

fn indexCast(index: anytype) ?usize {
    return std.math.cast(usize, index);
}

fn coordCast(coord: anytype) ?Coord {
    const x = indexCast(coord[0]) orelse return null;
    const y = indexCast(coord[1]) orelse return null;
    return Coord{ x, y };
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

        pub fn init(width: usize, height: usize, value: T, allocator: Allocator) !Self {
            const items = try allocator.alloc(T, width * height);
            @memset(items, value);
            return .{
                .items = items,
                .width = width,
                .height = height,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.items);
            self.* = empty;
        }

        pub fn clone(self: Self, allocator: Allocator) !Self {
            const new_items = try allocator.alloc(T, self.items.len);
            @memcpy(new_items, self.items);
            return .{
                .items = new_items,
                .width = self.width,
                .height = self.height,
            };
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

        pub fn coordFromIndex(self: Self, index: anytype) ?@Vector(2, @TypeOf(index)) {
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

        pub const Iterator = struct {
            width: usize,
            items: []T,
            index: usize = 0,
            x: usize = 0,
            y: usize = 0,

            pub fn next(self: *@This()) ?struct { index: usize, x: usize, y: usize, value: *T } {
                @setRuntimeSafety(false);
                if (self.index >= self.items.len) return null;
                const res = .{
                    .index = self.index,
                    .x = self.x,
                    .y = self.y,
                    .value = &self.items[self.index],
                };
                self.index += 1;
                self.x += 1;
                if (self.x >= self.width) {
                    self.x = 0;
                    self.y += 1;
                }
                return res;
            }
        };
        pub fn iterate(self: Self) Iterator {
            return .{ .width = self.width, .items = self.items };
        }

        pub fn toStr(self: Self, allocator: Allocator, context: anytype, cellToChar: fn (@TypeOf(context), x: usize, y: usize, value: T) u8) ![]u8 {
            return toStrImpl(Self, self, allocator, context, cellToChar);
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

    pub fn clear(self: Self) void {
        @memset(self.getBitSetSlice(), 0);
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

    pub fn coordFromIndex(self: Self, index: anytype) ?@Vector(2, @TypeOf(index)) {
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

    pub fn countLeadingZeroes(self: Self) usize {
        for (self.getBitSetSlice(), 0..) |bits, i| {
            const tz = @ctz(bits);
            if (tz < 64) {
                return i * 64 + tz;
            }
        }
        return self.len;
    }

    pub fn countLeadingOnes(self: Self) usize {
        for (self.getBitSetSlice(), 0..) |bits, i| {
            const tz = @ctz(~bits);
            if (tz < 64) {
                return i * 64 + tz;
            }
        }
        return self.len;
    }

    const bitmap_header_size_base = 14 + 40 + 4 * 2;
    const bitmap_header_size = (bitmap_header_size_base + 3) / 4 * 4;
    fn getBitmapMeta(self: Self) struct { scan_line_bytes: usize, scan_line_size: usize, pixel_data_size: usize } {
        const scan_line_bytes = (self.width + 7) / 8;
        const scan_line_size = (scan_line_bytes + 3) / 4 * 4;
        const pixel_data_size = scan_line_size * self.height;
        return .{ .scan_line_bytes = scan_line_bytes, .scan_line_size = scan_line_size, .pixel_data_size = pixel_data_size };
    }

    pub fn getBitmapByteCount(self: Self) usize {
        return bitmap_header_size + self.getBitmapMeta().pixel_data_size;
    }

    pub fn writeBitmap(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        const scan_line_bytes = (self.width + 7) / 8;
        const scan_line_size = (scan_line_bytes + 3) / 4 * 4;
        const pixel_data_size = scan_line_size * self.height;
        const file_size = bitmap_header_size + pixel_data_size;

        // BITMAPFILEHEADER
        try writer.writeByte('B');
        try writer.writeByte('M');
        try writer.writeInt(u32, @intCast(file_size), .little); // FileSize
        try writer.writeInt(u32, 0, .little); // reserved
        try writer.writeInt(u32, @intCast(bitmap_header_size), .little); // DataOffset
        // BITMAPINFOHEADER
        try writer.writeInt(u32, 40, .little); // Size of InfoHeader
        try writer.writeInt(u32, @intCast(self.width), .little); // Width
        try writer.writeInt(u32, @intCast(self.height), .little); // Height
        try writer.writeInt(u16, 1, .little); // Planes
        try writer.writeInt(u16, 1, .little); // BitsPerPixel
        try writer.writeInt(u32, 0, .little); // Compression, BI_RGB/no compression
        try writer.writeInt(u32, 0, .little); // ImageSize, dummy 0 because uncompressed
        try writer.writeInt(u32, 1024, .little); // XpixelsPerM
        try writer.writeInt(u32, 1024, .little); // YpixelsPerM
        try writer.writeInt(u32, 2, .little); // ColorsUsed
        try writer.writeInt(u32, 0, .little); // ImportantColors
        // ColorTable
        try writer.writeAll(&[4]u8{ 0, 0, 0, 0 }); // black
        try writer.writeAll(&[4]u8{ 255, 255, 255, 0 }); // white
        // padding
        for (0..bitmap_header_size - bitmap_header_size_base) |_| try writer.writeByte(0);

        for (0..self.height) |fy| {
            const y = self.height - 1 - fy;
            var index = self.width * y;
            for (0..self.width / 8) |_| {
                var byte: u8 = 0;
                for (0..8) |ox| {
                    byte |= @as(u8, @intFromBool(self.get(index))) << @truncate(7 - ox % 8);
                    index += 1;
                }
                try writer.writeByte(byte);
            }
            if (self.width % 8 != 0) {
                var byte: u8 = 0;
                for (0..self.width - (self.width / 8 * 8)) |ox| {
                    byte |= @as(u8, @intFromBool(self.get(index))) << @truncate(7 - ox % 8);
                    index += 1;
                }
                try writer.writeByte(byte);
            }
            for (scan_line_bytes..scan_line_size) |_| {
                try writer.writeByte(0);
            }
        }
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

fn toStrImpl(
    Grid: type,
    grid: Grid,
    allocator: Allocator,
    context: anytype,
    cellToChar: fn (@TypeOf(context), usize, usize, Grid.Item) u8,
) ![]u8 {
    if (grid.width == 0 or grid.height == 0) return &.{};
    const stride = grid.width + 1;
    const result = try allocator.alloc(u8, stride * grid.height - 1);
    for (0..grid.height - 1) |y| {
        result[stride * y + stride - 1] = '\n';
    }

    var iterator = grid.iterate();
    while (iterator.next()) |entry| {
        result[entry.x + entry.y * stride] = cellToChar(context, entry.x, entry.y, entry.value.*);
    }
    return result;
}
