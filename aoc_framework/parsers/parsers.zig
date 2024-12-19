const std = @import("std");
const infra = @import("infra.zig");
const combi = @import("combi.zig");
const multi = @import("multi.zig");
const primitives = @import("primitives.zig");

pub usingnamespace primitives;

pub const ParseContext = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    report_parse_error: ?*const fn (ParseContext, ParseError, []const u8) void,
    user: ?*anyopaque,

    pub const testing = ParseContext{
        .allocator = std.testing.allocator,
        .input = "",
        .report_parse_error = null,
        .user = null,
    };

    pub fn report(self: ParseContext, err: ParseError, position: []const u8) void {
        if (self.report_parse_error) |report_fn| {
            report_fn(self, err, position);
        }
    }
};

pub const ParseError = @import("errors.zig").ParseError;

pub fn ParseResult(T: type) type {
    return struct {
        result: union(enum) {
            success: T,
            failure: ParseError,
        },
        // remainder when successful
        // position it failed to match at when a failure
        location: []const u8,
    };
}

pub fn Parser(comptime parse_fn: anytype) type {
    return struct {
        pub const Output: type = infra.GetParseFnResultType(parse_fn);
        pub const impl = parse_fn;

        pub fn executeRaw(_: @This(), ctx: ParseContext, input: []const u8) ParseResult(Output) {
            return parse_fn(ctx, input);
        }

        pub fn execute(self: @This(), ctx: ParseContext) ?Output {
            const output = self.executeRaw(ctx, ctx.input);
            switch (output.result) {
                .success => |value| {
                    if (output.location.len == 0 or (output.location.len == 1 and output.location[0] == '\n')) {
                        return value;
                    }
                    ctx.report(ParseError.InputNotConsumed, output.location);
                    return null;
                },
                .failure => |err| {
                    ctx.report(err, output.location);
                    return null;
                },
            }
        }

        // combi
        pub fn withValue(_: @This(), comptime value: anytype) Parser(
            combi.withValue(Output, @TypeOf(value), impl, value),
        ) {
            return .{};
        }

        pub fn opt(_: @This()) Parser(combi.opt(Output, impl)) {
            return .{};
        }

        pub fn then(_: @This(), parser: anytype) Parser(
            combi.then(Output, infra.ResultFromParser(parser), impl, infra.parseFnFromParser(parser)),
        ) {
            return .{};
        }

        pub fn trailed(_: @This(), parser: anytype) Parser(
            combi.trailed(Output, infra.ResultFromParser(parser), impl, infra.parseFnFromParser(parser)),
        ) {
            return .{};
        }

        pub fn with(_: @This(), parser: anytype) Parser(
            combi.with(Output, infra.ResultFromParser(parser), impl, infra.parseFnFromParser(parser)),
        ) {
            return .{};
        }

        pub fn orElse(_: @This(), parser: anytype) Parser(
            combi.orElse(Output, impl, infra.parseFnFromParser(parser)),
        ) {
            return .{};
        }

        pub fn map(_: @This(), comptime map_fn: anytype) Parser(
            combi.map(
                Output,
                infra.GetFnFromArgReturnType(Output, map_fn),
                impl,
                infra.getFnFromArg(Output, map_fn, null),
            ),
        ) {
            return .{};
        }

        pub fn filter(_: @This(), comptime predicate: anytype) Parser(
            combi.filter(Output, impl, infra.getFnFromArg(Output, predicate, bool)),
        ) {
            return .{};
        }

        pub fn filterMap(_: @This(), comptime filter_fn: anytype) Parser(
            combi.filterMap(
                Output,
                infra.WithoutOptional(infra.GetFnFromArgReturnType(Output, filter_fn)),
                impl,
                infra.getFnFromArg(Output, filter_fn, null),
            ),
        ) {
            return .{};
        }

        // multi
        pub fn sepBy(_: @This(), separator: anytype) Parser(
            multi.sepBy(Output, infra.ResultFromParser(separator), impl, infra.parseFnFromParser(separator)),
        ) {
            return .{};
        }
    };
}

pub const allOf = multi.allOf;
pub const oneOf = multi.oneOf;
pub const oneOfValues = multi.oneOfValues;
pub const takeWhile = multi.takeWhile;
pub const grid = multi.grid;
pub const gridWithPOIs = multi.gridWithPOIs;

test {
    _ = &combi;
    _ = &infra;
    _ = &multi;
    _ = &primitives;
}
