const std = @import("std");
const term = @import("term.zig");
const InputCache = @import("input_cache.zig");

const Platform = switch (@import("builtin").target.os.tag) {
    .windows => @import("platform_windows.zig"),
    else => struct {
        pub fn init() void {}
    },
};

pub const p = @import("parsers/parsers.zig");

const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);
const Writer = BufferedWriter.Writer;

pub fn run(comptime days: anytype) !void {
    Platform.init();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    // Attempt to pre-allocate 50MB, if it fails, no problem
    _ = arena_alloc.alloc(u8, 50 * 1024 * 1024) catch {};
    _ = arena.reset(.retain_capacity);

    var input_cache = try InputCache.init(gpa_alloc);
    defer input_cache.deinit();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    defer {
        _ = bw.write(term.reset()) catch {};
        bw.flush() catch {};
    }
    const stdout: Writer = bw.writer();

    try term.format(
        stdout,
        "\n🎄 {<bold>}{<red>}Advent {<no_bold>}{<green>}of {<bold>}{<blue>}Code {<magenta>}2024 {<reset>}🎄\n\n",
        .{},
    );
    defer _ = stdout.writeByte('\n') catch {};

    inline for (days) |day| {
        try run_day(&bw, &input_cache, arena_alloc, day);
        _ = arena.reset(.retain_capacity);
    }

    _ = arena.reset(.retain_capacity);
}

fn parse_day_nr(comptime day: anytype) u4 {
    const day_name = @typeName(day);
    const error_msg = "Day name should be two digits, ranging 1 through 25, but is: " ++ day_name;
    if (day_name.len != 2) {
        @compileError(error_msg);
    }
    const day_nr = comptime std.fmt.parseUnsigned(u4, day_name, 10) catch @compileError(error_msg);
    if (day_nr < 1 or day_nr > 25) {
        @compileError(error_msg);
    }
    return day_nr;
}

fn run_day(bw: *BufferedWriter, input_cache: *InputCache, allocator: std.mem.Allocator, comptime day: anytype) !void {
    const stdout = bw.writer();
    const day_nr = comptime parse_day_nr(day);
    try term.format(stdout, "{<bold>}{<white>}day{s}{<reset>}", .{@typeName(day)});
    try bw.flush();
    defer _ = term.format(stdout, "{<reset>}\n", .{}) catch {};

    const input = try input_cache.get(day_nr, allocator);
    defer input.deinit();

    const parsed_input = blk: {
        if (!std.meta.hasFn(day, "parse")) {
            break :blk input.items;
        }
        break :blk day.parse(p.ParseContext{
            .allocator = allocator,
            .input = input.items,
            .report_parse_error = print_parse_error,
            .user = @constCast(&stdout),
        }) orelse {
            try bw.flush();
            return;
        };
    };

    inline for ([3][]const u8{ "pts", "pt1", "pt2" }) |part_name| {
        if (!std.meta.hasFn(day, part_name)) {
            continue;
        }

        const fn_info = @typeInfo(@TypeOf(@field(day, part_name))).@"fn";
        if (fn_info.params.len == 0 or fn_info.params.len > 2) {
            @compileError("Part function needs to take the input as its first argument, and optionally, an allocator as a second argument.");
        }
        const has_allocator_arg = fn_info.params.len == 2;
        if (has_allocator_arg and fn_info.params[1].type != std.mem.Allocator) {
            @compileError("Part function's second argument should be of type 'Allocator'");
        }

        try term.format(stdout, " {<bold>}{<dim_magenta>}| {<yellow>}{s}{<reset>} ", .{part_name});
        try bw.flush();
        const part_fn = @field(day, part_name);
        const part_output_raw = if (has_allocator_arg) part_fn(parsed_input, allocator) else part_fn(parsed_input);
        const part_output = if (@typeInfo(@TypeOf(part_output_raw)) == .error_union) try part_output_raw else part_output_raw;
        try print_part_output(stdout, part_output);
    }
}

fn print_parse_error(ctx: p.ParseContext, err: p.ParseError, location: []const u8) void {
    const characters_before_error_location = 20;
    const max_total_characters = 138;

    const stdout = @as(*const Writer, @ptrCast(@alignCast(ctx.user))).*;
    term.format(stdout, " {<bold>}{<dim_magenta>}| {<red>}{}{<reset>}\n", .{err}) catch {};

    const output_ptr = @intFromPtr(location.ptr);
    const input_ptr = @intFromPtr(ctx.input.ptr);
    if (output_ptr < input_ptr or
        output_ptr + location.len > input_ptr + ctx.input.len)
    {
        term.format(stdout, "{<dim_red>}no error location given{<reset>}", .{}) catch {};
        return;
    }

    const error_index = output_ptr - input_ptr;
    var shown_range_start = std.math.sub(usize, error_index, characters_before_error_location) catch 0;
    if (std.mem.lastIndexOfScalar(u8, ctx.input[shown_range_start..error_index], '\n')) |newline_before| {
        shown_range_start = newline_before + 1;
    }

    var shown_range_end = @max(error_index, @min(error_index + location.len, shown_range_start + max_total_characters));
    if (std.mem.indexOfScalarPos(u8, ctx.input[0..shown_range_end], error_index, '\n')) |newline_after| {
        shown_range_end = newline_after;
    }

    const ellipsis_before = if (shown_range_start == 0) "" else "…";
    const ellipsis_after = if (shown_range_end == ctx.input.len) "" else "…";

    term.format(
        stdout,
        "{<dim_red>}position: {<white>}{}{<dim_red>}, remaining length: {<white>}{}{<dim_red>}\n" ++
            "text: {<dim_magenta>}{s}{s}{<white>}{<underline>}{s}{<no_underline>}{s}{<reset>}\n",
        .{
            error_index,
            location.len,
            ellipsis_before,
            ctx.input[shown_range_start..error_index],
            ctx.input[error_index..shown_range_end],
            ellipsis_after,
        },
    ) catch {};
}

fn print_part_output(stdout: Writer, value: anytype) !void {
    try term.format(stdout, "{<white>}{: >20}{<reset>}", .{value});
}

test {
    _ = &p;
}
