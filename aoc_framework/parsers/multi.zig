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
