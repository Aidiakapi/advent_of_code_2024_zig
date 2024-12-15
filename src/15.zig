const std = @import("std");
const fw = @import("fw");
const Allocator = std.mem.Allocator;

const Input = struct {
    grid: Grid,
    instructions: []Instruction,
};

const Vec2 = @Vector(2, i32);
const Grid = fw.grid.DenseGrid(Cell);
const Grid2 = fw.grid.DenseGrid(Cell2);
const Cell = enum {
    empty,
    wall,
    obstacle,
    robot,
};
const Instruction = enum {
    left,
    right,
    up,
    down,

    fn delta(self: Instruction) Vec2 {
        return switch (self) {
            .left => .{ -1, 0 },
            .right => .{ 1, 0 },
            .up => .{ 0, -1 },
            .down => .{ 0, 1 },
        };
    }
};

const Cell2 = enum {
    empty,
    wall,
    obstacle_left,
    obstacle_right,
};

pub fn parse(ctx: fw.p.ParseContext) ?Input {
    const p = fw.p;
    const cell = p.oneOfValues(.{
        .{ p.literal('.'), Cell.empty },
        .{ p.literal('#'), Cell.wall },
        .{ p.literal('O'), Cell.obstacle },
        .{ p.literal('@'), Cell.robot },
    });
    const grid = p.grid(Grid, cell, p.noOp, p.nl);
    const instruction = p.oneOfValues(.{
        .{ p.literal('<'), Instruction.left },
        .{ p.literal('>'), Instruction.right },
        .{ p.literal('^'), Instruction.up },
        .{ p.literal('v'), Instruction.down },
    });
    const instructions = p.nl.opt().then(instruction).sepBy(p.noOp);
    return p.allOf(Input, .{ grid, p.literal("\n\n").then(instructions) }).execute(ctx);
}

pub fn pt1(input: Input, allocator: Allocator) !u64 {
    var state = try input.grid.clone(allocator);
    defer state.deinit(allocator);

    const robot_index = std.mem.indexOfScalar(Cell, state.items, .robot) orelse
        return error.InvalidInput;
    var robot_pos: Vec2 = @intCast(state.coordFromIndex(robot_index) orelse unreachable);
    state.get(robot_pos).* = .empty;

    outer: for (input.instructions) |instruction| {
        const delta = instruction.delta();
        const next_pos = robot_pos + delta;
        var empty_pos = robot_pos + delta;
        while (true) {
            switch (state.get(empty_pos).*) {
                .empty => break,
                .wall => continue :outer,
                else => empty_pos += delta,
            }
        }
        state.get(empty_pos).* = .obstacle;
        state.get(next_pos).* = .empty;
        robot_pos = next_pos;
    }

    return calculateScore(state, Cell.obstacle);
}

fn calculateScore(grid: anytype, target: anytype) u64 {
    var iterator = grid.iterate();
    var result: u64 = 0;
    while (iterator.next()) |entry| {
        if (entry.value.* != target) continue;
        result += entry.x + 100 * entry.y;
    }
    return result;
}

pub fn pt2(input: Input, allocator: Allocator) !u64 {
    var robot_pos, var state = try convertGrid(input.grid, allocator);
    defer state.deinit(allocator);

    for (input.instructions) |instruction| {
        const delta = instruction.delta();
        const new_pos = robot_pos + delta;
        if (pt2MoveInto(true, state, new_pos, instruction)) {
            _ = pt2MoveInto(false, state, new_pos, instruction);
            robot_pos = new_pos;
        }
    }

    return calculateScore(state, Cell2.obstacle_left);
}

fn pt2MoveInto(comptime trial: bool, state: Grid2, pos: Vec2, instruction: Instruction) if (trial) bool else void {
    switch (state.get(pos).*) {
        .empty => return if (trial) true else void{},
        .wall => return if (trial) false else void{},
        else => |x| {
            const is_left = x == .obstacle_left;
            return pt2MoveBox(trial, state, pos, instruction, is_left);
        },
    }
}

