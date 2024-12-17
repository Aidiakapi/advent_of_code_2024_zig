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
pub const astar = @import("astar.zig");

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
    _ = try bw.write(term.hide_cursor());
    defer {
        _ = bw.write(comptime term.reset() ++ term.show_cursor()) catch {};
        bw.flush() catch {};
    }
    const stdout: Writer = bw.writer();

    try term.format(
        stdout,
        "\n🎄 {<bold>}{<red>}Advent {<no_bold>}{<green>}of {<bold>}{<blue>}Code {<magenta>}2024 {<reset>}🎄\n\n",
        .{},
    );
    defer _ = stdout.writeByte('\n') catch {};

    var all_successful = true;
    inline for (days) |day| {
        all_successful = all_successful and
            try runDay(&bw, &input_cache, arena_alloc, day);
        _ = arena.reset(.retain_capacity);
    }

    _ = arena.reset(.retain_capacity);
    if (!hasArgv(arena_alloc, "--bench")) {
        return;
    }
    try term.format(stdout, "\n{<bold>}{<white>}Benchmarking:{<reset>}\n", .{});
    if (!all_successful) {
        try term.format(stdout, "{<bold>}{<red>}not running due to errors{<reset>}\n", .{});
        return;
    }
    inline for (days) |day| {
        _ = arena.reset(.retain_capacity);
        try benchDay(&bw, &input_cache, gpa_alloc, &arena, day);
    }
}

