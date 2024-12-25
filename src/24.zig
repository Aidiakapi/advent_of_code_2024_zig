const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Gate = [3]u8;
const Op = enum { And, Or, Xor };
const Initial = struct {
    gate: Gate,
    value: bool,
};
const Process = struct {
    a: Gate,
    op: Op,
    b: Gate,
    output: Gate,
};
const Input = struct {
    initials: []Initial,
    processes: []Process,
};
pub fn parse(ctx: fw.p.ParseContext) ?Input {
    const p = fw.p;
    const gate = p.allOf(Gate, .{ p.any, p.any, p.any });
    const op = p.oneOfValues(.{
        .{ p.literal("AND"), Op.And },
        .{ p.literal("OR"), Op.Or },
        .{ p.literal("XOR"), Op.Xor },
    });
    const bit = p.oneOfValues(.{ .{ p.literal('0'), false }, .{ p.literal('1'), true } });
    const initials = p.allOf(Initial, .{
        gate,
        p.literal(": ").then(bit),
    }).sepBy(p.nl);
    const processes = p.allOf(Process, .{
        gate,
        p.literal(' ').then(op),
        p.literal(' ').then(gate),
        p.literal(" -> ").then(gate),
    }).sepBy(p.nl);
    return p.allOf(Input, .{
        initials,
        p.literal("\n\n").then(processes),
    }).execute(ctx);
}

pub fn pt1(input: Input, allocator: Allocator) !u64 {
    const State = enum { unknown, false, true };
    const states = try allocator.alloc(State, input.initials.len + input.processes.len);
    defer allocator.free(states);
    @memset(states, .unknown);
    for (input.initials, states[0..input.initials.len]) |initial, *state| {
        state.* = if (initial.value) .true else .false;
    }

    const MappedProcess = struct {
        a: usize,
        b: usize,
        output: usize,
        op: Op,
    };
    const processes = try allocator.alloc(MappedProcess, input.processes.len);
    defer allocator.free(processes);

    var name_to_index = std.AutoHashMap(Gate, usize).init(allocator);
    defer name_to_index.deinit();
    for (input.initials, 0..) |initial, i| {
        const r = try name_to_index.getOrPut(initial.gate);
        if (r.found_existing) return error.InvalidInput;
        r.value_ptr.* = i;
    }
    for (input.processes, input.initials.len..) |process, i| {
        const r = try name_to_index.getOrPut(process.output);
        if (r.found_existing) return error.InvalidInput;
        r.value_ptr.* = i;
    }

    for (input.processes, processes[0..], input.initials.len..) |process, *mapped, i| {
        mapped.* = .{
            .a = name_to_index.get(process.a) orelse return error.InvalidInput,
            .b = name_to_index.get(process.b) orelse return error.InvalidInput,
            .output = i,
            .op = process.op,
        };
    }

    var remaining_processes = processes;
    while (remaining_processes.len > 0) {
        var unevaluated: usize = 0;
        for (remaining_processes) |process| {
            const a = states[process.a];
            const b = states[process.b];
            if (a == .unknown or b == .unknown) {
                remaining_processes[unevaluated] = process;
                unevaluated += 1;
                continue;
            }
            const ba = a == .true;
            const bb = b == .true;
            const r = switch (process.op) {
                .And => ba and bb,
                .Or => ba or bb,
                .Xor => ba != bb,
            };
            states[process.output] = if (r) .true else .false;
        }

        remaining_processes = remaining_processes[0..unevaluated];
    }

    var res: u64 = 0;
    for (0..64) |i| {
        const name = getName('z', i);
        const index = name_to_index.get(name) orelse break;
        const bit: u64 = if (states[index] == .true) 1 else 0;
        res |= bit << @truncate(i);
    }
    return res;
}

