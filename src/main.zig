const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = std.Buffer;
const File = std.fs.File;

const termios = @cImport({
    @cInclude("termios.h");
});

const ioctl = @cImport({
    @cInclude("sys/ioctl.h");
});

const LinenoiseState = @import("state.zig").LinenoiseState;

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
}

fn getColumns(in: File, out: File) usize {
    var ws: ioctl.winsize = undefined;

    if (ioctl.ioctl(1, ioctl.TIOCGWINSZ, &ws) == -1 or ws.ws_col == 0) {
        // ioctl() didn't work
    } else {
        return ws.ws_col;
    }

    return 80;
}

pub const LinenoiseCompletions = ArrayList([]const u8);

fn linenoiseEdit(allocator: *Allocator, in: File, out: File, err: File, prompt: []const u8) ![]const u8 {
    var state = LinenoiseState {
        .alloc = allocator,

        .stdin = in,
        .stdout = out,
        .stderr = err,
        .prompt = prompt,

        .buf = try Buffer.initSize(allocator, 0),

        .pos = 0,
        .oldpos = 0,
        .size = 0,
        .cols = getColumns(in, out),
        .maxrows = 0,
        .history_index = 0,

        .mlmode = false,
    };

    try out.writeAll(prompt);

    while (true) {
        var input_buf: [1]u8 = undefined;
        const nread = try in.read(&input_buf);
        const c = if (nread == 1) input_buf[0] else return "";

        switch (c) {
            key_null => {},
            key_ctrl_a => try state.editMoveHome(),
            key_ctrl_b => try state.editMoveLeft(),
            key_ctrl_c => {},
            key_ctrl_d => {
                if (state.buf.len() > 0) {
                    try state.editDelete();
                } else {
                    return "";
                }
            },
            key_ctrl_e => try state.editMoveEnd(),
            key_ctrl_f => try state.editMoveRight(),
            key_ctrl_h => {},
            key_tab => {},
            key_ctrl_k => try state.editKillLineForward(),
            key_ctrl_l => try state.clearScreen(),
            key_enter => return state.buf.span(),
            key_ctrl_n => {},
            key_ctrl_p => {},
            key_ctrl_t => try state.editSwapPrev(),
            key_ctrl_u => try state.editKillLineBackward(),
            key_ctrl_w => {},
            key_bsc => {},
            key_backspace => try state.editBackspace(),
            else => try state.editInsert(c),
        }
    }
}

fn linenoiseRaw(allocator: *Allocator, in: File, out: File, err: File, prompt: []const u8) ![]const u8 {
    const orig = try enableRawMode(in);
    const result = try linenoiseEdit(allocator, in, out, err, prompt);
    disableRawMode(in, orig);

    try out.writeAll("\n");
    return result;
}

fn linenoiseNoTTY(alloc: *Allocator, stdin: File) ![]const u8 {
    var stream = stdin.inStream().stream;
    return try stream.readUntilDelimiterAlloc(alloc, '\n', 1024);
}

pub fn linenoise(alloc: *Allocator, prompt: []const u8) ![]const u8 {
    const stdin_file = std.io.getStdIn();
    const stdout_file = std.io.getStdOut();
    const stderr_file = std.io.getStdErr();

    if (stdin_file.isTty()) {
        if (isUnsupportedTerm()) {
            try stdout_file.writeAll(prompt);

            return "";
        } else {
            return try linenoiseRaw(alloc, stdin_file, stdout_file, stderr_file, prompt);
        }
    } else {
        return try linenoiseNoTTY(alloc, stdin_file);
    }
}
