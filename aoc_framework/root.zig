const std = @import("std");
const term = @import("term.zig");
const InputCache = @import("input_cache.zig");

const Platform = switch (@import("builtin").target.os.tag) {
    .windows => @import("platform_windows.zig"),
    else => struct {
        pub fn init() void {}
    },
};

pub const p = @import("parsers/parsers.zig");

pub fn run() !void {
    Platform.init();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    // Attempt to pre-allocate 50MB, if it fails, no problem
    _ = arena_alloc.alloc(u8, 50 * 1024 * 1024) catch {};
    _ = arena.reset(.retain_capacity);

    var input_cache = try InputCache.init(gpa_alloc);
    defer input_cache.deinit();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    defer {
        _ = bw.write(term.reset()) catch {};
        bw.flush() catch {};
    }
    const stdout = bw.writer();

    try term.format(
        stdout,
        "\n🎄 {<bold>}{<red>}Advent {<no_bold>}{<green>}of {<bold>}{<blue>}Code {<magenta>}2024 {<reset>}🎄\n",
        .{},
    );
    defer _ = bw.write("\n") catch {};

    _ = arena.reset(.retain_capacity);
}

test {
    _ = &p;
}
