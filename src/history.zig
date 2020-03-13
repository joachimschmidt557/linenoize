const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const History = struct {
    alloc: *Allocator,
    hist: ArrayList([]const u8),
    current: usize,

    const Self = @This();

    /// Creates a new empty history
    pub fn empty(alloc: *Allocator) Self {
        return Self{
            .alloc = alloc,
            .hist = ArrayList([]const u8).init(alloc),
            .current = 0,
        };
    }

    /// Deinitializes the history
    pub fn deinit(self: *Self) void {
        for (self.hist.toSlice()) |x| self.alloc.free(x);
        self.hist.deinit();
    }

    /// Adds this line to the history. Does not take ownership of the line, but
    /// instead copies it
    pub fn add(self: *Self, line: []const u8) !void {
        if (self.hist.len < 1 or !std.mem.eql(u8, line, self.hist.toSlice()[self.hist.len - 1])) {
            try self.hist.append(try std.mem.dupe(self.alloc, u8, line));
        }
    }

    pub fn pop(self: *Self) void {
        self.alloc.free(self.hist.pop());
    }

    /// Loads the history from a file
    pub fn load(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const max_line_len = std.mem.page_size;

        const stream = &file.inStream().stream;
        while (stream.readUntilDelimiterAlloc(self.alloc, '\n', max_line_len)) |line| {
            try self.hist.append(line);
        } else |err| {
            switch (err) {
                error.EndOfStream => return,
                else => return err,
            }
        }
    }

    /// Saves the history to a file
    pub fn save(path: []const u8) !void {
        const file = try std.fs.File.openWrite(path);
        defer file.close();

        for (self.hist.toSlice()) |line| {
            try file.writeAll(line);
            try file.writeAll("\n");
        }
    }
};
