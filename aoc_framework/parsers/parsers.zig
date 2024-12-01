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

        pub fn execute_raw(_: @This(), ctx: ParseContext, input: []const u8) ParseResult(Output) {
            return parse_fn(ctx, input);
        }

        pub fn execute(this: @This(), ctx: ParseContext) ?Output {
            const output = this.execute_raw(ctx, ctx.input);
            switch (output.result) {
                .success => |value| {
                    if (output.location.len == 0 or (output.location.len == 1 and output.location[0] == '\n')) {
                        return value;
                    }
                    if (ctx.report_parse_error) |report_parse_error| {
                        report_parse_error(ctx, ParseError.InputNotConsumed, output.location);
                    }
                    return null;
                },
                .failure => |err| {
                    if (ctx.report_parse_error) |report_parse_error| {
                        report_parse_error(ctx, err, output.location);
                    }
                    return null;
                },
            }
        }

        // combi
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

        pub fn filter(_: @This(), comptime predicate: anytype) Parser(
            combi.filter(Output, impl, infra.getPredicateFn(Output, predicate)),
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

test {
    _ = &infra;
    _ = &combi;
    _ = &primitives;
}
