const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const File = std.fs.File;

pub const LinenoiseState = struct {
    alloc: *Allocator,

    stdin: File,
    stdout: File,
    stderr: File,
    buf: Buffer,
    prompt: []const u8,
    pos: usize,
    oldpos: usize,
    size: usize,
    cols: usize,
    maxrows: usize,
    history_index: i32,

    // completions: LinenoiseCompletions,

    // history: [][]u8,

    // rawmode: bool,
    mlmode: bool,

    const Self = @This();

    pub fn clearScreen(self: *Self) !void {
        try self.stdout.writeAll("\x1b[H\x1b[2J");
        try self.refreshLine();
    }

    pub fn beep(self: *Self) void {
        try self.stderr.writeAll("\x07");
    }

    pub fn completeLine(self: *Self) void {
        if (self.completions.len == 0) {
            self.beep();
        }
    }

    fn refreshShowHints(self: *Self, buf: Buffer) void {
    }

    fn refreshSingleLine(self: *Self) !void {
        var buf = try Buffer.initSize(self.alloc, 0);
        defer buf.deinit();

        // Move cursor to left edge
        try buf.appendByte('\r');

        // Write prompt
        try buf.append(self.prompt);

        // Write current buffer content
        try buf.append(self.buf.toSlice());

        // Show hints
        self.refreshShowHints(buf);

        // Erase to the right
        try buf.append("\x1b[0K");

        // Move cursor to original position
        try buf.print("\r\x1b[{}C", .{self.pos + self.prompt.len});

        // Write buffer
        try self.stdin.writeAll(buf.toSliceConst());
    }

    fn refreshMultiLine(self: *Self) void {
    }

    pub fn refreshLine(self: *Self) !void {
        if (self.mlmode) {
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
