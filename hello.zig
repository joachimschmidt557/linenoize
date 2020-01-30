const std = @import("std");

const linenoise = @import("src/main.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    const res = try linenoise.linenoise("hello> ", allocator);
    std.debug.warn("input: {}\n", .{ res });
}
