const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.ArrayList(u8);
const File = std.fs.File;

const Linenoise = @import("main.zig").Linenoise;
const History = @import("history.zig").History;

const key_tab = 9;
const key_esc = 27;

pub const LinenoiseState = struct {
    alloc: *Allocator,
    ln: *Linenoise,

    stdin: File,
    stdout: File,
    buf: Buffer,
    prompt: []const u8,
    pos: usize,
    old_pos: usize,
    size: usize,
    cols: usize,
    max_rows: usize,

    const Self = @This();

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
        const completions = try fun(self.alloc, self.buf.span());
        defer {
            for (completions) |x| self.alloc.free(x);
            self.alloc.free(completions);
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
                    const old_buf_alloc = self.buf.allocator;
                    const old_buf = self.buf.toOwnedSlice();
                    const old_pos = self.pos;

                    // Show suggested completion
                    self.buf.deinit();
                    self.buf = Buffer.init(old_buf_alloc);
                    try self.buf.appendSlice(completions[i]);
                    self.pos = self.buf.len;
                    try self.refreshLine();

                    // Restore original buffer into state
                    self.buf.deinit();
                    self.buf = Buffer.fromOwnedSlice(old_buf_alloc, old_buf);
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
                            const old_buf_alloc = self.buf.allocator;
                            self.buf.deinit();
                            self.buf = Buffer.init(old_buf_alloc);
                            try self.buf.appendSlice(completions[i]);
                            self.pos = self.buf.len;
                        }
                        finished = true;
                    },
                }
            }
        }

        return c;
    }

    fn refreshShowHints(self: *Self, buf: *Buffer) !void {
        if (self.ln.hints_callback) |fun| {
            const hint = try fun(self.alloc, self.buf.span());
            if (hint) |str| {
                defer self.alloc.free(str);
                try buf.appendSlice(str);
            }
        }
    }

    fn refreshSingleLine(self: *Self) !void {
        var buf = Buffer.init(self.alloc);
        defer buf.deinit();

        // Trim buffer if it is too long
        const avail_space = self.cols - self.prompt.len;
        const start = if (self.pos > avail_space) self.pos - avail_space else 0;
        const end = if (start + avail_space < self.buf.len) start + avail_space else self.buf.len;
        const trimmed_buf = self.buf.span()[start..end];

        // Move cursor to left edge
        try buf.append('\r');

        // Write prompt
        try buf.appendSlice(self.prompt);

        // Write current buffer content
        if (self.ln.mask_mode) {
            for (trimmed_buf) |_| {
                try buf.append('*');
            }
        } else {
            try buf.appendSlice(trimmed_buf);
        }

        // Show hints
        try self.refreshShowHints(&buf);

        // Erase to the right
        try buf.appendSlice("\x1b[0K");

        // Move cursor to original position
        try buf.outStream().print("\r\x1b[{}C", .{self.pos + self.prompt.len});

        // Write buffer
        try self.stdout.writeAll(buf.span());
    }

    fn refreshMultiLine(self: *Self) !void {
        var buf = Buffer.init(self.alloc);
        defer buf.deinit();

        var rows = (self.prompt.len + self.buf.len + self.cols - 1) / self.cols;
        var rpos = (self.prompt.len + self.old_pos + self.cols) / self.cols;
        const old_rows = self.max_rows;

        if (rows > self.max_rows) {
            self.max_rows = rows;
        }

        // Go to the last row
        if (old_rows > rpos) {
            try buf.outStream().print("\x1B[{}B", .{ old_rows - rpos });
        }

        // Clear every row
        if (old_rows > 0) {
            var j: usize = 0;
            while (j < old_rows - 1) : (j += 1) {
                try buf.appendSlice("\r\x1B[0K\x1B[1A");
            }
        }

        // Clear the top line
        try buf.appendSlice("\r\x1B[0K");

        // Write prompt
        try buf.appendSlice(self.prompt);

        // Write current buffer content
        if (self.ln.mask_mode) {
            for (self.buf.span()) |_| {
                try buf.append('*');
            }
        } else {
            try buf.appendSlice(self.buf.span());
        }

        // Reserve a newline if we filled all columns
        if (self.pos > 0 and self.pos == self.buf.len and (self.pos + self.prompt.len) % self.cols == 0) {
            try buf.appendSlice("\n\r");
            rows += 1;
            if (rows > self.max_rows) {
                self.max_rows = rows;
            }
        }

        // Move cursor to right position:
        const rpos2 = (self.prompt.len + self.pos + self.cols) / self.cols;

        // First, y position
        if (rows > rpos2) {
            try buf.outStream().print("\x1B[{}A", .{ rows - rpos2 });
        }

        // Then, x position
        const col = (self.prompt.len + self.pos) % self.cols;
        if (col > 0) {
            try buf.outStream().print("\r\x1B[{}C", .{ col });
        } else {
            try buf.appendSlice("\r");
        }

        self.old_pos = self.pos;

        try self.stdout.writeAll(buf.span());
    }

    pub fn refreshLine(self: *Self) !void {
        if (self.ln.multiline_mode) {
            try self.refreshMultiLine();
        } else {
            try self.refreshSingleLine();
        }
    }

    fn editInsert(self: *Self, c: u8) !void {
        try self.buf.resize(self.buf.len + 1);

        self.buf.span()[self.pos] = c;
        self.pos += 1;
        try self.refreshLine();
    }

    fn editMoveLeft(self: *Self) !void {
        if (self.pos > 0) {
            self.pos -= 1;
            try self.refreshLine();
        }
    }

    fn editMoveRight(self: *Self) !void {
        if (self.pos < self.buf.len) {
            self.pos += 1;
            try self.refreshLine();
        }
    }

    fn editMoveHome(self: *Self) !void {
        if (self.pos > 0) {
            self.pos = 0;
            try self.refreshLine();
        }
    }

    fn editMoveEnd(self: *Self) !void {
        if (self.pos < self.buf.len) {
            self.pos = self.buf.len;
            try self.refreshLine();
        }
    }

    pub const HistoryDirection = enum {
        Next,
        Prev,
    };

    fn editHistoryNext(self: *Self, dir: HistoryDirection) !void {
        if (self.ln.history.hist.len > 0) {
            // Update the current history with the current line
            const old_index = self.ln.history.current;
            const current_entry = self.ln.history.hist.toSlice()[old_index];
            self.ln.history.alloc.free(current_entry);
            self.ln.history.hist.toSlice()[old_index] = try std.mem.dupe(self.ln.history.alloc, u8, self.buf.span());

            // Update history index
            const new_index = switch(dir) {
                .Next => if (old_index < self.ln.history.hist.len - 1) old_index + 1 else self.ln.history.hist.len - 1,
                .Prev => if (old_index > 0) old_index - 1 else 0,
            };
            self.ln.history.current = new_index;

            // Copy history entry to the current line buffer
            self.buf.deinit();
            self.buf = Buffer.init(self.alloc);
            try self.buf.appendSlice(self.ln.history.hist.toSlice()[new_index]);
            self.pos = self.buf.len;

            try self.refreshLine();
        }
    }

    fn editDelete(self: *Self) !void {
        if (self.buf.len > 0 and self.pos < self.buf.len) {
            std.mem.copy(u8, self.buf.span()[self.pos..], self.buf.span()[self.pos + 1..]);
            try self.buf.resize(self.buf.len - 1);
            try self.refreshLine();
        }
    }

    fn editBackspace(self: *Self) !void {
        if (self.buf.len > 0 and self.pos > 0) {
            std.mem.copy(u8, self.buf.span()[self.pos - 1..], self.buf.span()[self.pos..]);
            self.pos -= 1;
            try self.buf.resize(self.buf.len - 1);
            try self.refreshLine();
        }
    }

    fn editSwapPrev(self: *Self) !void {
        if (self.pos > 1) {
            std.mem.swap(u8, &self.buf.span()[self.pos - 1], &self.buf.span()[self.pos - 2]);
            try self.refreshLine();
        }
    }

    fn editDeletePrevWord(self: *Self) !void {
        if (self.buf.len > 0 and self.pos > 0) {
            const old_pos = self.pos;
            while (self.pos > 0 and self.buf.span()[self.pos - 1] == ' ')
                self.pos -= 1;
            while (self.pos > 0 and self.buf.span()[self.pos - 1] != ' ')
                self.pos -= 1;

            const diff = old_pos - self.pos;
            const new_len = self.buf.len - diff;
            std.mem.copy(u8, self.buf.span()[self.pos..new_len], self.buf.span()[old_pos..]);
            try self.buf.resize(new_len);
            try self.refreshLine();
        }
    }

    fn editKillLineForward(self: *Self) !void {
        try self.buf.resize(self.pos);
        try self.refreshLine();
    }

    fn editKillLineBackward(self: *Self) !void {
        const new_len = self.buf.len - self.pos;
        std.mem.copy(u8, self.buf.span(), self.buf.span()[self.pos..]);
        self.pos = 0;
        try self.buf.resize(new_len);
        try self.refreshLine();
    }
};
