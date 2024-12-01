const std = @import("std");
const p = @import("parsers.zig");
const infra = @import("infra.zig");

const Parser = p.Parser;
const ParseResult = p.ParseResult;
const ParseContext = p.ParseContext;
const ParseError = p.ParseError;
const ParseFn = infra.ParseFn;

pub fn sepBy(T: type, TSep: type, comptime value: ParseFn(T), comptime separator: ParseFn(TSep)) ParseFn([]T) {
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult([]T) {
            var elements = std.ArrayListUnmanaged(T).empty;
            const first = value(ctx, input);
            switch (first.result) {
                .failure => |err| return .{
                    .result = .{ .failure = err },
                    .location = first.location,
                },
                .success => |v| elements.append(ctx.allocator, v) catch @panic("mem"),
            }
            var remainder = first.location;
            while (true) {
                const sep_res = separator(ctx, remainder);
                if (sep_res.result == .failure) {
                    break;
                }
                const next = value(ctx, sep_res.location);
                switch (next.result) {
                    .failure => break,
                    .success => |v| elements.append(ctx.allocator, v) catch @panic("mem"),
                }
                remainder = next.location;
            }
            const output = elements.toOwnedSlice(ctx.allocator) catch @panic("mem");
            return .{
                .result = .{ .success = output },
                .location = remainder,
            };
        }
    }.parse;
}

pub fn OneOfType(comptime parsers: anytype) type {
    infra.assertIsTuple(@TypeOf(parsers), 1, null);
    const ResultType = infra.ResultFromParser(parsers[0]);
    for (parsers, 0..) |parser, i| {
        const ParserType = infra.ResultFromParser(parser);
        if (i != 0 and ResultType != ParserType) {
            @compileError(std.fmt.comptimePrint(
                "all parsers must return the same type '{s}', but parser at index {} has type '{s}'",
                .{ @typeName(ResultType), i, @typeName(ParserType) },
            ));
        }
    }
    return ResultType;
}
pub fn oneOfImpl(comptime parsers: anytype) ParseFn(OneOfType(parsers)) {
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult(OneOfType(parsers)) {
            inline for (parsers) |parser| {
                const output = infra.parseFnFromParser(parser)(ctx, input);
                if (output.result == .success) {
                    return output;
                }
            }
            return .{
                .result = .{ .failure = ParseError.NoneMatch },
                .location = input,
            };
        }
    }.parse;
}
/// Takes a tuple of parsers, attempts to apply each one, and if it succeeds,
/// returns the value for that parser. All parsers must return the same type.
pub fn oneOf(comptime parsers: anytype) Parser(oneOfImpl(parsers)) {
    return .{};
}

pub fn OneOfValuesType(comptime kvs: anytype) type {
    comptime {
        infra.assertIsTuple(@TypeOf(kvs), 1, null);
        var ValueType: type = undefined;
        for (kvs, 0..) |kv, i| {
            infra.assertIsTuple(@TypeOf(kv), 2, 2);
            _ = infra.ResultFromParser(kv[0]);
            const Type = @TypeOf(kv[1]);
            if (i == 0) {
                ValueType = Type;
            } else if (ValueType != Type) {
                @compileError(std.fmt.comptimePrint(
                    "all values must be the same type '{s}', but value at index {} has type '{s}'",
                    .{ @typeName(ValueType), i, @typeName(Type) },
                ));
            }
        }
        return ValueType;
    }
}
pub fn oneOfValuesImpl(comptime kvs: anytype) ParseFn(OneOfValuesType(kvs)) {
    const Output = OneOfValuesType(kvs);
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult(Output) {
            inline for (kvs) |kv| {
                const output = infra.parseFnFromParser(kv[0])(ctx, input);
                if (output.result == .success) {
                    return .{
                        .result = .{ .success = kv[1] },
                        .location = output.location,
                    };
                }
            }
            return .{
                .result = .{ .failure = ParseError.NoneMatch },
                .location = input,
            };
        }
    }.parse;
}

pub fn oneOfValues(comptime kvs: anytype) Parser(oneOfValuesImpl(kvs)) {
    return .{};
}

test "parsing::multi::oneOf" {
    const parser = oneOf(.{
        p.literal("hello"),
        p.literal("world"),
    });
    try std.testing.expectEqualDeep(ParseResult(void){
        .result = .{ .success = void{} },
        .location = " world",
    }, parser.executeRaw(ParseContext.testing, "hello world"));
    try std.testing.expectEqualDeep(ParseResult(void){
        .result = .{ .success = void{} },
        .location = " hello",
    }, parser.executeRaw(ParseContext.testing, "world hello"));
    try std.testing.expectEqualDeep(ParseResult(void){
        .result = .{ .failure = ParseError.NoneMatch },
        .location = "herro wolld",
    }, parser.executeRaw(ParseContext.testing, "herro wolld"));
}


test "parsing::multi::oneOfValues" {
    const parser = oneOfValues(.{
        .{ p.literal("hello"), 123 },
        .{ p.literal("world"), 234 },
    });
    try std.testing.expectEqualDeep(ParseResult(comptime_int){
        .result = .{ .success = 123 },
        .location = " world",
    }, parser.executeRaw(ParseContext.testing, "hello world"));
    try std.testing.expectEqualDeep(ParseResult(comptime_int){
        .result = .{ .success = 234 },
        .location = " hello",
    }, parser.executeRaw(ParseContext.testing, "world hello"));
    try std.testing.expectEqualDeep(ParseResult(comptime_int){
        .result = .{ .failure = ParseError.NoneMatch },
        .location = "herro wolld",
    }, parser.executeRaw(ParseContext.testing, "herro wolld"));
}
