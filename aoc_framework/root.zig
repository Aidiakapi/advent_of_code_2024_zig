const std = @import("std");
const testing = std.testing;
const term = @import("term.zig");

const platform = switch (@import("builtin").target.os.tag) {
    .windows => @import("platform_windows.zig"),
    else => struct {
        pub fn init() void {}
    },
};

pub fn run() !void {
    platform.init();
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
}
