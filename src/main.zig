const std = @import("std");
const fw = @import("fw");

const days = .{
    @import("01.zig"),
};

pub fn main() !void {
    try fw.run(days);
}

test {
    _ = &days;
}
