const std = @import("std");
const p = @import("parsers.zig");
const infra = @import("infra.zig");
const grid_mod = @import("../grid.zig");

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
                .success => |v| elements.append(ctx.allocator, v) catch @panic("OOM"),
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
                    .success => |v| elements.append(ctx.allocator, v) catch @panic("OOM"),
                }
                remainder = next.location;
            }
            const output = elements.toOwnedSlice(ctx.allocator) catch @panic("OOM");
            return .{
                .result = .{ .success = output },
                .location = remainder,
            };
        }
    }.parse;
}

fn MultiOutputHelperStruct(Output: type) type {
    const fields = @typeInfo(Output).@"struct".fields;
    return struct {
        const Self = @This();
        const count: comptime_int = fields.len;
        output: Output = undefined,

        pub fn set(self: *Self, comptime index: usize, value: anytype) void {
            @field(self.output, fields[index].name) = value;
        }
    };
}

fn MultiOutputHelperArrayOrVector(Output: type, len: comptime_int) type {
    return struct {
        const Self = @This();
        const count: comptime_int = len;
        output: Output = undefined,

        pub fn set(self: *Self, comptime index: usize, value: anytype) void {
            self.output[index] = value;
        }
    };
}

const MultiOutputHelperVoid = struct {
    const count: comptime_int = 0;
    output: void = void{},
};

fn MultiOutputHelper(Output: type) type {
    return switch (@typeInfo(Output)) {
        .@"struct" => MultiOutputHelperStruct(Output),
        .array => |a| MultiOutputHelperArrayOrVector(Output, a.len),
        .vector => |v| MultiOutputHelperArrayOrVector(Output, v.len),
        .void => MultiOutputHelperVoid,
        else => @compileError(std.fmt.comptimePrint("Type is not supported as output type: {s}", .{@typeName(Output)})),
    };
}

fn allOfImpl(Output: type, comptime parsers: anytype) ParseFn(Output) {
    const Helper = MultiOutputHelper(Output);
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult(Output) {
            var remainder = input;
            var helper = Helper{};
            inline for (parsers, 0..Helper.count) |parser, index| {
                const output = infra.parseFnFromParser(parser)(ctx, remainder);
                const value = switch (output.result) {
                    .success => |v| v,
                    .failure => |err| return .{
                        .result = .{ .failure = err },
                        .location = output.location,
                    },
                };
                remainder = output.location;
                helper.set(index, value);
            }
            return .{
                .result = .{ .success = helper.output },
                .location = remainder,
            };
        }
    }.parse;
}

