const std = @import("std");

const Linenoise = @import("src/main.zig").Linenoise;

fn completion(buf: []const u8) void {

}

fn hints(buf: []const u8) ?Hint {

}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    while (try ln.linenoise("hello> ")) |input| {
        std.debug.warn("input: {}\n", .{ input });
    }
}
