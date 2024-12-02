const std = @import("std");
const p = @import("parsers.zig");
const infra = @import("infra.zig");

const Parser = p.Parser;
const ParseResult = p.ParseResult;
const ParseContext = p.ParseContext;
const ParseError = p.ParseError;
const ParseFn = infra.ParseFn;

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

test "parsing::primitives::any" {
    try std.testing.expectEqualDeep(ParseResult(u8){
        .result = .{ .success = 'h' },
        .location = "ello",
    }, any.executeRaw(ParseContext.testing, "hello"));
    try std.testing.expectEqualDeep(ParseResult(u8){
        .result = .{ .failure = ParseError.EmptyInput },
        .location = "",
    }, any.executeRaw(ParseContext.testing, ""));
}

fn digitImpl(_: ParseContext, input: []const u8) ParseResult(u4) {
    if (input.len == 0 or input[0] < '0' or input[0] > '9') {
        return .{
            .result = .{
                .failure = if (input.len == 0) ParseError.EmptyInput else ParseError.InvalidCharacter,
            },
            .location = input,
        };
    }
    return .{
        .result = .{ .success = @intCast(input[0] - '0') },
        .location = input[1..],
    };
}

pub const digit = Parser(digitImpl){};

fn matchStrSlice(comptime value: []const u8, input: []const u8) ParseResult(void) {
    if (std.mem.startsWith(u8, input, value)) {
        return .{
            .result = .{ .success = void{} },
            .location = input[value.len..],
        };
    }
    return .{
        .result = .{ .failure = ParseError.LiteralDoesNotMatch },
        .location = input,
    };
}

fn literalImpl(comptime value: anytype) ParseFn(void) {
    return struct {
        pub fn parser(_: ParseContext, input: []const u8) ParseResult(void) {
            if (input.len == 0) {
                return .{
                    .result = .{ .failure = ParseError.EmptyInput },
                    .location = input,
                };
            }
            const T = @TypeOf(value);
            if (T == u8 or (T == comptime_int and value > 0 and value < 255)) {
                if (input[0] == value) {
                    return .{
                        .result = .{ .success = void{} },
                        .location = input[1..],
                    };
                }
                return .{
                    .result = .{ .failure = ParseError.LiteralDoesNotMatch },
                    .location = input,
                };
            }
            if (T == []const u8) {
                return matchStrSlice(value, input);
            }
            switch (@typeInfo(T)) {
                .pointer => |pointer| blk: {
                    if (pointer.size != .One or !pointer.is_const) {
                        break :blk;
                    }
                    const containedArray = switch (@typeInfo(pointer.child)) {
                        .array => |v| v,
                        else => break :blk,
                    };
                    if (containedArray.child == u8) {
                        return matchStrSlice(value, input);
                    }
                },
                else => {},
            }
            @compileError(std.fmt.comptimePrint("Unsupported literal type: {s}", .{@typeName(T)}));
        }
    }.parser;
}

pub fn literal(comptime value: anytype) Parser(literalImpl(value)) {
    return .{};
}

pub const nl = literal('\n');

fn nrImpl(comptime Number: type) ParseFn(Number) {
    const int: std.builtin.Type.Int = switch (@typeInfo(Number)) {
        .int => |v| v,
        else => @compileError(std.fmt.comptimePrint("expected integer type, got: {s}", .{@typeName(Number)})),
    };
    const Unsigned = if (int.signedness == .unsigned)
        Number
    else
        @Type(std.builtin.Type{ .int = .{ .signedness = .unsigned, .bits = int.bits } });
    const is_signed = comptime int.signedness == .signed;
    const unsignedMaxValue = comptime ~@as(Unsigned, 0);
    const maxThatCanTakeExtraDigits = comptime if (int.bits >= 4) unsignedMaxValue / 10 else 0;
    const digitMultiplier: Unsigned = comptime if (int.bits >= 4) 10 else 0;

    return struct {
        fn makeError(remainder: []const u8, e: ParseError) ParseResult(Number) {
            return .{
                .result = .{ .failure = e },
                .location = remainder,
            };
        }

        pub fn parser(_: ParseContext, input: []const u8) ParseResult(Number) {
            if (input.len == 0) {
                return makeError(input, ParseError.EmptyInput);
            }
            const is_negative = is_signed and input[0] == '-';
            var remainder = input;
            if (is_negative) {
                if (remainder.len == 1) {
                    return makeError(remainder, ParseError.InvalidCharacter);
                }
                remainder = remainder[1..];
            }
            if (!std.ascii.isDigit(remainder[0])) {
                return makeError(remainder, ParseError.InvalidCharacter);
            }
            var value: Unsigned = 0;
            while (remainder.len > 0 and std.ascii.isDigit(remainder[0])) {
                const d = remainder[0] - '0';
                if (unsignedMaxValue < d) {
                    return makeError(remainder, ParseError.NumberOverflow);
                }
                if (value > maxThatCanTakeExtraDigits) {
                    return makeError(remainder, ParseError.NumberOverflow);
                }
                value = value * digitMultiplier + @as(Unsigned, @intCast(d));
                remainder = remainder[1..];
            }

            if (!is_signed) {
                return .{ .result = .{ .success = value }, .location = remainder };
            }

            const signedAbsMaxValue: Unsigned = if (int.bits > 1) (unsignedMaxValue >> 1) + 1 else 1;
            const output: Number = if (is_negative) blk: {
                if (value > signedAbsMaxValue) {
                    return makeError(remainder, ParseError.NumberOverflow);
                }
                break :blk @bitCast(~value +% 1);
            } else blk: {
                if (value >= signedAbsMaxValue) {
                    return makeError(remainder, ParseError.NumberOverflow);
                }
                break :blk @bitCast(value);
            };

            return .{ .result = .{ .success = output }, .location = remainder };
        }
    }.parser;
}

pub fn nr(comptime Number: type) Parser(nrImpl(Number)) {
    return .{};
}

fn noOpImpl(_: ParseContext, input: []const u8) ParseResult(void) {
    return .{
        .result = .{ .success = void{} },
        .location = input,
    };
}
pub const noOp = Parser(noOpImpl){};
