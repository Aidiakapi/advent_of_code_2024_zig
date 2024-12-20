const std = @import("std");
const fw = @import("fw");

const Registers = struct {
    a: u64,
    b: u64,
    c: u64,
};
const Input = struct {
    registers: Registers,
    instructions: []u3,
};

pub fn parse(ctx: fw.p.ParseContext) ?Input {
    const p = fw.p;
    const nr_reg = p.nr(u64);
    const registers = p.allOf(Registers, .{
        p.literal("Register A: ").then(nr_reg),
        p.literal("\nRegister B: ").then(nr_reg),
        p.literal("\nRegister C: ").then(nr_reg),
    });
    const instructions = p.literal("\n\nProgram: ").then(p.nr(u3).sepBy(p.literal(',')));
    return p.allOf(Input, .{ registers, instructions }).execute(ctx);
}

pub fn pt1(input: Input, allocator: std.mem.Allocator) ![]u8 {
    var buffer: [32]u3 = undefined;
    const out = try exec(input.registers, input.instructions, &buffer);

    var str = std.ArrayList(u8).init(allocator);
    errdefer str.deinit();
    for (out, 0..) |n, i| {
        if (i != 0) {
            (try str.addOne()).* = ',';
        }
        try std.fmt.format(str.writer(), "{}", .{n});
    }
    return str.toOwnedSlice();
}

const program_length = 16;
// How many bits each digit takes (bandwidth)
const digit_bit_width = 3;
// How many bits affect a given output digit (latency)
const affected_bits = 11;
// How many digits these affected bits can affect
const affected_digits = (affected_bits + digit_bit_width - 1) / digit_bit_width;

const Error = error{NoMoreSpace};

pub fn pt2(input: Input) !usize {
    if (input.instructions.len != program_length) {
        return pt2BruteForce(input);
    }

    const Visitor = struct {
        const Self = @This();
        instructions: []u3,
        buffer: [program_length]u3 = undefined,
        var1: u3,
        var2: u3,

        execFn: *const fn (*Self, u64) Error![]u3,

        fn execFast(self: *Self, value: u64) Error![]u3 {
            return pt2FastPath(value, &self.buffer, self.var1, self.var2);
        }

        fn execSlow(self: *Self, value: u64) Error![]u3 {
            return pt2Exec(self.instructions, value, &self.buffer);
        }

        fn visit(self: *Self, digit_index: usize, prev: u64) ?u64 {
            const matching_digit_count = if (digit_index == program_length - 1)
                program_length
            else if (digit_index < affected_digits)
                0
            else
                digit_index - (affected_digits - 1);
            const matching_instructions = self.instructions[self.instructions.len - matching_digit_count ..];
            const begin = prev << digit_bit_width;
            const end = begin + (1 << digit_bit_width);
            for (begin..end) |curr| {
                const out = self.execFn(self, curr) catch continue;
                if (out.len < matching_instructions.len or
                    !std.mem.eql(u3, out[out.len - matching_instructions.len ..], matching_instructions)) continue;
                if (digit_index == program_length - 1) {
                    return curr;
                }
                if (self.visit(digit_index + 1, curr)) |match| {
                    return match;
                }
            }
            return null;
        }
    };

    const has_fast_path =
        std.mem.eql(u3, &.{ 2, 4, 1 }, input.instructions[0..3]) and
        std.mem.eql(u3, &.{ 7, 5, 0, 3 }, input.instructions[4..8]) and
        (4 == input.instructions[8] or // b ^= c has two encodings
        std.mem.eql(u3, &.{ 1, 6 }, input.instructions[8..10])) and
        input.instructions[10] == 1 and
        std.mem.eql(u3, &.{ 5, 5, 3, 0 }, input.instructions[12..16]);

    var visitor = Visitor{
        .instructions = input.instructions,
        .var1 = input.instructions[3],
        .var2 = input.instructions[11],
        .execFn = if (has_fast_path) &Visitor.execFast else &Visitor.execSlow,
    };
    return visitor.visit(0, 0) orelse error.NoSolution;
}

fn pt2FastPath(a: u64, buffer: []u3, var1: u3, var2: u3) Error![]u3 {
    var write_index: usize = 0;
    var remainder: u64 = a;
    while (true) {
        const t1 = (remainder & 0b111) ^ var1;
        const t2 = shr(remainder, t1);
        const t3 = t1 ^ t2 ^ var2;
        if (write_index >= buffer.len) return Error.NoMoreSpace;
        buffer[write_index] = @truncate(t3);
        write_index += 1;
        remainder >>= 3;
        if (remainder == 0) return buffer[0..write_index];
    }
}

