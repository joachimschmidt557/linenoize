const std = @import("std");

const Linenoise = @import("src/main.zig").Linenoise;

fn completion(buf: []const u8) void {

}

fn hints(buf: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, "hello", buf)) {
        return " World";
    } else {
        return null;
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // const allocator = &arena.allocator;
    const allocator = std.heap.c_allocator;

    var ln = Linenoise.init(allocator);
    defer ln.deinit();

    // Set up hints callback
    ln.hints_callback = hints;

    while (try ln.linenoise("hello> ")) |input| {
        defer allocator.free(input);
        std.debug.warn("input: {}\n", .{ input });
        try ln.history.add(input);
    }
}
