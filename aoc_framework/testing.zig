const std = @import("std");
const p = @import("parsers/parsers.zig");

const term = @import("term.zig");

const TestContext = struct {
    arena: std.heap.ArenaAllocator,
    pending_error: ?TestError,

    fn init() @This() {
        return .{
            .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
            .pending_error = null,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn getParseContext(self: *@This(), input: []const u8) p.ParseContext {
        std.debug.assert(self.pending_error == null);
        return .{
            .allocator = self.arena.allocator(),
            .input = input,
            .report_parse_error = onTestParseError,
            .user = self,
        };
    }
};
const TestError = struct { err: p.ParseError, location: []const u8 };
fn onTestParseError(ctx: p.ParseContext, err: p.ParseError, location: []const u8) void {
    const self: *TestContext = @ptrCast(@alignCast(ctx.user));
    std.debug.assert(self.*.pending_error == null);
    self.*.pending_error = .{ .err = err, .location = location };
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    nosuspend term.format(std.io.getStdErr().writer(), fmt, args) catch return;
}

pub fn ExecReturnType(comptime partFn: anytype) type {
    return @typeInfo(@TypeOf(partFn)).@"fn".return_type.?;
}
pub fn exec(Day: type, comptime partFn: anytype, input: []const u8) !ExecReturnType(partFn) {
    var context = TestContext.init();
    defer context.deinit();

    const parsed_input = if (std.meta.hasFn(Day, "parse")) blk: {
        const parsed_raw = Day.parse(context.getParseContext(input));
        const parsed_opt = if (@typeInfo(@TypeOf(parsed_raw)) == .error_union) try parsed_raw else parsed_raw;
        std.debug.assert((parsed_opt == null) != (context.pending_error == null));
        break :blk parsed_opt orelse {
            const e = context.pending_error.?;
            if (errorLocationToRanges(input, e.location)) |r| {
                print(
                    "{<red>}{<bold>}{}{<reset>}\n" ++
                        "{<dim_red>}position: {<white>}{}{<dim_red>}, remaining length: {<white>}{}{<dim_red>}\n" ++
                        "text: {<dim_magenta>}{s}{s}{<white>}{<underline>}{s}{<no_underline>}{s}{<reset>}\n",
                    .{
                        e.err,
                        r.error_index,
                        e.location.len,
                        r.ellipsis_before,
                        input[r.range_begin..r.error_index],
                        input[r.error_index..r.range_end],
                        r.ellipsis_after,
                    },
                );
            }
            return error.ParsingFailed;
        };
    } else input;

    const fn_info = @typeInfo(@TypeOf(partFn)).@"fn";
    if (fn_info.params.len == 0 or fn_info.params.len > 2) {
        @compileError("Part function needs to take the input as its first argument, and optionally, an allocator as a second argument.");
    }
    const has_allocator_arg = fn_info.params.len == 2;
    if (has_allocator_arg and fn_info.params[1].type != std.mem.Allocator) {
        @compileError("Part function's second argument should be of type 'Allocator'");
    }

    const part_output_raw = if (has_allocator_arg) partFn(parsed_input, context.arena.allocator()) else partFn(parsed_input);
    const part_output = if (@typeInfo(@TypeOf(part_output_raw)) == .error_union) try part_output_raw else part_output_raw;
    return part_output;
}

pub fn simple(Day: type, comptime partFn: anytype, expected: anytype, input: []const u8) !void {
    const output = try exec(Day, partFn, input);
    try std.testing.expectEqualDeep(expected, output);
}

pub const ErrorRanges = struct {
    error_index: usize,
    range_begin: usize,
    range_end: usize,
    ellipsis_before: []const u8,
    ellipsis_after: []const u8,
};
pub fn errorLocationToRanges(input: []const u8, error_location: []const u8) ?ErrorRanges {
    const characters_before_error_location = 20;
    const max_total_characters = 138;

    const output_ptr = @intFromPtr(error_location.ptr);
    const input_ptr = @intFromPtr(input.ptr);
    if (output_ptr < input_ptr or
        output_ptr + error_location.len > input_ptr + input.len)
    {
        return null;
    }

    const error_index = output_ptr - input_ptr;
    var range_begin = std.math.sub(usize, error_index, characters_before_error_location) catch 0;
    if (std.mem.lastIndexOfScalar(u8, input[range_begin..error_index], '\n')) |newline_before| {
        range_begin = range_begin + newline_before + 1;
    }

    var range_end = @max(error_index, @min(error_index + error_location.len, range_begin + max_total_characters));
    if (std.mem.indexOfScalarPos(u8, input[0..range_end], error_index, '\n')) |newline_after| {
        range_end = newline_after;
    }

    return .{
        .error_index = error_index,
        .range_begin = range_begin,
        .range_end = range_end,
        .ellipsis_before = if (range_begin == 0) "" else "...",
        .ellipsis_after = if (range_end == input.len) "" else "...",
    };
}
