const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const unicode = @import("unicode.zig");
const toUtf8 = unicode.toUtf8;
const fromUtf8 = unicode.fromUtf8;

pub const History = struct {
    alloc: *Allocator,
    hist: ArrayList([]const u21),
    current: usize,

    const Self = @This();

    /// Creates a new empty history
    pub fn empty(alloc: *Allocator) Self {
        return Self{
            .alloc = alloc,
            .hist = ArrayList([]const u21).init(alloc),
            .current = 0,
        };
    }

    /// Deinitializes the history
    pub fn deinit(self: *Self) void {
        for (self.hist.items) |x| self.alloc.free(x);
        self.hist.deinit();
    }

    /// Adds this line to the history. Does not take ownership of the line, but
    /// instead copies it
    pub fn add(self: *Self, line: []const u21) !void {
        if (self.hist.items.len < 1 or !std.mem.eql(u21, line, self.hist.items[self.hist.items.len - 1])) {
            try self.hist.append(try self.alloc.dupe(u21, line));
        }
    }

    /// Adds a UTF-8 encoded line
    pub fn addUtf8(self: *Self, line: []const u8) !void {
        const line_unicode = try fromUtf8(self.alloc, line);
        defer self.alloc.free(line_unicode);

        try self.add(line_unicode);
    }

    /// Removes the last item (newest item) of the history
    pub fn pop(self: *Self) void {
        self.alloc.free(self.hist.pop());
    }

    /// Loads the history from a file
    pub fn load(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const max_line_len = std.mem.page_size;

        var reader = file.reader();
        while (reader.readUntilDelimiterAlloc(self.alloc, '\n', max_line_len)) |line| {
            defer self.alloc.free(line);
            try self.hist.append(try fromUtf8(self.alloc, line));
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
            const line_utf8 = try toUtf8(self.alloc, line);
            defer self.alloc.free(line_utf8);
            try file.writeAll(line_utf8);

            try file.writeAll("\n");
        }
    }
};
