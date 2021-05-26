# linenoize

A port of [linenoise](https://github.com/antirez/linenoise) to zig
aiming to be a simple readline for command-line applications written
in zig. It is written in pure zig and doesn't require libc.

In addition to being a full-fledged zig library, `linenoize` also
serves as a drop-in replacement for linenoise. As a proof of concept,
the example application from linenoise can be built with `zig build
c-example`.

## Features

- Line editing
- Completions
- Hints
- History
- Multi line mode
- Mask input mode

### Supported platforms

- Linux
- macOS (Experimental)
- TODO: Windows
- TODO: FreeBSD

## Examples

### Minimal example

```zig
const std = @import("std");
const Linenoise = @import("linenoise").Linenoise;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    while (try ln.linenoise("hello> ")) |input| {
        defer allocator.free(input);
        std.debug.print("input: {s}\n", .{input});
        try ln.history.add(input);
    }
}
```

### Example of more features

``` zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Linenoise = @import("linenoise").Linenoise;

fn completion(alloc: *Allocator, buf: []const u8) ![][]const u8 {
    if (std.mem.eql(u8, "z", buf)) {
        var result = ArrayList([]const u8).init(alloc);
        try result.append(try alloc.dupe(u8, "zig"));
        try result.append(try alloc.dupe(u8, "ziglang"));
        return result.toOwnedSlice();
    } else {
        return &[_][]const u8{};
    }
}

fn hints(alloc: *Allocator, buf: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, "hello", buf)) {
        return try alloc.dupe(u8, " World");
    } else {
        return null;
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    // Load history and save history later
    ln.history.load("history.txt") catch std.debug.print("Failed to load history\n", .{});
    defer ln.history.save("history.txt") catch std.debug.print("Failed to save history\n", .{});

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
        std.debug.print("input: {s}\n", .{input});
        try ln.history.add(input);
    }
}
```