fn pt2MoveBox(comptime trial: bool, state: Grid2, pos: Vec2, instruction: Instruction, is_left: bool) if (trial) bool else void {
    const left = if (is_left) pos[0] else pos[0] - 1;
    const right = left + 1;

    if (instruction == .left or instruction == .right) {
        const next_x = if (instruction == .left) left - 1 else right + 1;
        const can_move_into = pt2MoveInto(trial, state, Vec2{ next_x, pos[1] }, instruction);
        if (trial) return can_move_into;

        if (instruction == .left) {
            state.get(.{ left - 1, pos[1] }).* = .obstacle_left;
            state.get(.{ left, pos[1] }).* = .obstacle_right;
            state.get(.{ right, pos[1] }).* = .empty;
        } else {
            state.get(.{ left, pos[1] }).* = .empty;
            state.get(.{ right, pos[1] }).* = .obstacle_left;
            state.get(.{ right + 1, pos[1] }).* = .obstacle_right;
        }
        return;
    }

    const new_y = if (instruction == .up) pos[1] - 1 else pos[1] + 1;
    var can_move_into =
        pt2MoveInto(trial, state, .{ left, new_y }, instruction);
    // If the boxes are stacked vertically without offset, do not push both sides
    if ((!trial or can_move_into) and state.get(.{ left, new_y }).* != .obstacle_left) {
        can_move_into = pt2MoveInto(trial, state, .{ right, new_y }, instruction);
    }
    if (trial) return can_move_into;

    state.get(.{ left, pos[1] }).* = .empty;
    state.get(.{ right, pos[1] }).* = .empty;
    state.get(.{ left, new_y }).* = .obstacle_left;
    state.get(.{ right, new_y }).* = .obstacle_right;
}

fn convertGrid(grid: Grid, allocator: Allocator) !struct { Vec2, Grid2 } {
    var state = try Grid2.init(grid.width * 2, grid.height, .empty, allocator);
    errdefer state.deinit(allocator);

    var robot_pos = Vec2{ -1, -1 };
    var iterator = grid.iterate();
    while (iterator.next()) |entry| {
        switch (entry.value.*) {
            .empty => continue,
            .robot => robot_pos = .{ @intCast(entry.x * 2), @intCast(entry.y) },
            .obstacle => {
                state.get(entry.index * 2).* = .obstacle_left;
                state.get(entry.index * 2 + 1).* = .obstacle_right;
            },
            .wall => {
                state.get(entry.index * 2).* = .wall;
                state.get(entry.index * 2 + 1).* = .wall;
            },
        }
    }

    if (robot_pos[0] < 0) return error.InvalidInput;
    return .{ robot_pos, state };
}

const test_input_small1 =
    \\########
    \\#..O.O.#
    \\##@.O..#
    \\#...O..#
    \\#.#.O..#
    \\#...O..#
    \\#......#
    \\########
    \\
    \\<^^>>>vv<v>>v<<
;
const test_input_small2 =
    \\#######
    \\#...#.#
    \\#.....#
    \\#..OO@#
    \\#..O..#
    \\#.....#
    \\#######
    \\
    \\<vv<<^^<<^^
;
const test_input_large =
    \\##########
    \\#..O..O.O#
    \\#......O.#
    \\#.OO..O.O#
    \\#..O@..O.#
    \\#O#..O...#
    \\#O..O..O.#
    \\#.OO.O.OO#
    \\#....O...#
    \\##########
    \\
    \\<vv>^<v^>v>^vv^v>v<>v^v<v<^vv<<<^><<><>>v<vvv<>^v^>^<<<><<v<<<v^vv^v>^
    \\vvv<<^>^v^^><<>>><>^<<><^vv^^<>vvv<>><^^v>^>vv<>v<<<<v<^v>^<^^>>>^<v<v
    \\><>vv>v^v^<>><>>>><^^>vv>v<^^^>>v^v^<^^>v^^>v^<^v>v<>>v^v^<v>v^^<^^vv<
    \\<<v<^>>^^^^>>>v^<>vvv^><v<<<>^^^vv^<vvv>^>v<^^^^v<>^>vvvv><>>v^<<^^^^^
    \\^><^><>>><>^^<<^^v>>><^<v>^<vv>>v>>>^v><>^v><<<<v>>v<v<v>vvv>^<><<>^><
    \\^>><>^v<><^vvv<^^<><v<<<<<><^v<<<><<<^^<v<^^^><^>>^<v^><<<^>>^v<v^v<v^
    \\>^>>^v>vv>^<<^v<>><<><<v<<v><>v<^vv<<<>^^v^>^^>>><<^v>>v^v><^^>>^<>vv^
    \\<><^^>^^^<><vvvvv^v<v<<>^v<v>v<<^><<><<><<<^^<<<^<<>><<><^^^>^^<>^>v<>
    \\^^>vv<^v^v<vv>^<><v<^v>^^^>>>^^vvv^>vvv<>>>^<^>>>>>^<<^v>^vvv<>^<><<v>
    \\v^^>>><<^^<>>^v^<v^vv<>v^<<>^<^v^v><^<<<><<^<v><v<>vv>>v><v^<vv<>v^<<^
;
test "day15::pt1" {
    try fw.t.simple(@This(), pt1, 2028, test_input_small1);
    try fw.t.simple(@This(), pt1, 10092, test_input_large);
}
test "day15::pt2" {
    try fw.t.simple(@This(), pt2, 618, test_input_small2);
    try fw.t.simple(@This(), pt2, 9021, test_input_large);
}
