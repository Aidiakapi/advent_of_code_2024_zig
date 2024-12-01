//! The two key types are:
//! - `ParseFn(T)`, a function type, whose instances perform the actual logic of
//!   parsing.
//! - `Parser(T)`, a struct type without any fields, which defines the
//!   utility functions used to combine the parsers.
//!
//! The `T` in both of these is the type being parsed into, this will vary based
//! on the implementation of the parser.
//!
//! In general, all implementations of parsers purely operate on `ParseFn(T)`,
//! likewise, all user-code operates solely on instances of `Parser(T)`, which
//! allows convenient combining.

const std = @import("std");
const p = @import("parsers.zig");

const Parser = p.Parser;
const ParseResult = p.ParseResult;
const ParseContext = p.ParseContext;
const ParseError = p.ParseError;

pub fn ParseFn(T: type) type {
    return fn (ParseContext, []const u8) ParseResult(T);
}

fn TryGetParseResultType(T: type) ?type {
    const info = tryGetStructInfo(T) orelse return null;

    if (info.decls.len != 0 or info.fields.len != 2) {
        return null;
    }
    const result_field = info.fields[0];
    const location_field = info.fields[1];
    if (!std.mem.eql(u8, result_field.name, "result") or !std.mem.eql(u8, location_field.name, "location")) {
        return null;
    }
    if (location_field.type != []const u8) {
        return null;
    }
    const result_info = tryGetUnionInfo(result_field.type) orelse return null;
    if (result_info.fields.len != 2) {
        return null;
    }
    const success_field = result_info.fields[0];
    const failure_field = result_info.fields[1];
    if (!std.mem.eql(u8, success_field.name, "success") or !std.mem.eql(u8, failure_field.name, "failure")) {
        return null;
    }
    if (failure_field.type != ParseError) {
        return null;
    }
    return success_field.type;
}

pub fn isParseResult(T: type) bool {
    _ = TryGetParseResultType(T) orelse return false;
    return true;
}

fn ParseFnFromParser(comptime parser: anytype) type {
    const T = @TypeOf(parser);
    if (!@hasDecl(T, "impl")) {
        @compileError(std.fmt.comptimePrint("Expected parser1, got: {s}", .{@typeName(T)}));
    }
    return @TypeOf(T.impl);
}

pub fn parseFnFromParser(comptime parser: anytype) ParseFnFromParser(parser) {
    return @TypeOf(parser).impl;
}

pub fn ResultFromParser(comptime parser: anytype) type {
    return GetParseFnResultType(parseFnFromParser(parser));
}

pub fn GetParseFnResultType(comptime parse_fn: anytype) type {
    return TryGetParseFnResultType(parse_fn) orelse
        @compileError(std.fmt.comptimePrint("expected parse function, but got: {s}", .{@typeName(@TypeOf(parse_fn))}));
}

pub fn TryGetParseFnResultType(comptime parse_fn: anytype) ?type {
    const info = tryGetFnInfo(@TypeOf(parse_fn)) orelse return null;
    if (info.is_var_args or
        info.params.len != 2 or
        info.params[0].type != ParseContext or
        info.params[1].type != []const u8)
    {
        return null;
    }
    return TryGetParseResultType(info.return_type.?);
}

fn tryGetFnInfo(T: type) ?std.builtin.Type.Fn {
    switch (@typeInfo(T)) {
        .@"fn" => |value| return value,
        else => return null,
    }
}
fn tryGetStructInfo(T: type) ?std.builtin.Type.Struct {
    switch (@typeInfo(T)) {
        .@"struct" => |value| return value,
        else => return null,
    }
}
fn tryGetUnionInfo(T: type) ?std.builtin.Type.Union {
    switch (@typeInfo(T)) {
        .@"union" => |value| return value,
        else => return null,
    }
}

fn UnwrapStructEvalFnType(comptime fn_or_struct: anytype) type {
    if (@TypeOf(fn_or_struct) == type) {
        switch (@typeInfo(fn_or_struct)) {
            .@"struct" => |_| {
                if (@hasDecl(fn_or_struct, "eval")) {
                    return @TypeOf(@field(fn_or_struct, "eval"));
                }
            },
            else => {},
        }
    }
    return @TypeOf(fn_or_struct);
}
fn unwrapStructEvalFn(comptime fn_or_struct: anytype) UnwrapStructEvalFnType(fn_or_struct) {
    if (@TypeOf(fn_or_struct) == type) {
        switch (@typeInfo(fn_or_struct)) {
            .@"struct" => |_| {
                if (@hasDecl(fn_or_struct, "eval")) {
                    return @field(fn_or_struct, "eval");
                }
            },
            else => {},
        }
    }
    return fn_or_struct;
}

pub fn GetPredicateFnType(TInput: type, comptime predicate: anytype) type {
    const predicate_fn = unwrapStructEvalFn(predicate);
    switch (@typeInfo(@TypeOf(predicate_fn))) {
        .@"fn" => |fn_info| {
            if (fn_info.is_var_args) {
                @compileError("Predicate may not take a variable argument count");
            }
            if (fn_info.return_type != bool) {
                @compileError("Predicate must return a bool");
            }
            if (fn_info.params.len != 1) {
                @compileError("Predicate must take a single parameter");
            }
            if (fn_info.params[0].type != TInput) {
                @compileError(
                    std.fmt.comptimePrint(
                        "Predicate should take type '{s}' as input, but it takes '{s}' instead",
                        .{ @typeName(TInput), @typeName(fn_info.params[0].type) },
                    ),
                );
            }
            return @TypeOf(predicate_fn);
        },
        else => @compileError(
            std.fmt.comptimePrint(
                "Expected a fn or struct with a fn named 'eval', but got: {s}",
                .{@typeName(predicate_fn)},
            ),
        ),
    }
}
pub fn getPredicateFn(TInput: type, comptime predicate: anytype) GetPredicateFnType(TInput, predicate) {
    return unwrapStructEvalFn(predicate);
}

test "TryGetParseResultType" {
    try std.testing.expectEqual(u8, TryGetParseResultType(ParseResult(u8)));
    try std.testing.expectEqual([]const u8, TryGetParseResultType(ParseResult([]const u8)));
    try std.testing.expectEqual(void, TryGetParseResultType(ParseResult(void)));
    try std.testing.expectEqual(null, TryGetParseResultType(u8));
}
