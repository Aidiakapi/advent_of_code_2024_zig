const std = @import("std");
const p = @import("parsers.zig");

const Parser = p.Parser;
const ParseResult = p.ParseResult;
const ParseContext = p.ParseContext;
const ParseError = p.ParseError;

fn anyImpl(_: ParseContext, input: []const u8) ParseResult(u8) {
    if (input.len == 0) {
        return .{
            .result = .{ .failure = ParseError.EmptyInput },
            .location = input,
        };
    }
    return .{
        .result = .{ .success = input[0] },
        .location = input[1..],
    };
}

pub const any = Parser(anyImpl){};

test "parsing::any" {
    try std.testing.expectEqualDeep(ParseResult(u8){
        .result = .{ .success = 'h' },
        .location = "ello",
    }, any.execute_raw(ParseContext.testing, "hello"));
    try std.testing.expectEqualDeep(ParseResult(u8){
        .result = .{ .failure = ParseError.EmptyInput },
        .location = "",
    }, any.execute_raw(ParseContext.testing, ""));
}
