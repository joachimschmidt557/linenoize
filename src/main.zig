const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const File = std.fs.File;

const termios = @cImport({ @cInclude("termios.h"); });
const ioctl = @cImport({ @cInclude("sys/ioctl.h"); });

const LinenoiseState = @import("state.zig").LinenoiseState;
pub const History = @import("history.zig").History;
pub const HintsCallback = (fn (line: []const u8) ?[]const u8);

const unsupported_term = [_][]const u8 { "dumb", "cons25", "emacs" };

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
const key_esc = 27;
const key_backspace = 127;

fn isUnsupportedTerm() bool {
    const env_var = std.os.getenv("TERM") orelse return false;

    return for (unsupported_term) |t| {
        if (std.mem.eql(u8, env_var, t))
            break true;
    } else false;
}

fn enableRawMode(fd: File) !termios.termios {
    var orig: termios.termios = undefined;
    var raw: termios.termios = undefined;

    if (termios.tcgetattr(fd.handle, &orig) < 0) {
        return error.GetAttr;
    }

    raw = orig;

    raw.c_iflag &= ~(@intCast(c_uint, termios.BRKINT) | @intCast(c_uint, termios.ICRNL) | @intCast(c_uint, termios.INPCK) | @intCast(c_uint, termios.ISTRIP) | @intCast(c_uint, termios.IXON));

    raw.c_oflag &= ~(@intCast(c_uint, termios.OPOST));

    raw.c_cflag |= (@intCast(c_uint, termios.CS8));

    raw.c_lflag &= ~(@intCast(c_uint, termios.ECHO) | @intCast(c_uint, termios.ICANON) | @intCast(c_uint, termios.IEXTEN) | @intCast(c_uint, termios.ISIG));

    raw.c_cc[termios.VMIN] = 1;
    raw.c_cc[termios.VTIME] = 0;

    if (termios.tcsetattr(fd.handle, termios.TCSAFLUSH, &raw) < 0) {
        return error.SetAttr;
    }

    return orig;
}

fn disableRawMode(fd: File, orig: termios.termios) void {
    _ = termios.tcsetattr(fd.handle, termios.TCSAFLUSH, &orig);
}

fn getCursorPosition(in: File, out: File) !usize {
    var buf: [32]u8 = undefined;
    var in_stream = in.inStream().stream;

    // Tell terminal to report cursor to in
    try out.writeAll("\x1B[6n");

    // Read answer
    const answer = (try in_stream.readUntilDelimiterOrEof(&buf, 'R')) orelse
        return error.CursorPos;

    // Parse answer
    if (!std.mem.startsWith(u8, "\x1B[", answer))
        return error.CursorPos;

    var iter = std.mem.separate(answer[2..], ";");
    const y = iter.next() orelse return error.CursorPos;
    const x = iter.next() orelse return error.CursorPos;

    return try std.fmt.parseInt(usize, x, 10);
}

fn getColumns(in: File, out: File) usize {
    var ws: ioctl.winsize = undefined;

    if (ioctl.ioctl(1, ioctl.TIOCGWINSZ, &ws) == -1 or ws.ws_col == 0) {
        // ioctl() didn't work
        var out_stream = out.outStream().stream;
        const orig_cursor_pos = getCursorPosition(in, out) catch return 80;

        out_stream.print("\x1B[999C", .{}) catch return 80;
        const cols = getCursorPosition(in, out) catch return 80;

        out_stream.print("\x1B[{}D", .{ orig_cursor_pos }) catch return 80;

        return cols;
    } else {
        return ws.ws_col;
    }

    return 80;
}

fn linenoiseEdit(ln: *Linenoise, in: File, out: File, prompt: []const u8) !?[]const u8 {
    var state = LinenoiseState {
        .alloc = ln.alloc,
        .ln = ln,

        .stdin = in,
        .stdout = out,
        .prompt = prompt,

        .buf = try Buffer.initSize(ln.alloc, 0),

        .pos = 0,
        .oldpos = 0,
        .size = 0,
        .cols = getColumns(in, out),
        .maxrows = 0,

        .mlmode = false,
    };

    try state.ln.history.add("");
    try state.stdout.writeAll(prompt);

    while (true) {
        var input_buf: [1]u8 = undefined;
        const nread = try in.read(&input_buf);
        const c = if (nread == 1) input_buf[0] else return "";

        switch (c) {
            key_null => {},
            key_ctrl_a => try state.editMoveHome(),
            key_ctrl_b => try state.editMoveLeft(),
            key_ctrl_c => return error.CtrlC,
            key_ctrl_d => {
                if (state.buf.len() > 0) {
                    try state.editDelete();
                } else {
                    return null;
                }
            },
            key_ctrl_e => try state.editMoveEnd(),
            key_ctrl_f => try state.editMoveRight(),
            key_ctrl_h => {},
            key_tab => {},
            key_ctrl_k => try state.editKillLineForward(),
            key_ctrl_l => try state.clearScreen(),
            key_enter => return state.buf.span(),
            key_ctrl_n => try state.editHistoryNext(),
            key_ctrl_p => {},
            key_ctrl_t => try state.editSwapPrev(),
            key_ctrl_u => try state.editKillLineBackward(),
            key_ctrl_w => try state.editDeletePrevWord(),
            key_esc => {
                var seq: [3]u8 = undefined;
                try in.readAll(seq[0..2]);
                switch (seq[0]) {
                    '[' => switch (seq[1]) {
                        '0'...'9' => {},
                        'A' => {},
                        'B' => {},
                        'C' => try state.editMoveRight(),
                        'D' => try state.editMoveLeft(),
                        'H' => try state.editMoveHome(),
                        'F' => try state.editMoveEnd(),
                        else => {},
                    },
                    '0' => switch (seq[1]) {
                        'H' => try state.editMoveHome(),
                        'F' => try state.editMoveEnd(),
                        else => {},
                    },
                    else => {}
                }
            },
            key_backspace => try state.editBackspace(),
            else => try state.editInsert(c),
        }
    }
}

fn linenoiseRaw(ln: *Linenoise, in: File, out: File, prompt: []const u8) !?[]const u8 {
    const orig = try enableRawMode(in);
    const result = try linenoiseEdit(ln, in, out, prompt);
    disableRawMode(in, orig);

    try out.writeAll("\n");
    return result;
}

/// Read a line with no special features (no hints, no completions, no history)
fn linenoiseNoTTY(alloc: *Allocator, stdin: File) ![]const u8 {
    var stream = stdin.inStream().stream;
    return try stream.readUntilDelimiterAlloc(alloc, '\n', std.math.maxInt(usize));
}

pub const Linenoise = struct {
    alloc: *Allocator,
    history: History,
    hints_callback: ?HintsCallback,

    const Self = @This();

    pub fn init(alloc: *Allocator) Self {
        return Self{
            .alloc = alloc,
            .history = History.empty(alloc),
            .hints_callback = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.history.deinit();
    }

    pub fn linenoise(self: *Self, prompt: []const u8) !?[]const u8 {
        const stdin_file = std.io.getStdIn();
        const stdout_file = std.io.getStdOut();

        if (stdin_file.isTty()) {
            if (isUnsupportedTerm()) {
                try stdout_file.writeAll(prompt);
                return try linenoiseNoTTY(self.alloc, stdin_file);
            } else {
                return try linenoiseRaw(self, stdin_file, stdout_file, prompt);
            }
        } else {
            return try linenoiseNoTTY(self.alloc, stdin_file);
        }
    }
};
