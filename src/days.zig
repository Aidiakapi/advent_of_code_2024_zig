const std = @import("std");

fn getDay(comptime day_nr: u5) ?type {
    return switch (day_nr) {
        1 => @import("01.zig"),
        2 => @import("02.zig"),
        3 => @import("03.zig"),
        4 => @import("04.zig"),
        5 => @import("05.zig"),
        6 => @import("06.zig"),
        7 => @import("07.zig"),
        8 => @import("08.zig"),
        9 => @import("09.zig"),
        10 => @import("10.zig"),
        11 => @import("11.zig"),
        12 => @import("12.zig"),
        13 => @import("13.zig"),
        else => null,
    };
}

const single_day = @import("config").single_day;
fn SelectedDaysType() type {
    return comptime if (single_day == 0)
        AllDaysType
    else
        struct { type };
}
pub fn selectedDays() SelectedDaysType() {
    return comptime if (single_day == 0)
        allDays()
    else
        struct { type }{getDay(single_day) orelse
            @compileError(std.fmt.comptimePrint(
            "day{d:0>2} is not yet implemented",
            .{single_day},
        ))};
}

const AllDaysType: type = blk: {
    var count = 0;
    for (1..25) |i| {
        if (getDay(@intCast(i))) |_| {
            count += 1;
        }
    }
    var fields: [count]std.builtin.Type.StructField = undefined;
    for (&fields, 0..) |*field, i| {
        var num_buf: [3]u8 = undefined;
        field.* = std.builtin.Type.StructField{
            .alignment = 0,
            .is_comptime = false,
            .name = std.fmt.bufPrintZ(&num_buf, "{d}", .{i}) catch unreachable,
            .type = type,
            .default_value = null,
        };
    }
    const struct_info = std.builtin.Type{ .@"struct" = std.builtin.Type.Struct{
        .decls = &[0]std.builtin.Type.Declaration{},
        .fields = &fields,
        .is_tuple = true,
        .layout = .auto,
    } };
    break :blk @Type(struct_info);
};
inline fn allDays() AllDaysType {
    var result: AllDaysType = undefined;
    var count = 0;
    var i = 1;
    while (i < 25) : (i += 1) {
        if (getDay(i)) |day| {
            result[count] = day;
            count += 1;
        }
    }
    return result;
}
