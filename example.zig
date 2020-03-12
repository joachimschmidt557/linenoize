const std = @import("std");

const linenoise = @import("src/main.zig");

fn completion(buf: []const u8) void {

}

fn hints(buf: []const u8) ?Hint {

}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    const res = try linenoise.linenoise(allocator, "hello> ");
    std.debug.warn("input: {}\n", .{ res });
}
