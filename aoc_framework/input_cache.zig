const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;
const SessionToken = [128]u8;
const Instant = std.time.Instant;

const throttle_time_s = 5;

allocator: Allocator,
client: std.http.Client,
inputs_dir: std.fs.Dir,
session_token: ?SessionToken = null,
last_request_time: ?Instant = null,

pub fn init(allocator: Allocator) !@This() {
    const cwd = std.fs.cwd();
    const inputs_dir = try cwd.makeOpenPath("inputs", .{});
    errdefer inputs_dir.close();

    const client = http.Client{ .allocator = allocator };
    return .{
        .allocator = allocator,
        .client = client,
        .inputs_dir = inputs_dir,
    };
}

pub fn deinit(this: *@This()) void {
    this.client.deinit();
    this.inputs_dir.close();
    this.* = undefined;
}

fn getSessionToken(this: *@This()) !*const SessionToken {
    if (this.session_token) |*session_token| {
        return session_token;
    }
    this.session_token = std.mem.zeroes(SessionToken);
    const session_token: *SessionToken = &this.session_token.?;
    const read = try std.fs.cwd().readFile("token.txt", session_token);
    if (read.len != session_token.len) {
        return error.TokenHasWrongSize;
    }
    return session_token;
}

pub fn get(this: *@This(), comptime day: u32, allocator: Allocator) !std.ArrayList(u8) {
    if (day < 1 or day > 25) {
        return error.DayOutOfRange;
    }
    // Already cached on disk
    const file_path = std.fmt.comptimePrint("{:0>2}.txt", .{day});
    const result_from_disk: ?[]u8 = this.inputs_dir.readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| blk: {
        if (err == error.FileTooBig) {
            return err;
        }
        break :blk null;
    };
    if (result_from_disk) |result| {
        return std.ArrayList(u8).fromOwnedSlice(allocator, result);
    }

    const session_token = try this.getSessionToken();
    const session_key = "session=";
    var cookies: [session_key.len + session_token.len]u8 = undefined;
    @memcpy(cookies[0..session_key.len], session_key);
    @memcpy(cookies[session_key.len..], session_token);

    // Throttle requests
    const throttle_time_ns = throttle_time_s * 1_000_000_000;
    if (this.last_request_time) |last_request_time| {
        const elapsed = (Instant.now() catch unreachable).since(last_request_time);
        if (elapsed < throttle_time_ns) {
            std.Thread.sleep(throttle_time_ns - elapsed);
        }
    }

    const url = std.fmt.comptimePrint("https://adventofcode.com/2024/day/{}/input", .{day});
    var response = std.ArrayList(u8).init(allocator);
    const result = try this.client.fetch(.{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &response },
        .extra_headers = &.{http.Header{
            .name = "Cookie",
            .value = &cookies,
        }},
    });
    this.last_request_time = Instant.now() catch unreachable;
    if (result.status != .ok) {
        return error.HttpRequestFailed;
    }

    try this.inputs_dir.writeFile(.{
        .sub_path = file_path,
        .data = response.items,
    });

    return response;
}
