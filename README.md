# linenoize

A port of [linenoise](https://github.com/antirez/linenoise) to zig
aiming to be a simple readline for command-line applications written
in zig. It is written in pure zig and doesn't require
libc. `linenoize` works with the latest stable zig version (0.14.0).

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
- macOS
- Windows

## Add linenoize to a project

Add linenoize as a dependency to your project:
```bash
zig fetch --save git+https://github.com/joachimschmidt557/linenoize.git#v0.1.0
```

Then add the following code to your `build.zig` file:
```zig
const linenoize = b.dependency("linenoize", .{
    .target = target,
    .optimize = optimize,
}).module("linenoise");
exe.root_module.addImport("linenoize", linenoize);
```

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

const log = std.log.scoped(.main);

const Linenoise = @import("linenoise").Linenoise;

fn completion(allocator: Allocator, buf: []const u8) ![]const []const u8 {
    if (std.mem.eql(u8, "z", buf)) {
        var result = ArrayList([]const u8).init(allocator);
        try result.append(try allocator.dupe(u8, "zig"));
        try result.append(try allocator.dupe(u8, "ziglang"));
        return result.toOwnedSlice();
    } else {
        return &[_][]const u8{};
    }
}

fn hints(allocator: Allocator, buf: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, "hello", buf)) {
        return try allocator.dupe(u8, " World");
    } else {
        return null;
    }
}

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

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
```