fn hasArgv(allocator: std.mem.Allocator, str: []const u8) bool {
    var args = std.process.argsWithAllocator(allocator) catch return false;
    defer args.deinit();
    while (args.next()) |arg|
        if (std.mem.eql(u8, arg, str))
            return true;
    return false;
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

const part_fn_names = [3][]const u8{ "pts", "pt1", "pt2" };
fn runDay(bw: *BufferedWriter, input_cache: *InputCache, allocator: std.mem.Allocator, Day: type) !bool {
    const stdout = bw.writer();
    const day_nr = comptime parseDayNr(Day);
    try term.format(stdout, "{<bold>}{<white>}day{s}{<reset>}", .{@typeName(Day)});
    try bw.flush();
    defer _ = term.format(stdout, "{<reset>}\n", .{}) catch {};

    const input = try input_cache.get(day_nr, allocator);
    defer input.deinit();

    const parsed_input = blk: {
        if (!std.meta.hasFn(Day, "parse")) {
            break :blk input.items;
        }
        const parsed_raw = Day.parse(p.ParseContext{
            .allocator = allocator,
            .input = input.items,
            .report_parse_error = printParseError,
            .user = @constCast(&stdout),
        });
        const parsed_opt = if (@typeInfo(@TypeOf(parsed_raw)) == .error_union) try parsed_raw else parsed_raw;
        break :blk parsed_opt orelse {
            try bw.flush();
            return false;
        };
    };

    inline for (part_fn_names) |part_name| {
        if (!std.meta.hasFn(Day, part_name)) {
            continue;
        }

        const partFn = @field(Day, part_name);
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
    return true;
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

fn benchDay(
    bw: *BufferedWriter,
    input_cache: *InputCache,
    gpa_alloc: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    Day: type,
) !void {
    const stdout = bw.writer();
    try term.format(
        stdout,
        "{<bold>}{<white>}",
        .{},
    );

    const day_name = "day" ++ @typeName(Day);
    const day_nr = comptime parseDayNr(Day);
    const input = try input_cache.get(day_nr, gpa_alloc);
    defer input.deinit();

    const has_parse_fn = comptime std.meta.hasFn(Day, "parse");
    if (has_parse_fn) {
        try benchFn(bw, gpa_alloc, day_name, "parse", struct {
            ctx: p.ParseContext,
            arena: *std.heap.ArenaAllocator,
            inline fn before(self: @This()) void {
                _ = self.arena.reset(.retain_capacity);
            }
            inline fn exec(self: @This()) void {
                const result = Day.parse(self.ctx);
                std.mem.doNotOptimizeAway(result);
            }
        }{
            .arena = arena,
            .ctx = p.ParseContext{
                .allocator = arena.allocator(),
                .input = input.items,
                .report_parse_error = null,
                .user = null,
            },
        });
    }

    var input_parse_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const parsed_input = if (has_parse_fn) Day.parse(p.ParseContext{
        .allocator = input_parse_arena.allocator(),
        .input = input.items,
        .report_parse_error = null,
        .user = null,
    }).? else input.items;
    defer input_parse_arena.deinit();

    inline for (part_fn_names) |part_name| {
        if (!std.meta.hasFn(Day, part_name)) {
            continue;
        }

        const partFn = @field(Day, part_name);
        const fn_info = @typeInfo(@TypeOf(partFn)).@"fn";
        if (fn_info.params.len == 0 or fn_info.params.len > 2) {
            @compileError("Part function needs to take the input as its first argument, and optionally, an allocator as a second argument.");
        }
        const has_allocator_arg = fn_info.params.len == 2;
        if (has_allocator_arg and fn_info.params[1].type != std.mem.Allocator) {
            @compileError("Part function's second argument should be of type 'Allocator'");
        }

        try benchFn(bw, gpa_alloc, day_name, part_name, struct {
            arena: *std.heap.ArenaAllocator,
            allocator: std.mem.Allocator,
            input: @TypeOf(parsed_input),
            inline fn before(self: @This()) void {
                if (has_allocator_arg) _ = self.arena.reset(.retain_capacity);
            }
            inline fn exec(self: @This()) void {
                const part_output_raw = if (has_allocator_arg)
                    partFn(self.input, self.allocator)
                else
                    partFn(self.input);
                std.mem.doNotOptimizeAway(part_output_raw);
                if (@typeInfo(@TypeOf(part_output_raw)) == .error_union) {
                    _ = part_output_raw catch {};
                }
            }
        }{
            .arena = arena,
            .allocator = arena.allocator(),
            .input = parsed_input,
        });
    }
}

fn benchFn(bw: *BufferedWriter, allocator: std.mem.Allocator, comptime day_name: []const u8, comptime fn_name: []const u8, functor: anytype) !void {
    const stdout = bw.writer();
    try term.format(
        stdout,
        "{<bold>}{<white>}{s}{<magenta>}::{<yellow>}{s: <5}{<reset>}",
        .{ day_name, fn_name },
    );
    _ = try bw.flush();
    defer _ = bw.flush() catch {};
    const Instant = std.time.Instant;
    const before_warmup = try Instant.now();
    const max_warmup_time = 500_000_000;
    const max_warmup_iter = 1000;
    var warmup_count: usize = 0;
    while (true) {
        warmup_count += 1;
        functor.before();
        functor.exec();
        if (warmup_count >= max_warmup_iter or Instant.since(try Instant.now(), before_warmup) > max_warmup_time) {
            break;
        }
    }
    const after_warmup = try Instant.now();
    const mean_warmup_time = (after_warmup.since(before_warmup) + warmup_count - 1) / warmup_count;
    if (warmup_count < 10) {
        try printTime(stdout, "mean", mean_warmup_time);
        try stdout.writeByte('\n');
        return;
    }

    const minimum_iteration_count = 2;
    const measurement_time = 5_000_000_000;
    var group_iterations = @max(minimum_iteration_count, measurement_time / mean_warmup_time);
    var group_size: u64 = 1;
    while (group_iterations >= 1024) {
        group_size *= 2;
        group_iterations = (group_iterations + 512) / 2;
    }
    if (group_size > 1) {
        functor.before();
        for (0..group_size) |_| {
            functor.exec();
        }
    }
    const costs = try allocator.alloc(u64, @intCast(group_iterations));
    defer allocator.free(costs);

    for (0..group_iterations) |i| {
        functor.before();
        const before = try Instant.now();
        for (0..group_size) |_| {
            functor.exec();
        }
        const after = try Instant.now();
        costs[i] = after.since(before) / group_size;
    }

    std.mem.sortUnstable(u64, costs, void{}, std.sort.asc(u64));
    const median = if (costs.len % 2 == 0)
        (costs[costs.len / 2] + costs[costs.len / 2 + 1]) / 2
    else
        costs[costs.len / 2];
    var sum: u128 = 0;
    for (costs) |cost| sum += cost;
    const mean: u64 = @intCast((sum + costs.len / 2) / costs.len);
    var sd_sum: u128 = 0;
    for (costs) |cost| {
        const delta = @as(i128, cost) - @as(i128, mean);
        sd_sum += @intCast(delta * delta);
    }
    const sd_avg = (sd_sum + (costs.len - 1) / 2) / (costs.len - 1);
    const sd: u64 = @intFromFloat(@sqrt(@as(f128, @floatFromInt(sd_avg))));
    try printTime(stdout, "median", median);
    try printTime(stdout, "mean", mean);
    try printTime(stdout, "sd", sd);
    try stdout.writeByte('\n');
}

fn printTime(writer: anytype, comptime label: []const u8, time: u64) !void {
    var value: f64 = undefined;
    var unit: []const u8 = undefined;
    if (time < 1_000) {
        value = @floatFromInt(time);
        unit = "ns";
    } else if (time < 1_000_000) {
        value = @floatFromInt(time / 1_0);
        value /= 100.0;
        unit = "µs";
    } else if (time < 1_000_000_000) {
        value = @floatFromInt(time / 1_000_0);
        value /= 100.0;
        unit = "ms";
    } else if (time < 1_000_000_000_000) {
        value = @floatFromInt(time / 1_000_000_0);
        value /= 100.0;
        unit = " s";
    } else if (time < 1_000_000_000_000_000) {
        value = @floatFromInt(time / 1_000_000_000_0);
        value /= 100.0;
        unit = "ks";
    } else if (time < 1_000_000_000_000_000_000) {
        value = @floatFromInt(time / 1_000_000_000_000_0);
        value /= 100.0;
        unit = "Ms";
    } else if (time < 1_000_000_000_000_000_000_000) {
        value = @floatFromInt(time / 1_000_000_000_000_000_0);
        value /= 100.0;
        unit = "Gs";
    } else {
        @panic("unsupported");
    }

    var buffer: [4 + 1 + 2]u8 = undefined;
    const valueFmt = try std.fmt.bufPrint(&buffer, "{d:.2}", .{value});

    try term.format(
        writer,
        " {<magenta>}{<bold>}|{<reset>} {s}: {<white>}{<bold>}{s: >6}{<reset>}{<blue>}{s}{<reset>}",
        .{ label, valueFmt, unit },
    );
}

test {
    _ = &p;
}
