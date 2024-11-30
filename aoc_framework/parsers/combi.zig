const std = @import("std");
const p = @import("parsers.zig");
const infra = @import("infra.zig");

const Parser = p.Parser;
const ParseResult = p.ParseResult;
const ParseContext = p.ParseContext;
const ParseError = p.ParseError;
const ParseFn = infra.ParseFn;

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
        }, parser.execute_raw(ParseContext.testing, "hello"));
        try std.testing.expectEqualDeep(ParseResult(u8){
            .result = .{ .failure = ParseError.Filtered },
            .location = "jello",
        }, parser.execute_raw(ParseContext.testing, "jello"));
    }
}
