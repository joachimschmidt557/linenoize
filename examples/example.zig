const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const log = std.log.scoped(.main);

const Linenoise = @import("linenoise").Linenoise;

fn completion(allocator: *Allocator, buf: []const u8) ![]const []const u8 {
    if (std.mem.eql(u8, "z", buf)) {
        var result = ArrayList([]const u8).init(allocator);
        try result.append(try allocator.dupe(u8, "zig"));
        try result.append(try allocator.dupe(u8, "ziglang"));
        return result.toOwnedSlice();
    } else {
        return &[_][]const u8{};
    }
}

fn hints(allocator: *Allocator, buf: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, "hello", buf)) {
        return try allocator.dupe(u8, " World");
    } else {
        return null;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    // Load history and save history later
    ln.history.load("history.txt") catch log.err("Failed to load history", .{});
    defer ln.history.save("history.txt") catch log.err("Failed to save history", .{});

    // Set up hints callback
    ln.hints_callback = hints;

    // Set up completions callback
    ln.completions_callback = completion;

    // Enable mask mode
    // ln.mask_mode = true;

    // Enable multiline mode
    // ln.multiline_mode = true;

    while (try ln.linenoise("hellö> ")) |input| {
        defer allocator.free(input);
        log.info("input: {s}", .{input});
        try ln.history.add(input);
    }
}
