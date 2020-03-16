const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
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
    oldpos: usize,
    size: usize,
    cols: usize,
    maxrows: usize,

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
        const completions = try fun(self.alloc, self.buf.toSlice());
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
                    const old_buf_alloc = self.buf.list.allocator;
                    const old_buf = self.buf.toOwnedSlice();
                    const old_pos = self.pos;

                    // Show suggested completion
                    try self.buf.replaceContents(completions[i]);
                    self.pos = self.buf.len();
                    try self.refreshLine();

                    // Restore original buffer into state
                    self.buf.deinit();
                    self.buf = try Buffer.fromOwnedSlice(old_buf_alloc, old_buf);
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
                            const old_buf_alloc = self.buf.list.allocator;
                            self.buf.deinit();
                            self.buf = try Buffer.init(old_buf_alloc, completions[i]);
                            self.pos = self.buf.len();
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
            const hint = try fun(self.alloc, self.buf.toSlice());
            if (hint) |str| {
                defer self.alloc.free(str);
                try buf.append(str);
            }
        }
    }

    fn refreshSingleLine(self: *Self) !void {
        var buf = try Buffer.initSize(self.alloc, 0);
        defer buf.deinit();

        // Move cursor to left edge
        try buf.appendByte('\r');

        // Write prompt
        try buf.append(self.prompt);

        // Write current buffer content
        if (self.ln.mask_mode) {
            for (self.buf.toSlice()) |_| {
                try buf.appendByte('*');
            }
        } else {
            try buf.append(self.buf.toSlice());
        }

        // Show hints
        try self.refreshShowHints(&buf);

        // Erase to the right
        try buf.append("\x1b[0K");

        // Move cursor to original position
        try buf.outStream().print("\r\x1b[{}C", .{self.pos + self.prompt.len});

        // Write buffer
        try self.stdin.writeAll(buf.toSliceConst());
    }

    fn refreshMultiLine(self: *Self) void {
    }

    pub fn refreshLine(self: *Self) !void {
        if (self.ln.multiline_mode) {
            self.refreshMultiLine();
        } else {
            try self.refreshSingleLine();
        }
    }

    fn editInsert(self: *Self, c: u8) !void {
        try self.buf.resize(self.buf.len() + 1);

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
        if (self.pos < self.buf.len()) {
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
        if (self.pos < self.buf.len()) {
            self.pos = self.buf.len();
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
            try self.buf.replaceContents(self.ln.history.hist.toSlice()[new_index]);
            self.pos = self.buf.len();

            try self.refreshLine();
        }
    }

    fn editDelete(self: *Self) !void {
        if (self.buf.len() > 0 and self.pos < self.buf.len()) {
            std.mem.copy(u8, self.buf.span()[self.pos..], self.buf.span()[self.pos + 1..]);
            try self.buf.resize(self.buf.len() - 1);
            try self.refreshLine();
        }
    }

    fn editBackspace(self: *Self) !void {
        if (self.buf.len() > 0 and self.pos > 0) {
            std.mem.copy(u8, self.buf.span()[self.pos - 1..], self.buf.span()[self.pos..]);
            self.pos -= 1;
            try self.buf.resize(self.buf.len() - 1);
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
        if (self.buf.len() > 0 and self.pos > 0) {
            const old_pos = self.pos;
            while (self.pos > 0 and self.buf.span()[self.pos - 1] == ' ')
                self.pos -= 1;
            while (self.pos > 0 and self.buf.span()[self.pos - 1] != ' ')
                self.pos -= 1;

            const diff = old_pos - self.pos;
            const new_len = self.buf.len() - diff;
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
        const new_len = self.buf.len() - self.pos;
        std.mem.copy(u8, self.buf.span(), self.buf.span()[self.pos..]);
        self.pos = 0;
        try self.buf.resize(new_len);
        try self.refreshLine();
    }
};
