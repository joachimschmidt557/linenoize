# zig-linenoise

A port of [linenoise](https://github.com/antirez/linenoise) to zig. It currently
relies on libc for `ioctl`.

## Features

- Line editing
- Completions
- Hints
- History
- Multi line mode
- Mask input mode

## Quick Example

``` zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Linenoise = @import("src/main.zig").Linenoise;

fn completion(alloc: *Allocator, buf: []const u8) ![][]const u8 {
    if (std.mem.eql(u8, "z", buf)) {
        var result = ArrayList([]const u8).init(alloc);
        try result.append(try std.mem.dupe(alloc, u8, "zig"));
        try result.append(try std.mem.dupe(alloc, u8, "ziglang"));
        return result.toOwnedSlice();
    } else {
        return &[_][]const u8{};
    }
}

fn hints(alloc: *Allocator, buf: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, "hello", buf)) {
        return try std.mem.dupe(alloc, u8, " World");
    } else {
        return null;
    }
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    // Load history and save history later
    ln.history.load("history.txt") catch std.debug.warn("Failed to load history\n", .{});
    defer ln.history.save("history.txt") catch std.debug.warn("Failed to save history\n", .{});

    // Set up hints callback
    ln.hints_callback = hints;

    // Set up completions callback
    ln.completions_callback = completion;

    // Enable mask mode
    // ln.mask_mode = true;

    // Enable multiline mode
    // ln.multiline_mode = true;

    while (try ln.linenoise("hello> ")) |input| {
        defer allocator.free(input);
        std.debug.warn("input: {}\n", .{input});
        try ln.history.add(input);
    }
}
```