const AtomicUsize = std.atomic.Value(usize);
fn pt2BruteForce(input: Input) !usize {
    const Thread = std.Thread;

    var result = AtomicUsize.init(0);
    errdefer result.store(1, .seq_cst);
    {
        const max_thread_count = 128;
        const thread_count = @min(max_thread_count, std.Thread.getCpuCount() catch 4);
        var threads: [max_thread_count]Thread = undefined;
        var spawned_threads: usize = 0;
        defer for (threads[0..spawned_threads]) |t| {
            t.join();
        };
        for (0..thread_count) |i| {
            threads[i] = try std.Thread.spawn(
                .{},
                pt2ThreadMain,
                .{ input, i, thread_count, &result },
            );
            spawned_threads += 1;
        }
    }
    return result.load(.seq_cst);
}

fn pt2ThreadMain(input: Input, thread_index: usize, thread_count: usize, result: *AtomicUsize) void {
    var buffer: [32]u3 = undefined;
    var count: usize = 0;
    var initial = input.registers.a + 1 + thread_index;
    while (true) : (initial += thread_count) {
        count += 1;
        if (count % 100_000 == 0) {
            const prev_res = result.load(.seq_cst);
            if (prev_res != 0 and prev_res < initial) return;
        }
        const out = pt2Exec(input.instructions, initial, &buffer) catch continue;
        if (!std.mem.eql(u3, input.instructions, out)) continue;

        var expected_value: usize = 0;
        while (result.cmpxchgWeak(expected_value, initial, .seq_cst, .seq_cst)) |unexpected_value| {
            if (unexpected_value == 0) continue;
            if (unexpected_value < initial) return;
            expected_value = unexpected_value;
        }
    }
}

fn pt2Exec(instructions: []const u3, a: u64, buffer: []u3) Error![]u3 {
    return exec(.{ .a = a, .b = 0, .c = 0 }, instructions, buffer);
}

fn exec(initial_registers: Registers, instructions: []const u3, buffer: []u3) Error![]u3 {
    var ip: usize = 0;
    var registers = initial_registers;
    var write_index: usize = 0;
    while (ip < instructions.len) {
        const instruction = instructions[ip];
        const literal = instructions[ip + 1];
        switch (instruction) {
            // adv
            0 => registers.a = shr(registers.a, comboOp(registers, literal)),
            // bxl
            1 => registers.b ^= literal,
            // bst
            2 => registers.b = @as(u3, @truncate(comboOp(registers, literal))),
            // jnz
            3 => if (registers.a != 0) {
                ip = literal;
                continue;
            },
            // bxc
            4 => registers.b ^= registers.c,
            // out
            5 => {
                if (write_index >= buffer.len) return error.NoMoreSpace;
                buffer[write_index] = @truncate(comboOp(registers, literal));
                write_index += 1;
            },
            // bdv
            6 => registers.b = shr(registers.a, comboOp(registers, literal)),
            7 => registers.c = shr(registers.a, comboOp(registers, literal)),
        }
        ip += 2;
    }
    return buffer[0..write_index];
}

fn shr(a: u64, b: u64) u64 {
    return if (b >= 64) 0 else a >> @truncate(b);
}

fn comboOp(registers: Registers, literal: u3) u64 {
    return switch (literal) {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        4 => registers.a,
        5 => registers.b,
        6 => registers.c,
        7 => @panic("invalid op"),
    };
}

const test_input =
    \\Register A: 729
    \\Register B: 0
    \\Register C: 0
    \\
    \\Program: 0,1,5,4,3,0
;
test "day17::pt1" {
    try fw.t.simple(@This(), pt1, "4,6,3,5,6,3,5,2,1,0", test_input);
}
test "day17::pt2" {
    try fw.t.simple(@This(), pt2, 117440,
        \\Register A: 2024
        \\Register B: 0
        \\Register C: 0
        \\
        \\Program: 0,3,5,4,3,0
    );
    try fw.t.simple(@This(), pt2, 236581108670061,
        \\Register A: 45483412
        \\Register B: 0
        \\Register C: 0
        \\
        \\Program: 2,4,1,3,7,5,0,3,4,1,1,5,5,5,3,0
    );
    //             2,4,1,5,7,5,0,3,1,6,4,3,5,5,3,0
}