pub fn allOf(Output: type, comptime parsers: anytype) Parser(allOfImpl(Output, parsers)) {
    return .{};
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

fn takeWhileImpl(comptime filterFn: fn (u8) bool) ParseFn([]const u8) {
    return struct {
        fn parse(_: ParseContext, input: []const u8) ParseResult([]const u8) {
            var i: usize = 0;
            while (i < input.len) : (i += 1) {
                if (!filterFn(input[i])) break;
            }
            if (i == 0) {
                const err = if (input.len == 0) ParseError.EmptyInput else ParseError.NoneMatch;
                return .{
                    .result = .{ .failure = err },
                    .location = input,
                };
            }
            return .{
                .result = .{ .success = input[0..i] },
                .location = input[i..],
            };
        }
    }.parse;
}

pub fn takeWhile(comptime filterFn: fn (u8) bool) Parser(takeWhileImpl(filterFn)) {
    return .{};
}

fn gridImpl(
    Grid: type,
    TColSep: type,
    TRowSep: type,
    comptime parseItem: ParseFn(Grid.Item),
    comptime parseColSep: ParseFn(TColSep),
    comptime parseRowSep: ParseFn(TRowSep),
) ParseFn(Grid) {
    const underlying = gridWithPOIsImpl(
        Grid,
        TColSep,
        TRowSep,
        parseItem,
        parseColSep,
        parseRowSep,
        void,
        undefined,
        .{},
    );
    return struct {
        fn parse(ctx: ParseContext, input: []const u8) ParseResult(Grid) {
            const res = underlying(ctx, input);
            switch (res.result) {
                .success => |value| return .{
                    .result = .{ .success = value[0] },
                    .location = res.location,
                },
                .failure => |err| return .{
                    .result = .{ .failure = err },
                    .location = res.location,
                },
            }
        }
    }.parse;
}

fn GridWithPOIsResult(Grid: type, TPOIs: type) type {
    return struct { Grid, TPOIs };
}
fn gridWithPOIsImpl(
    Grid: type,
    TColSep: type,
    TRowSep: type,
    comptime parseItem: ParseFn(Grid.Item),
    comptime parseColSep: ParseFn(TColSep),
    comptime parseRowSep: ParseFn(TRowSep),
    TPOIs: type,
    comptime poi_substitution: Grid.Item,
    comptime poi_parsers: anytype,
) ParseFn(GridWithPOIsResult(Grid, TPOIs)) {
    const Builder = Grid.Builder;
    const Helper = MultiOutputHelper(TPOIs);
    const Result = GridWithPOIsResult(Grid, TPOIs);
    infra.assertIsTuple(@TypeOf(poi_parsers), Helper.count, Helper.count);
    return struct {
        fn makeError(location: []const u8, err: grid_mod.BuildGridError) ParseResult(Result) {
            return .{
                .result = .{ .failure = switch (err) {
                    grid_mod.BuildGridError.NoItems => ParseError.GridNoItems,
                    grid_mod.BuildGridError.RowTooShort => ParseError.GridRowTooShort,
                    grid_mod.BuildGridError.RowTooLong => ParseError.GridRowTooLong,
                } },
                .location = location,
            };
        }

        fn parse(ctx: ParseContext, input: []const u8) ParseResult(Result) {
            const BitSet = std.bit_set.IntegerBitSet(@intCast(Helper.count));
            var pois_found = BitSet.initEmpty();
            var pois_helper = Helper{};
            var builder = Builder.init(ctx.allocator);

            var remainder = input;
            var pre_sep_remainder = input;
            end_of_grid: while (true) {
                var is_first_column = true;
                end_of_row: while (true) {
                    const item = parseItem(ctx, remainder);
                    switch (item.result) {
                        .failure => failure_handler: {
                            inline for (poi_parsers, 0..) |poi_parser, i| {
                                if (!pois_found.isSet(i)) {
                                    const poi_res = infra.parseFnFromParser(poi_parser)(ctx, remainder);
                                    if (poi_res.result == .success) {
                                        remainder = poi_res.location;
                                        pois_found.set(i);
                                        pois_helper.set(i, builder.getNextItemCoord());
                                        builder.pushItem(poi_substitution) catch |err| {
                                            builder.deinit();
                                            return makeError(remainder, err);
                                        };
                                        remainder = poi_res.location;
                                        break :failure_handler;
                                    }
                                }
                            }

                            remainder = pre_sep_remainder;
                            if (is_first_column) {
                                break :end_of_grid;
                            }
                            break :end_of_row;
                        },
                        .success => |value| {
                            builder.pushItem(value) catch |err| {
                                builder.deinit();
                                return makeError(remainder, err);
                            };
                            remainder = item.location;
                        },
                    }

                    is_first_column = false;
                    pre_sep_remainder = remainder;
                    const col_sep = parseColSep(ctx, remainder);
                    switch (col_sep.result) {
                        .failure => break :end_of_row,
                        .success => remainder = col_sep.location,
                    }
                }

                pre_sep_remainder = remainder;
                const row_sep = parseRowSep(ctx, remainder);
                switch (row_sep.result) {
                    .failure => break :end_of_grid,
                    .success => remainder = row_sep.location,
                }

                builder.advanceToNextRow() catch |err| {
                    builder.deinit();
                    return makeError(remainder, err);
                };
            }

            const output = builder.toOwned() catch |err| {
                return makeError(remainder, err);
            };
            if (!pois_found.eql(BitSet.initFull())) {
                return .{
                    .result = .{ .failure = ParseError.GridMissingPOIs },
                    .location = remainder,
                };
            }
            return .{
                .result = .{ .success = .{ output, pois_helper.output } },
                .location = remainder,
            };
        }
    }.parse;
}
pub fn grid(
    Grid: type,
    comptime parse_item: anytype,
    comptime parse_col_sep: anytype,
    comptime parse_row_sep: anytype,
) Parser(gridImpl(
    Grid,
    infra.ResultFromParser(parse_col_sep),
    infra.ResultFromParser(parse_row_sep),
    infra.parseFnFromParser(parse_item),
    infra.parseFnFromParser(parse_col_sep),
    infra.parseFnFromParser(parse_row_sep),
)) {
    return .{};
}

pub fn gridWithPOIs(
    Grid: type,
    comptime parse_item: anytype,
    comptime parse_col_sep: anytype,
    comptime parse_row_sep: anytype,
    POIs: type,
    comptime poi_substitution: Grid.Item,
    comptime parse_pois: anytype,
) Parser(gridWithPOIsImpl(
    Grid,
    infra.ResultFromParser(parse_col_sep),
    infra.ResultFromParser(parse_row_sep),
    infra.parseFnFromParser(parse_item),
    infra.parseFnFromParser(parse_col_sep),
    infra.parseFnFromParser(parse_row_sep),
    POIs,
    poi_substitution,
    parse_pois,
)) {
    return .{};
}

test "parsing::multi::grid" {
    const Grid = grid_mod.DenseGrid(u8);
    const parser = grid(Grid, p.nr(u8), p.literal('a'), p.literal('b'));

    var parsed = parser.executeRaw(ParseContext.testing, "10a20a30b40a50a60abc");
    try std.testing.expectEqualDeep(ParseResult(Grid){
        .result = .{ .success = Grid{
            .items = @constCast(@as([]const u8, &.{ @as(u8, 10), 20, 30, 40, 50, 60 })),
            .width = 3,
            .height = 2,
        } },
        .location = "abc",
    }, parsed);
    parsed.result.success.free(std.testing.allocator);
}
