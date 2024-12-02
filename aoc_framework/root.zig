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
pub const t = @import("testing.zig");
pub const grid = @import("grid.zig");

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
        try runDay(&bw, &input_cache, arena_alloc, day);
        _ = arena.reset(.retain_capacity);
    }

    _ = arena.reset(.retain_capacity);
}

fn parseDayNr(comptime day: anytype) u5 {
    const day_name = @typeName(day);
    const error_msg = "Day name should be two digits, ranging 1 through 25, but is: " ++ day_name;
    if (day_name.len != 2) {
        @compileError(error_msg);
    }
    const day_nr = comptime std.fmt.parseUnsigned(u5, day_name, 10) catch @compileError(error_msg);
    if (day_nr < 1 or day_nr > 25) {
        @compileError(error_msg);
    }
    return day_nr;
}

fn runDay(bw: *BufferedWriter, input_cache: *InputCache, allocator: std.mem.Allocator, comptime day: anytype) !void {
    const stdout = bw.writer();
    const day_nr = comptime parseDayNr(day);
    try term.format(stdout, "{<bold>}{<white>}day{s}{<reset>}", .{@typeName(day)});
    try bw.flush();
    defer _ = term.format(stdout, "{<reset>}\n", .{}) catch {};

    const input = try input_cache.get(day_nr, allocator);
    defer input.deinit();

    const parsed_input = blk: {
        if (!std.meta.hasFn(day, "parse")) {
            break :blk input.items;
        }
        const parsed_raw = day.parse(p.ParseContext{
            .allocator = allocator,
            .input = input.items,
            .report_parse_error = printParseError,
            .user = @constCast(&stdout),
        });
        const parsed_opt = if (@typeInfo(@TypeOf(parsed_raw)) == .error_union) try parsed_raw else parsed_raw;
        break :blk parsed_opt orelse {
            try bw.flush();
            return;
        };
    };

    inline for ([3][]const u8{ "pts", "pt1", "pt2" }) |part_name| {
        if (!std.meta.hasFn(day, part_name)) {
            continue;
        }

        const partFn = @field(day, part_name);
        const fn_info = @typeInfo(@TypeOf(partFn)).@"fn";
        if (fn_info.params.len == 0 or fn_info.params.len > 2) {
            @compileError("Part function needs to take the input as its first argument, and optionally, an allocator as a second argument.");
        }
        const has_allocator_arg = fn_info.params.len == 2;
        if (has_allocator_arg and fn_info.params[1].type != std.mem.Allocator) {
            @compileError("Part function's second argument should be of type 'Allocator'");
        }

        try term.format(stdout, " {<bold>}{<dim_magenta>}| {<yellow>}{s}{<reset>} ", .{part_name});
        try bw.flush();
        const part_output_raw = if (has_allocator_arg) partFn(parsed_input, allocator) else partFn(parsed_input);
        const part_output = if (@typeInfo(@TypeOf(part_output_raw)) == .error_union) try part_output_raw else part_output_raw;
        try printPartOutput(stdout, part_output);
    }
}

fn printParseError(ctx: p.ParseContext, err: p.ParseError, location: []const u8) void {
    const stdout = @as(*const Writer, @ptrCast(@alignCast(ctx.user))).*;
    term.format(stdout, " {<bold>}{<dim_magenta>}| {<red>}{}{<reset>}\n", .{err}) catch {};

    if (t.errorLocationToRanges(ctx.input, location)) |r| {
        term.format(
            stdout,
            "{<dim_red>}position: {<white>}{}{<dim_red>}, remaining length: {<white>}{}{<dim_red>}\n" ++
                "text: {<dim_magenta>}{s}{s}{<white>}{<underline>}{s}{<no_underline>}{s}{<reset>}\n",
            .{
                r.error_index,
                location.len,
                r.ellipsis_before,
                ctx.input[r.range_begin..r.error_index],
                ctx.input[r.error_index..r.range_end],
                r.ellipsis_after,
            },
        ) catch {};
    } else {
        term.format(stdout, "{<dim_red>}no error location given{<reset>}", .{}) catch {};
    }
}

fn printPartOutput(stdout: Writer, value: anytype) !void {
    try term.format(stdout, "{<white>}{: >20}{<reset>}", .{value});
}

test {
    _ = &p;
}
