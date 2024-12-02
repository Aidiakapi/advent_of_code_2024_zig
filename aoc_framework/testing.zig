const std = @import("std");
const p = @import("parsers/parsers.zig");

const term = @import("term.zig");

const TestError = struct { err: p.ParseError, location: []const u8 };
fn TestContext(comptime Day: type) type {
    return struct {
        const Self = @This();
        const has_parser = std.meta.hasFn(Day, "parse");
        const ParseType = if (has_parser)
            switch (@typeInfo(FnReturnType(Day.parse))) {
                .optional => |v| v.child,
                else => @compileError(std.fmt.comptimePrint(
                    "Expected parse function to return an optional, but it returned: ",
                    .{@typeName(FnReturnType(Day.parse))},
                )),
            }
        else
            []const u8;

        arena: std.heap.ArenaAllocator,
        pending_error: ?TestError,

        fn init() @This() {
            return .{
                .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
                .pending_error = null,
            };
        }

        pub fn parse(self: *Self, input: []const u8) !ParseType {
            if (!has_parser) {
                return input;
            }
            const parsed_raw = Day.parse(self.getParseContext(input));
            const parsed_opt = if (@typeInfo(@TypeOf(parsed_raw)) == .error_union) try parsed_raw else parsed_raw;
            std.debug.assert((parsed_opt == null) != (self.pending_error == null));
            return parsed_opt orelse {
                const e = self.pending_error.?;
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
        }

        pub fn execPart(self: *Self, comptime partFn: anytype, input: []const u8) !FnReturnType(partFn) {
            const parsed_input = try self.parse(input);

            const fn_info = @typeInfo(@TypeOf(partFn)).@"fn";
            if (fn_info.params.len == 0 or fn_info.params.len > 2) {
                @compileError("Part function needs to take the input as its first argument, and optionally, an allocator as a second argument.");
            }

            const has_allocator_arg = fn_info.params.len == 2;
            const part_output_raw = if (has_allocator_arg) partFn(parsed_input, self.arena.allocator()) else partFn(parsed_input);
            return if (@typeInfo(@TypeOf(part_output_raw)) == .error_union) try part_output_raw else part_output_raw;
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.* = undefined;
        }

        fn getParseContext(self: *Self, input: []const u8) p.ParseContext {
            std.debug.assert(self.pending_error == null);
            return .{
                .allocator = self.arena.allocator(),
                .input = input,
                .report_parse_error = onTestParseError,
                .user = self,
            };
        }

        fn onTestParseError(ctx: p.ParseContext, err: p.ParseError, location: []const u8) void {
            const self: *Self = @ptrCast(@alignCast(ctx.user));
            std.debug.assert(self.*.pending_error == null);
            self.*.pending_error = .{ .err = err, .location = location };
        }
    };
}

pub fn testContext(comptime Day: type) TestContext(Day) {
    return TestContext(Day).init();
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.Progress.lockStdErr();
    defer std.Progress.unlockStdErr();
    nosuspend term.format(std.io.getStdErr().writer(), fmt, args) catch return;
}

fn ExecReturnType(comptime partFn: anytype) type {
    return @typeInfo(@TypeOf(partFn)).@"fn".return_type.?;
}

pub fn simple(Day: type, comptime partFn: anytype, expected: anytype, input: []const u8) !void {
    var ctx = TestContext(Day).init();
    defer ctx.deinit();
    const actual = try ctx.execPart(partFn, input);
    try std.testing.expectEqualDeep(expected, actual);
}

pub fn simpleMulti(Day: type, comptime partFn: anytype, pairs: anytype) !void {
    var ctx = TestContext(Day).init();
    defer ctx.deinit();
    inline for (pairs) |pair| {
        const expected = pair[0];
        const input = pair[1];
        const actual = try ctx.execPart(partFn, input);
        std.testing.expectEqualDeep(expected, actual) catch |err| {
            print("{<bold>}{<red>}invalid input: {<reset>}{s}\n", .{input});
            return err;
        };
    }
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

fn FnReturnType(comptime f: anytype) type {
    const F = @TypeOf(f);
    switch (@typeInfo(F)) {
        .@"fn" => |v| return v.return_type.?,
        else => @compileError(std.fmt.comptimePrint("type is not a valid function type: {}", .{@typeName(F)})),
    }
}
