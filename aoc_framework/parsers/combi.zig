const std = @import("std");
const p = @import("parsers.zig");
const infra = @import("infra.zig");

const Parser = p.Parser;
const ParseResult = p.ParseResult;
const ParseContext = p.ParseContext;
const ParseError = p.ParseError;
const ParseFn = infra.ParseFn;

pub fn then(T1: type, T2: type, comptime p1: ParseFn(T1), comptime p2: ParseFn(T2)) ParseFn(T2) {
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult(T2) {
            const r1 = p1(ctx, input);
            switch (r1.result) {
                .failure => |err| return .{
                    .result = .{ .failure = err },
                    .location = r1.location,
                },
                else => {},
            }
            return p2(ctx, r1.location);
        }
    }.parse;
}

pub fn trailed(T1: type, T2: type, comptime p1: ParseFn(T1), comptime p2: ParseFn(T2)) ParseFn(T1) {
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult(T1) {
            const r1 = p1(ctx, input);
            switch (r1.result) {
                .failure => return r1,
                else => {},
            }
            const r2 = p2(ctx, r1.location);
            const result = switch (r2.result) {
                .success => .{ .success = r1.result.success },
                .failure => |err| .{ .failure = err },
            };
            return .{
                .result = result,
                .location = r2.location,
            };
        }
    }.parse;
}

fn WithOutput(T1: type, T2: type) type {
    return struct { T1, T2 };
}

pub fn with(T1: type, T2: type, comptime p1: ParseFn(T1), comptime p2: ParseFn(T2)) ParseFn(WithOutput(T1, T2)) {
    const Result = ParseResult(WithOutput(T1, T2));
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) Result {
            const r1 = p1(ctx, input);
            switch (r1.result) {
                .failure => |err| return .{
                    .result = .{ .failure = err },
                    .location = r1.location,
                },
                else => {},
            }
            const r2 = p2(ctx, r1.location);
            // Note: Can become @FieldType at some point
            const result: @TypeOf(@as(Result, undefined).result) = switch (r2.result) {
                .success => |result2| .{ .success = .{ r1.result.success, result2 } },
                .failure => |err| .{ .failure = err },
            };
            return .{
                .result = result,
                .location = r2.location,
            };
        }
    }.parse;
}

pub fn filter(T: type, comptime parse_fn: ParseFn(T), comptime filter_fn: fn (T) bool) ParseFn(T) {
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult(T) {
            const output = parse_fn(ctx, input);
            switch (output.result) {
                .success => |value| {
                    if (filter_fn(value)) {
                        return output;
                    }
                    return .{
                        .result = .{ .failure = ParseError.Filtered },
                        .location = input,
                    };
                },
                .failure => return output,
            }
        }
    }.parse;
}

test "parsing::filter" {
    const IsH = struct {
        pub fn eval(v: u8) bool {
            return v == 'h';
        }
    };
    const parser1 = p.any.filter(IsH);
    const parser2 = p.any.filter(IsH.eval);

    inline for (.{ parser1, parser2 }) |parser| {
        try std.testing.expectEqualDeep(ParseResult(u8){
            .result = .{ .success = 'h' },
            .location = "ello",
        }, parser.executeRaw(ParseContext.testing, "hello"));
        try std.testing.expectEqualDeep(ParseResult(u8){
            .result = .{ .failure = ParseError.Filtered },
            .location = "jello",
        }, parser.executeRaw(ParseContext.testing, "jello"));
    }
}
