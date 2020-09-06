const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const bufferedWriter = std.io.bufferedWriter;

const Linenoise = @import("main.zig").Linenoise;
const History = @import("history.zig").History;
const unicode = @import("unicode.zig");
const width = unicode.width;
const toUtf8 = unicode.toUtf8;
const fromUtf8 = unicode.fromUtf8;
const term = @import("term.zig");
const getColumns = term.getColumns;

const key_tab = 9;
const key_esc = 27;

pub const LinenoiseState = struct {
    allocator: *Allocator,
    ln: *Linenoise,

    stdin: File,
    stdout: File,
    buf: ArrayList(u21),
    prompt: []const u8,
    pos: usize,
    old_pos: usize,
    size: usize,
    cols: usize,
    max_rows: usize,

    const Self = @This();

    pub fn init(ln: *Linenoise, in: File, out: File, prompt: []const u8) Self {
        return Self{
            .allocator = ln.allocator,
            .ln = ln,

            .stdin = in,
            .stdout = out,
            .prompt = prompt,
            .buf = ArrayList(u21).init(ln.allocator),
            .pos = 0,
            .old_pos = 0,
            .size = 0,
            .cols = getColumns(in, out),
            .max_rows = 0,
        };
    }

    pub fn clearScreen(self: *Self) !void {
        try self.stdout.writeAll("\x1b[H\x1b[2J");
        try self.refreshLine();
    }

    pub fn beep(self: *Self) !void {
        const stderr = std.io.getStdErr();
        try stderr.writeAll("\x07");
    }

    pub fn browseCompletions(self: *Self) !?u8 {
        var input_buf: [1]u8 = undefined;
        var c: ?u8 = null;

        const fun = self.ln.completions_callback orelse return null;
        const buf_utf8 = try toUtf8(self.allocator, self.buf.items);
        defer self.allocator.free(buf_utf8);

        const completions = try fun(self.allocator, buf_utf8);
        defer {
            for (completions) |x| self.allocator.free(x);
            self.allocator.free(completions);
        }

        if (completions.len == 0) {
            try self.beep();
        } else {
            var finished = false;
            var i: usize = 0;

            while (!finished) {
                if (i < completions.len) {
                    // Change to completion nr. i
                    // First, save buffer so we can restore it later
                    const old_buf_allocator = self.buf.allocator;
                    const old_buf = self.buf.toOwnedSlice();
                    const old_pos = self.pos;

                    // Show suggested completion
                    self.buf.deinit();
                    self.buf = ArrayList(u21).init(old_buf_allocator);

                    const completion_unicode = try fromUtf8(self.allocator, completions[i]);
                    defer self.allocator.free(completion_unicode);
                    try self.buf.appendSlice(completion_unicode);

                    self.pos = self.buf.items.len;
                    try self.refreshLine();

                    // Restore original buffer into state
                    self.buf.deinit();
                    self.buf = ArrayList(u21).fromOwnedSlice(old_buf_allocator, old_buf);
                    self.pos = old_pos;
                } else {
                    // Return to original line
                    try self.refreshLine();
                }

                // Read next key
                const nread = try self.stdin.read(&input_buf);
                c = if (nread == 1) input_buf[0] else return error.NothingRead;

                switch (c.?) {
                    key_tab => {
                        // Next completion
                        i = (i + 1) % (completions.len + 1);
                        if (i == completions.len) try self.beep();
                    },
                    key_esc => {
                        // Stop browsing completions, return to buffer displayed
                        // prior to browsing completions
                        if (i < completions.len) try self.refreshLine();
                        finished = true;
                    },
                    else => {
                        // Stop browsing completions, potentially use suggested
                        // completion
                        if (i < completions.len) {
                            // Replace buffer with text in the selected
                            // completion
                            const old_buf_allocator = self.buf.allocator;
                            self.buf.deinit();
                            self.buf = ArrayList(u21).init(old_buf_allocator);

                            const completion_unicode = try fromUtf8(self.allocator, completions[i]);
                            defer self.allocator.free(completion_unicode);
                            try self.buf.appendSlice(completion_unicode);

                            self.pos = self.buf.items.len;
                        }
                        finished = true;
                    },
                }
            }
        }

        return c;
    }

    fn getHint(self: *Self) !?[]const u8 {
        if (self.ln.hints_callback) |fun| {
            const buf_utf8 = try toUtf8(self.allocator, self.buf.items);
            defer self.allocator.free(buf_utf8);
            return try fun(self.allocator, buf_utf8);
        }

        return null;
    }

    fn refreshSingleLine(self: *Self) !void {
        var buf = bufferedWriter(self.stdout.writer());
        var writer = buf.writer();

        const hint = try self.getHint();
        defer if (hint) |str| self.allocator.free(str);

        // Trim buffer if it is too long
        const prompt_width = width(self.prompt);
        const hint_width = if (hint) |str| width(str) else 0;
        const avail_space = self.cols - prompt_width - hint_width - 1;
        const start = if (self.pos > avail_space) self.pos - avail_space else 0;
        const end = if (start + avail_space < self.buf.items.len) start + avail_space else self.buf.items.len;
        const trimmed_buf = self.buf.items[start..end];

        // Move cursor to left edge
        try writer.writeAll("\r");

        // Write prompt
        try writer.writeAll(self.prompt);

        // Write current buffer content
        if (self.ln.mask_mode) {
            for (trimmed_buf) |_| {
                try writer.writeAll("*");
            }
        } else {
            const trimmed_buf_utf8 = try toUtf8(self.allocator, trimmed_buf);
            defer self.allocator.free(trimmed_buf_utf8);
            try writer.writeAll(trimmed_buf_utf8);
        }

        // Show hints
        if (hint) |str| {
            try writer.writeAll(str);
        }

        // Erase to the right
        try writer.writeAll("\x1b[0K");

        // Move cursor to original position
        const pos = if (self.pos > avail_space) self.cols - hint_width - 1 else prompt_width + self.pos;
        try writer.print("\r\x1b[{}C", .{pos});

        // Write buffer
        try buf.flush();
    }

    fn refreshMultiLine(self: *Self) !void {
        var buf = bufferedWriter(self.stdout.writer());
        var writer = buf.writer();

        const hint = try self.getHint();
        defer if (hint) |str| self.allocator.free(str);

        const prompt_width = width(self.prompt);
        const hint_width = if (hint) |str| width(str) else 0;
        const total_width = prompt_width + self.buf.items.len + hint_width;
        var rows = (total_width + self.cols - 1) / self.cols;
        var rpos = (prompt_width + self.old_pos + self.cols) / self.cols;
        const old_rows = self.max_rows;

        if (rows > self.max_rows) {
            self.max_rows = rows;
        }

        // Go to the last row
        if (old_rows > rpos) {
            try writer.print("\x1B[{}B", .{old_rows - rpos});
        }

        // Clear every row
        if (old_rows > 0) {
            var j: usize = 0;
            while (j < old_rows - 1) : (j += 1) {
                try writer.writeAll("\r\x1B[0K\x1B[1A");
            }
        }

        // Clear the top line
        try writer.writeAll("\r\x1B[0K");

        // Write prompt
        try writer.writeAll(self.prompt);

        // Write current buffer content
        if (self.ln.mask_mode) {
            for (self.buf.items) |_| {
                try writer.writeAll("*");
            }
        } else {
            const buf_utf8 = try toUtf8(self.allocator, self.buf.items);
            defer self.allocator.free(buf_utf8);
            try writer.writeAll(buf_utf8);
        }

        // Show hints if applicable
        if (hint) |str| {
            try writer.writeAll(str);
        }

        // Reserve a newline if we filled all columns
        if (self.pos > 0 and self.pos == self.buf.items.len and total_width % self.cols == 0) {
            try writer.writeAll("\n\r");
            rows += 1;
            if (rows > self.max_rows) {
                self.max_rows = rows;
            }
        }

        // Move cursor to right position:
        const rpos2 = (prompt_width + self.pos + self.cols) / self.cols;

        // First, y position
        if (rows > rpos2) {
            try writer.print("\x1B[{}A", .{rows - rpos2});
        }

        // Then, x position
        const col = (prompt_width + self.pos) % self.cols;
        if (col > 0) {
            try writer.print("\r\x1B[{}C", .{col});
        } else {
            try writer.writeAll("\r");
        }

        self.old_pos = self.pos;

        try buf.flush();
    }

    pub fn refreshLine(self: *Self) !void {
        if (self.ln.multiline_mode) {
            try self.refreshMultiLine();
        } else {
            try self.refreshSingleLine();
        }
    }

    pub fn editInsert(self: *Self, c: u21) !void {
        try self.buf.resize(self.buf.items.len + 1);
        if (self.buf.items.len > 0 and self.pos < self.buf.items.len - 1) {
            std.mem.copyBackwards(
                u21,
                self.buf.items[self.pos + 1 .. self.buf.items.len],
                self.buf.items[self.pos .. self.buf.items.len - 1],
            );
        }

        self.buf.items[self.pos] = c;
        self.pos += 1;
        try self.refreshLine();
    }

    pub fn editMoveLeft(self: *Self) !void {
        if (self.pos > 0) {
            self.pos -= 1;
            try self.refreshLine();
        }
    }

    pub fn editMoveRight(self: *Self) !void {
        if (self.pos < self.buf.items.len) {
            self.pos += 1;
            try self.refreshLine();
        }
    }

    pub fn editMoveWordEnd(self: *Self) !void {
        if (self.pos < self.buf.items.len) {
            while (self.pos < self.buf.items.len and self.buf.items[self.pos] == ' ')
                self.pos += 1;
            while (self.pos < self.buf.items.len and self.buf.items[self.pos] != ' ')
                self.pos += 1;
            try self.refreshLine();
        }
    }

    pub fn editMoveWordStart(self: *Self) !void {
        if (self.buf.items.len > 0 and self.pos > 0) {
            while (self.pos > 0 and self.buf.items[self.pos - 1] == ' ')
                self.pos -= 1;
            while (self.pos > 0 and self.buf.items[self.pos - 1] != ' ')
                self.pos -= 1;
            try self.refreshLine();
        }
    }

    pub fn editMoveHome(self: *Self) !void {
        if (self.pos > 0) {
            self.pos = 0;
            try self.refreshLine();
        }
    }

    pub fn editMoveEnd(self: *Self) !void {
        if (self.pos < self.buf.items.len) {
            self.pos = self.buf.items.len;
            try self.refreshLine();
        }
    }

    pub const HistoryDirection = enum {
        next,
        prev,
    };

    pub fn editHistoryNext(self: *Self, dir: HistoryDirection) !void {
        if (self.ln.history.hist.items.len > 0) {
            // Update the current history with the current line
            const old_index = self.ln.history.current;
            const current_entry = self.ln.history.hist.items[old_index];
            self.ln.history.allocator.free(current_entry);
            self.ln.history.hist.items[old_index] = try self.ln.history.allocator.dupe(u21, self.buf.items);

            // Update history index
            const new_index = switch (dir) {
                .next => if (old_index < self.ln.history.hist.items.len - 1) old_index + 1 else self.ln.history.hist.items.len - 1,
                .prev => if (old_index > 0) old_index - 1 else 0,
            };
            self.ln.history.current = new_index;

            // Copy history entry to the current line buffer
            self.buf.deinit();
            self.buf = ArrayList(u21).init(self.allocator);
            try self.buf.appendSlice(self.ln.history.hist.items[new_index]);
            self.pos = self.buf.items.len;

            try self.refreshLine();
        }
    }

    pub fn editDelete(self: *Self) !void {
        if (self.buf.items.len > 0 and self.pos < self.buf.items.len) {
            std.mem.copy(u21, self.buf.items[self.pos..], self.buf.items[self.pos + 1 ..]);
            try self.buf.resize(self.buf.items.len - 1);
            try self.refreshLine();
        }
    }

    pub fn editBackspace(self: *Self) !void {
        if (self.buf.items.len > 0 and self.pos > 0) {
            std.mem.copy(u21, self.buf.items[self.pos - 1 ..], self.buf.items[self.pos..]);
            self.pos -= 1;
            try self.buf.resize(self.buf.items.len - 1);
            try self.refreshLine();
        }
    }

    pub fn editSwapPrev(self: *Self) !void {
        if (self.pos > 1) {
            std.mem.swap(u21, &self.buf.items[self.pos - 1], &self.buf.items[self.pos - 2]);
            try self.refreshLine();
        }
    }

    pub fn editDeletePrevWord(self: *Self) !void {
        if (self.buf.items.len > 0 and self.pos > 0) {
            const old_pos = self.pos;
            while (self.pos > 0 and self.buf.items[self.pos - 1] == ' ')
                self.pos -= 1;
            while (self.pos > 0 and self.buf.items[self.pos - 1] != ' ')
                self.pos -= 1;

            const diff = old_pos - self.pos;
            const new_len = self.buf.items.len - diff;
            std.mem.copy(u21, self.buf.items[self.pos..new_len], self.buf.items[old_pos..]);
            try self.buf.resize(new_len);
            try self.refreshLine();
        }
    }

    pub fn editKillLineForward(self: *Self) !void {
        try self.buf.resize(self.pos);
        try self.refreshLine();
    }

    pub fn editKillLineBackward(self: *Self) !void {
        const new_len = self.buf.items.len - self.pos;
        std.mem.copy(u21, self.buf.items, self.buf.items[self.pos..]);
        self.pos = 0;
        try self.buf.resize(new_len);
        try self.refreshLine();
    }
};
