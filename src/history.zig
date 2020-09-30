const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub const History = struct {
    allocator: *Allocator,
    hist: ArrayListUnmanaged([]const u8),
    current: usize,

    const Self = @This();

    /// Creates a new empty history
    pub fn empty(allocator: *Allocator) Self {
        return Self{
            .allocator = allocator,
            .hist = .{},
            .current = 0,
        };
    }

    /// Deinitializes the history
    pub fn deinit(self: *Self) void {
        for (self.hist.items) |x| self.allocator.free(x);
        self.hist.deinit(self.allocator);
    }

    /// Adds this line to the history. Does not take ownership of the line, but
    /// instead copies it
    pub fn add(self: *Self, line: []const u8) !void {
        if (self.hist.items.len < 1 or !std.mem.eql(u8, line, self.hist.items[self.hist.items.len - 1])) {
            try self.hist.append(self.allocator, try self.allocator.dupe(u8, line));
        }
    }

    /// Removes the last item (newest item) of the history
    pub fn pop(self: *Self) void {
        self.allocator.free(self.hist.pop());
    }

    /// Loads the history from a file
    pub fn load(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const max_line_len = std.math.maxInt(usize);

        var reader = file.reader();
        while (reader.readUntilDelimiterAlloc(self.allocator, '\n', max_line_len)) |line| {
            try self.hist.append(self.allocator, line);
        } else |err| {
            switch (err) {
                error.EndOfStream => return,
                else => return err,
            }
        }
    }

    /// Saves the history to a file
    pub fn save(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        for (self.hist.items) |line| {
            try file.writeAll(line);

            try file.writeAll("\n");
        }
    }
};

test "history" {
    var hist = History.empty(std.testing.allocator);
    defer hist.deinit();

    try hist.add("Hello");
    hist.pop();
}
