const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const day_option = b.option(u5, "day", "Which day to compile") orelse 0;
    if (day_option > 25) {
        @panic("specified day must be <= 25");
    }
    const options = b.addOptions();
    options.addOption(u5, "single_day", day_option);
    const options_mod = options.createModule();

    const lib = b.addStaticLibrary(.{
        .name = "aoc_framework",
        .root_source_file = b.path("aoc_framework/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "advent_of_code_2024",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("fw", &lib.root_module);
    exe.root_module.addImport("config", options_mod);
    exe.linkLibrary(lib);

    // Compile these when running `zig build`
    b.installArtifact(lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run Advent of Code");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("aoc_framework/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("fw", &lib.root_module);
    exe_unit_tests.root_module.addImport("config", options_mod);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run Advent of Code unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const fw_test_step = b.step("fw-test", "Run AoC Framework unit tests");
    fw_test_step.dependOn(&run_lib_unit_tests.step);

    const all_test_step = b.step("all-test", "Run all unit tests");
    all_test_step.dependOn(&run_exe_unit_tests.step);
    all_test_step.dependOn(&run_lib_unit_tests.step);
}
