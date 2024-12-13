const std = @import("std");
const fw = @import("fw");
const divExact = std.math.divExact;

const Int = i64;
const UInt = u64;
const Vec2 = struct { Int, Int };
const MachineSpec = struct {
    a: Vec2,
    b: Vec2,
    res: Vec2,
};

pub fn parse(ctx: fw.p.ParseContext) ?[]MachineSpec {
    const p = fw.p;
    const nr = p.nr(Int);
    const pair = nr.with(p.literal(", Y").then(nr));
    const a = p.literal("Button A: X").then(pair);
    const b = p.literal("\nButton B: X").then(pair);
    const prize = p.literal("\nPrize: X=").then(nr)
        .with(p.literal(", Y=").then(nr));
    const machine = p.allOf(MachineSpec, .{ a, b, prize });
    return machine.sepBy(p.literal("\n\n")).execute(ctx);
}

pub fn pt1(machines: []MachineSpec) UInt {
    return pts(false, machines);
}

pub fn pt2(machines: []MachineSpec) UInt {
    return pts(true, machines);
}

fn pts(comptime is_pt2: bool, machines: []MachineSpec) UInt {
    var total: UInt = 0;
    for (machines) |machine| {
        if (getCheapestWin(is_pt2, machine)) |presses| {
            total += presses[0] * 3 + presses[1];
        }
    }
    return @intCast(total);
}

// Today's day is a system of linear equations:
// [m n] [a] = [x] = [m * a + n * b]
// [o p] [b]   [y]   [o * a + p * b]
//
// Invert the matrix:
// d = mp - no
// 1/d * [ p -n] [x] = [a]
//       [-o  m] [y]   [b]
fn getCheapestWin(comptime is_pt2: bool, machine: MachineSpec) ?struct { UInt, UInt } {
    const m, const o = machine.a;
    const n, const p = machine.b;
    const x = machine.res[0] + if (is_pt2) 10000000000000 else 0;
    const y = machine.res[1] + if (is_pt2) 10000000000000 else 0;
    const d = m * p - n * o;
    if (d == 0) {
        @panic("input vectors are colinear");
    }
    const ad = p * x + -n * y;
    const a = divExact(Int, ad, d) catch return null;
    const bd = -o * x + m * y;
    const b = divExact(Int, bd, d) catch return null;
    if (a < 0 or b < 0) return null;
    if (!is_pt2 and (a > 100 or b > 100)) return null;
    return .{ @intCast(a), @intCast(b) };
}

const test_input =
    \\Button A: X+94, Y+34
    \\Button B: X+22, Y+67
    \\Prize: X=8400, Y=5400
    \\
    \\Button A: X+26, Y+66
    \\Button B: X+67, Y+21
    \\Prize: X=12748, Y=12176
    \\
    \\Button A: X+17, Y+86
    \\Button B: X+84, Y+37
    \\Prize: X=7870, Y=6450
    \\
    \\Button A: X+69, Y+23
    \\Button B: X+27, Y+71
    \\Prize: X=18641, Y=10279
;
test "day13::pt1" {
    try fw.t.simple(@This(), pt1, 480, test_input);
}
test "day13::pt2" {
    try fw.t.simple(@This(), pt2, 875318608908, test_input);
}
