const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const File = std.fs.File;

const unsupported_term = [_][]const u8 { "dumb", "cons25", "emacs" };

const CompletionCallback = fn(input: []u8) void;
const HintsCallback = fn(input: []u8, color: i32, bold: bool) []u8;

const KeyAction = enum {
    KeyNull = 0,
    CtrlA = 1,
    CtrlB = 2,
    CtrlC = 3,
    CtrlD = 4,
    CtrlE = 5,
    CtrlF = 6,
    CtrlH = 8,
    Tab = 9,
    CtrlK = 11,
    CtrlL = 12,
    Enter = 13,
    CtrlN = 14,
    CtrlP = 16,
    CtrlT = 20,
    CtrlU = 21,
    CtrlW = 23,
    Esc = 27,
    Backspace = 127,
};

fn isUnsupportedTerm() bool {
    const env_var = std.os.getenv("TERM") orelse return false;

    return for (unsupported_term) |t| {
        if (std.mem.eql(u8, env_var, t))
            break true;
    } else false;
}

fn enableRawMode(fd: File) void {
}

fn disableRawMode(fd: File) void {
}

fn getCursorPosition(in: File, out: File) !usize {
    var buf: [32]u8 = undefined;
}

fn getColumns(in: File, out: File) usize {
    return 80;
}

pub const LinenoiseCompletions = ArrayList([]const u8);

pub const Linenoise = struct {
    alloc: *Allocator,

    stdin: File,
    stdout: File,
    stderr: File,
    buf: []u8,
    prompt: []const u8,
    pos: usize,
    oldpos: usize,
    size: usize,
    cols: usize,
    maxrows: usize,
    history_index: i32,

    completions: LinenoiseCompletions,

    history: [][]u8,

    rawmode: bool,
    mlmode: bool,

    const Self = @This();

    pub fn clearScreen(self: *Self) !void {
        try self.stdout.write("\x1b[H\x1b[2J");
    }

    pub fn beep(self: *Self) void {
        try self.stderr.write("\x07");
    }

    pub fn completeLine(self: *Self) void {
        if (self.completions.len == 0) {
            self.beep();
        }
    }

    fn refreshShowHints(self: *Self, buf: ArrayList(u8)) void {
    }

    fn refreshSingleLine(self: *Self) void {
        var buf = ArrayList(u8).init(self.alloc);
        defer buf.deinit();

        // Move cursor to left edge
        buf.appendSlice("\r");

        // Write prompt
        buf.appendSlice(self.prompt);

        // Write current buffer content
        buf.appendSlice(self.buf);

        // Show hints
        self.refreshShowHints(buf);

        // Erase to the right
        buf.appendSlice("\x1b[0K");

        // Move cursor to original position
        buf.appendSlice("\r\x1b[%dC");

        // Write buffer
        self.stdin.write(buf.toSliceConst());
    }

    fn refreshMultiLine(self: *Self) void {
    }

    pub fn refreshLine(self: *Self) void {
        if (self.mlmode) {
            self.refreshMultiLine();
        } else {
            self.refreshSingleLine();
        }
    }

    fn editInsert(self: *Self, c: u8) void {
        if (self.len < self.buf.len) {
            if (self.len == self.pos) {
            } else {
                self.buf[self.pos] = c;
                self.len += 1;
                self.pos += 1;
                self.refreshLine();
            }
        }
    }

    fn editMoveLeft(self: *Self) void {
        if (self.pos > 0) {
            self.pos -= 1;
            self.refreshLine();
        }
    }

    fn editMoveRight(self: *Self) void {
        if (self.pos > 0) {
            self.pos += 1;
            self.refreshLine();
        }
    }

    fn editMoveHome(self: *Self) void {
        if (self.pos != 0) {
            self.pos = 0;
            self.refreshLine();
        }
    }

    fn editMoveEnd(self: *Self) void {
        if (self.pos != self.len) {
            self.pos = self.len;
            self.refreshLine();
        }
    }

    fn editDelete(self: *Self) void {
        if (self.len > 0 and self.pos < self.len) {
            for (self.buf[self.pos..self.len-1]) |_, i| {
                self.buf[i] = self.buf[i+1];
            }
            self.len -= 1;
            self.buf[self.len] = 0;
            self.refreshLine();
        }
    }

    fn editBackspace(self: *Self) void {
        if (self.len > 0 and self.pos < self.len) {
            for (self.buf[self.pos..self.len-1]) |_, i| {
                self.buf[i] = self.buf[i+1];
            }
            self.len -= 1;
            self.pos -= 1;
            self.buf[self.len] = 0;
            self.refreshLine();
        }
    }

    fn editDeletePrevWord(self: *Self) void {
    }
};

fn linenoiseEdit(in: File, out: File, prompt: []const u8) []const u8 {
    var state = Linenoise{
        .stdin = in,
        .stdout = out,
    };

    while (true) {
        switch (c) {
            else => state.editInsert(c),
        }
    }
}

fn linenoiseRaw(in: File, out: File, prompt: []const u8) []const u8 {
    enableRawMode(in);
    disableRawMode(in);
    try out.write("\n");
    return "";
}

fn linenoiseNoTTY(alloc: *Allocator) ![]const u8 {
    var buf = Buffer.initNull(alloc);
    return try std.io.readLine(&buf);
}

pub fn linenoise(prompt: []const u8, alloc: *Allocator) ![]const u8 {
    const stdin_file = std.io.getStdIn();
    const stdout_file = std.io.getStdOut();

    if (stdin_file.isTty()) {
        if (isUnsupportedTerm()) {
            try stdout_file.write(prompt);

            return "";
        } else {
            return linenoiseRaw(stdin_file, stdout_file, prompt);
        }
    } else {
        return try linenoiseNoTTY(alloc);
    }
}
