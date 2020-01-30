const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const File = std.fs.File;

const termios = @cImport({
    @cInclude("termios.h");
});

const unsupported_term = [_][]const u8 { "dumb", "cons25", "emacs" };

const CompletionCallback = fn(input: []u8) void;
const HintsCallback = fn(input: []u8, color: i32, bold: bool) []u8;

const key_null = 0;
const key_ctrl_a = 1;
const key_ctrl_b = 2;
const key_ctrl_c = 3;
const key_ctrl_d = 4;
const key_ctrl_e = 5;
const key_ctrl_f = 6;
const key_ctrl_h = 8;
const key_tab = 9;
const key_ctrl_k = 11;
const key_ctrl_l = 12;
const key_enter = 13;
const key_ctrl_n = 14;
const key_ctrl_p = 16;
const key_ctrl_t = 20;
const key_ctrl_u = 21;
const key_ctrl_w = 23;
const key_bsc = 27;
const key_backspace = 127;

fn isUnsupportedTerm() bool {
    const env_var = std.os.getenv("TERM") orelse return false;

    return for (unsupported_term) |t| {
        if (std.mem.eql(u8, env_var, t))
            break true;
    } else false;
}

fn enableRawMode(fd: File) termios.termios {
    var orig: termios.termios = undefined;
    var raw: termios.termios = undefined;

    _ = termios.tcgetattr(fd.handle, &orig);
    raw = orig;

    raw.c_iflag &= ~(@intCast(c_uint, termios.BRKINT) | @intCast(c_uint, termios.ICRNL) | @intCast(c_uint, termios.INPCK) | @intCast(c_uint, termios.ISTRIP) | @intCast(c_uint, termios.IXON));

    raw.c_oflag &= ~(@intCast(c_uint, termios.OPOST));

    raw.c_cflag |= (@intCast(c_uint, termios.CS8));

    raw.c_lflag &= ~(@intCast(c_uint, termios.ECHO) | @intCast(c_uint, termios.ICANON) | @intCast(c_uint, termios.IEXTEN) | @intCast(c_uint, termios.ISIG));

    raw.c_cc[termios.VMIN] = 1;
    raw.c_cc[termios.VTIME] = 0;

    _ = termios.tcsetattr(fd.handle, termios.TCSAFLUSH, &raw);

    return orig;
}

fn disableRawMode(fd: File, orig: termios.termios) void {
    _ = termios.tcsetattr(fd.handle, termios.TCSAFLUSH, &orig);
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

        .prompt = prompt,
    };

    while (true) {
        switch (c) {
            key_null => {},
            key_ctrl_a => {},
            key_ctrl_b => {},
            key_ctrl_c => {},
            key_ctrl_d => {},
            key_ctrl_e => {},
            key_ctrl_f => {},
            key_ctrl_h => {},
            key_tab => {},
            key_ctrl_k => {},
            key_ctrl_l => {},
            key_enter => {},
            key_ctrl_n => {},
            key_ctrl_p => {},
            key_ctrl_t => {},
            key_ctrl_u => {},
            key_ctrl_w => {},
            key_bsc => {},
            key_backspace => {},
            else => state.editInsert(c),
        }
    }
}

fn linenoiseRaw(in: File, out: File, prompt: []const u8) ![]const u8 {
    const orig = enableRawMode(in);
    const result = linenoiseEdit(in, out, prompt);
    disableRawMode(in, orig);

    try out.write("\n");
    return result;
}

fn linenoiseNoTTY(alloc: *Allocator) ![]const u8 {
    var buf = Buffer.initNull(alloc);
    return try std.io.readLine(&buf);
}

pub fn linenoise(alloc: *Allocator, prompt: []const u8) ![]const u8 {
    const stdin_file = std.io.getStdIn();
    const stdout_file = std.io.getStdOut();

    if (stdin_file.isTty()) {
        if (isUnsupportedTerm()) {
            try stdout_file.write(prompt);

            return "";
        } else {
            return try linenoiseRaw(stdin_file, stdout_file, prompt);
        }
    } else {
        return try linenoiseNoTTY(alloc);
    }
}