const RenameMap = std.AutoHashMap(Gate, Gate);
pub fn pt2(input: Input, allocator: Allocator) ![]const u8 {
    if (input.initials.len == 0 or
        input.initials.len >= 128 or
        input.initials.len % 2 != 0)
    {
        return error.InvalidInput;
    }
    const bit_count = input.initials.len / 2;

    // It's 44 full adders and one half adder (for x00 and y00).
    // These are the conditions specified, given some more friendly names:
    //
    // Full adder, NN = bit index, PP = previous bit index:
    // xNN XOR yNN -> dNN (d = difference)
    // dNN XOR cPP -> zNN (z = output)
    // xNN AND yNN -> aNN (a = intermediate a)
    // dNN AND cPP -> bNN (b = intermediate b)
    // aNN  OR bNN -> cNN (c = carry)
    //
    // The final carry c44 is actually called z45.
    //
    // The initial half adder:
    // x00 XOR y00 -> z00 (z = output)
    // x00 AND y00 -> c00 (c = carry)
    //
    // The part of the input that is a "lie" is the name of the output.
    // In order to solve it, we cannot rely on the connectivity as-specified.
    // Instead, by going over the operations, we can assign a semantic meaning
    // to each variable name. For example, if we see abc OR def, it must mean
    // that both abc and def are each either an intermediate a or b.
    //
    // Then, in a second pass over the inputs, we can uniquely identify the
    // semantic meaning of the output.
    //
    // Where these two do not line up, the output cannot possibly be the input,
    // and therefore, it's invalid. Whilst this doesn't uniquely solve the
    // problem in general, it likely solves it for all inputs.

    const GateKind = enum { input, output, carry_or_delta, intermediate };
    var kinds = std.AutoHashMap(Gate, GateKind).init(allocator);
    defer kinds.deinit();
    try kinds.ensureTotalCapacity(@truncate(input.initials.len + input.processes.len));
    for (0..bit_count) |i| {
        kinds.putAssumeCapacityNoClobber(getName('x', i), .input);
        kinds.putAssumeCapacityNoClobber(getName('y', i), .input);
        kinds.putAssumeCapacityNoClobber(getName('z', i), .output);
    }
    kinds.putAssumeCapacityNoClobber(getName('z', bit_count), .output);

    for (input.processes) |process| {
        if (isInput(process.a)) continue;
        const kind = switch (process.op) {
            .Xor => GateKind.carry_or_delta,
            .And => GateKind.carry_or_delta,
            .Or => GateKind.intermediate,
        };
        for ([2]Gate{ process.a, process.b }) |g| {
            const entry = kinds.getOrPutAssumeCapacity(g);
            if (entry.found_existing and entry.value_ptr.* != kind) {
                return error.InvalidInput;
            }
            entry.value_ptr.* = kind;
        }
    }

    var invalid_output_names = std.ArrayList(Gate).init(allocator);
    defer invalid_output_names.deinit();

    for (input.processes) |process| {
        const is_input = isInput(process.a);
        const expected_output_kind = if (is_input) res: {
            const n = getBitIndex(process.a);
            std.debug.assert(isInput(process.b) and getBitIndex(process.b) == n);
            if (n == 0) {
                if (process.op == .Xor) {
                    if (!gateEql(process.output, getName('z', 0))) {
                        try invalid_output_names.append(process.output);
                    }
                    continue;
                }
                break :res GateKind.carry_or_delta;
            }
            break :res switch (process.op) {
                .Xor => GateKind.carry_or_delta,
                .And => GateKind.intermediate,
                else => return error.InvalidInput,
            };
        } else res: {
            std.debug.assert(!isInput(process.b));
            break :res switch (process.op) {
                .Xor => GateKind.output,
                .And => GateKind.intermediate,
                .Or => GateKind.carry_or_delta,
            };
        };

        const kind = kinds.get(process.output) orelse return error.InvalidInput;
        if (kind != expected_output_kind) {
            if (gateEql(process.output, getName('z', bit_count)) and
                expected_output_kind == .carry_or_delta)
                continue;
            try invalid_output_names.append(process.output);
        }
    }

    if (invalid_output_names.items.len != 8) {
        return error.NoSolution;
    }
    std.mem.sort(Gate, invalid_output_names.items, void{}, struct {
        pub fn lt(_: void, a: Gate, b: Gate) bool {
            return std.mem.order(u8, &a, &b) == .lt;
        }
    }.lt);

    const output = try allocator.alloc(u8, 4 * 8 - 1);
    @memset(output, ',');
    for (invalid_output_names.items, 0..) |name, i| {
        @memcpy(output[i * 4 .. i * 4 + 3], &name);
    }
    return output;
}

fn isInput(gate: Gate) bool {
    return gate[0] == 'x' or gate[0] == 'y';
}

fn getBitIndex(gate: Gate) u8 {
    return (gate[1] - '0') * 10 + (gate[2] - '0');
}

fn getName(comptime prefix: u8, i: usize) [3]u8 {
    return [3]u8{ prefix, @truncate((i / 10) + '0'), @truncate((i % 10) + '0') };
}

fn gateEql(a: Gate, b: Gate) bool {
    return std.mem.eql(u8, &a, &b);
}

const test_input =
    \\x00: 1
    \\x01: 0
    \\x02: 1
    \\x03: 1
    \\x04: 0
    \\y00: 1
    \\y01: 1
    \\y02: 1
    \\y03: 1
    \\y04: 1
    \\
    \\ntg XOR fgs -> mjb
    \\y02 OR x01 -> tnw
    \\kwq OR kpj -> z05
    \\x00 OR x03 -> fst
    \\tgd XOR rvg -> z01
    \\vdt OR tnw -> bfw
    \\bfw AND frj -> z10
    \\ffh OR nrd -> bqk
    \\y00 AND y03 -> djm
    \\y03 OR y00 -> psh
    \\bqk OR frj -> z08
    \\tnw OR fst -> frj
    \\gnj AND tgd -> z11
    \\bfw XOR mjb -> z00
    \\x03 OR x00 -> vdt
    \\gnj AND wpb -> z02
    \\x04 AND y00 -> kjc
    \\djm OR pbm -> qhw
    \\nrd AND vdt -> hwm
    \\kjc AND fst -> rvg
    \\y04 OR y02 -> fgs
    \\y01 AND x02 -> pbm
    \\ntg OR kjc -> kwq
    \\psh XOR fgs -> tgd
    \\qhw XOR tgd -> z09
    \\pbm OR djm -> kpj
    \\x03 XOR y03 -> ffh
    \\x00 XOR y04 -> ntg
    \\bfw OR bqk -> z06
    \\nrd XOR fgs -> wpb
    \\frj XOR qhw -> z04
    \\bqk OR frj -> z07
    \\y03 OR x01 -> nrd
    \\hwm AND bqk -> z03
    \\tgd XOR rvg -> z12
    \\tnw OR pbm -> gnj
;
test "day24::pt1" {
    try fw.t.simple(@This(), pt1, 2024, test_input);
}
