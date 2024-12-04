const std = @import("std");
const assert = std.debug.assert;
const meta = std.meta;

const ESC = '\x1B';

pub const TextDecoration = enum {
    unchanged,
    bold,
    no_bold,
    underline,
    no_underline,
};

pub fn format(
    writer: anytype,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    // Copy-paste of std.fmt.format, with special handling for the custom format
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.@"struct".fields;
    if (fields_info.len > 32) {
        @compileError("32 arguments max are supported per format call");
    }

    @setEvalBranchQuota(2000000);
    comptime var arg_state: std.fmt.ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    inline while (i < fmt.len) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        // Write out the literal
        if (start_index != end_index) {
            try writer.writeAll(fmt[start_index..end_index]);
        }

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        // Get past the {
        comptime assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        // Get past the }
        comptime assert(fmt[i] == '}');
        i += 1;

        // Custom format
        const fmt_str = comptime fmt[fmt_begin..fmt_end];
        if (fmt_str.len >= 2 and fmt_str[0] == '<' and fmt_str[fmt_str.len - 1] == '>') {
            try printColorStr(writer, fmt_str[1 .. fmt_str.len - 1]);
            continue;
        }

        const placeholder = comptime std.fmt.Placeholder.parse(fmt[fmt_begin..fmt_end].*);
        const arg_pos = comptime switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            .named => |arg_name| meta.fieldIndex(ArgsType, arg_name) orelse
                @compileError("no argument with name '" ++ arg_name ++ "'"),
        };

        const width = switch (placeholder.width) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const precision = switch (placeholder.precision) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const arg_to_print = comptime arg_state.nextArg(arg_pos) orelse
            @compileError("too few arguments");

        try std.fmt.formatType(
            @field(args, fields_info[arg_to_print].name),
            placeholder.specifier_arg,
            std.fmt.FormatOptions{
                .fill = placeholder.fill,
                .alignment = placeholder.alignment,
                .width = width,
                .precision = precision,
            },
            writer,
            std.options.fmt_max_depth,
        );
    }

    if (comptime arg_state.hasUnusedArgs()) {
        const missing_count = arg_state.args_len - @popCount(arg_state.used_args);
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("unused argument in '" ++ fmt ++ "'"),
            else => @compileError(std.fmt.comptimePrint("{d}", .{missing_count}) ++ " unused arguments in '" ++ fmt ++ "'"),
        }
    }
}

fn printColorStr(writer: anytype, comptime color_str: []const u8) !void {
    if (comptime std.mem.eql(u8, "reset", color_str)) {
        try writer.writeAll(reset());
        return;
    }
    if (comptime std.mem.eql(u8, "bold", color_str)) {
        try writer.writeAll(bold());
        return;
    }
    if (comptime std.mem.eql(u8, "no_bold", color_str)) {
        try writer.writeAll(noBold());
        return;
    }
    if (comptime std.mem.eql(u8, "underline", color_str)) {
        try writer.writeAll(underline());
        return;
    }
    if (comptime std.mem.eql(u8, "no_underline", color_str)) {
        try writer.writeAll(noUnderline());
        return;
    }

    const col_opt = comptime meta.stringToEnum(TermColor, color_str);
    if (col_opt) |col| {
        try writer.writeAll(color(col));
        return;
    }

    @compileError(std.fmt.comptimePrint("Unknown color string: \"{s}\"", .{color_str}));
}

pub fn hide_cursor() []const u8 {
    return [1]u8{ESC} ++ "[?25l";
}

pub fn show_cursor() []const u8 {
    return [1]u8{ESC} ++ "[?25h";
}

pub fn reset() []const u8 {
    return [1]u8{ESC} ++ "[0m";
}

pub fn bold() []const u8 {
    return [1]u8{ESC} ++ "[1m";
}

pub fn noBold() []const u8 {
    return [1]u8{ESC} ++ "[22m";
}

pub fn underline() []const u8 {
    return [1]u8{ESC} ++ "[4m";
}

pub fn noUnderline() []const u8 {
    return [1]u8{ESC} ++ "[24m";
}

pub const TermColor = enum(u8) {
    dim_black = 30,
    dim_red = 31,
    dim_green = 32,
    dim_yellow = 33,
    dim_blue = 34,
    dim_magenta = 35,
    dim_cyan = 36,
    dim_white = 37,
    black = 90,
    red = 91,
    green = 92,
    yellow = 93,
    blue = 94,
    magenta = 95,
    cyan = 96,
    white = 97,
};

pub fn color(comptime col: TermColor) []const u8 {
    return [2]u8{ ESC, '[' } ++ std.fmt.comptimePrint("{}m", .{@intFromEnum(col)});
}
