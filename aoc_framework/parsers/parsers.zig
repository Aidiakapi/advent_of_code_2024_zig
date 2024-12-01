const std = @import("std");
const infra = @import("infra.zig");
const combi = @import("combi.zig");
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
    const ParseType: type = infra.tryGetParseFnType(parse_fn) orelse
        @compileError(std.fmt.comptimePrint("parse_fn is not a parse function: {s}", .{@typeName(@TypeOf(parse_fn))}));
    return struct {
        pub const Output: type = ParseType;
        pub const impl = parse_fn;

        pub fn execute_raw(_: @This(), ctx: ParseContext, input: []const u8) ParseResult(ParseType) {
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

        pub fn filter(_: @This(), comptime predicate: anytype) Parser(
            combi.filter(ParseType, impl, infra.getPredicateFn(ParseType, predicate)),
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
