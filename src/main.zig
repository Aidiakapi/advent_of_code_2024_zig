const std = @import("std");
const fw = @import("fw");

const days = @import("days.zig");

pub fn main() !void {
    try fw.run(days.selectedDays());
}

test {
    _ = &days.selectedDays();
}
