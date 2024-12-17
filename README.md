# Advent of Code 2024

My solutions for Advent of Code 2024. Written in Zig ⚡.

- Clone the repository.
- Make sure you have Zig 0.14.0-dev.2497+8f330ab70.
- `zig build run -Doptimize=ReleaseSafe` for all days.  
  `zig build run -Doptimize=ReleaseSafe -Dday=12` for a day 12.
- Want your own inputs?
    - **Auto-download:** Delete the `inputs` directory, then create a
      `token.txt` file containing your AoC website's session cookie value.
    - **Manually:** Replace the contents of a `inputs/NN.txt` file with your
      desired input.
- Tests?
    - `zig build test` for the tests under `src`.
    - `zig build test -Dday=12` to test day 12.
    - `zig build fw-test` for the tests under `aoc_framework`.
    - `zig build all-test` for all the tests.
- Benchmarks? 🚤 `zig build bench`
