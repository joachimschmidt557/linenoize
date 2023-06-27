const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Allocator = mem.Allocator;

const Linenoise = @import("main.zig").Linenoise;
const term = @import("term.zig");

const global_allocator = std.heap.c_allocator;
var global_linenoise: ?Linenoise = null;

var c_completion_callback: ?linenoiseCompletionCallback = null;
var c_hints_callback: ?linenoiseHintsCallback = null;
var c_free_hints_callback: ?linenoiseFreeHintsCallback = null;

const LinenoiseCompletions = extern struct {
    len: usize,
    cvec: ?[*][*:0]u8,

    pub fn free(self: *LinenoiseCompletions) void {
        if (self.cvec) |raw_completions| {
            const len: usize = @intCast(self.len);
            for (raw_completions[0..len]) |x| global_allocator.free(mem.span(x));
            global_allocator.free(raw_completions[0..len]);
        }
    }
};

const linenoiseCompletionCallback = *const fn ([*:0]const u8, *LinenoiseCompletions) callconv(.C) void;
const linenoiseHintsCallback = *const fn ([*:0]const u8, *c_int, *c_int) callconv(.C) ?[*:0]u8;
const linenoiseFreeHintsCallback = *const fn (*anyopaque) callconv(.C) void;

export fn linenoiseSetCompletionCallback(fun: linenoiseCompletionCallback) void {
    c_completion_callback = fun;
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.completions_callback = completionsCallback;
}

export fn linenoiseSetHintsCallback(fun: linenoiseHintsCallback) void {
    c_hints_callback = fun;
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.hints_callback = hintsCallback;
}

export fn linenoiseSetFreeHintsCallback(fun: linenoiseFreeHintsCallback) void {
    c_free_hints_callback = fun;
}

export fn linenoiseAddCompletion(lc: *LinenoiseCompletions, str: [*:0]const u8) void {
    const dupe = global_allocator.dupeZ(u8, mem.span(str)) catch return;

    var completions: std.ArrayList([*:0]u8) = undefined;
    if (lc.cvec) |raw_completions| {
        completions = std.ArrayList([*:0]u8).fromOwnedSlice(global_allocator, raw_completions[0..lc.len]);
    } else {
        completions = std.ArrayList([*:0]u8).init(global_allocator);
    }

    completions.append(dupe) catch return;
    const slice = completions.toOwnedSlice() catch return;
    lc.cvec = slice.ptr;
    lc.len += 1;
}

fn completionsCallback(allocator: Allocator, line: []const u8) ![]const []const u8 {
    if (c_completion_callback) |cCompletionCallback| {
        const lineZ = try allocator.dupeZ(u8, line);
        defer allocator.free(lineZ);

        var lc = LinenoiseCompletions{
            .len = 0,
            .cvec = null,
        };
        cCompletionCallback(lineZ, &lc);

        if (lc.cvec) |raw_completions| {
            defer lc.free();

            const completions = try allocator.alloc([]const u8, lc.len);
            for (completions, 0..) |*x, i| {
                x.* = try allocator.dupe(u8, mem.span(raw_completions[i]));
            }

            return completions;
        }
    }

    return &[_][]const u8{};
}

fn hintsCallback(allocator: Allocator, line: []const u8) !?[]const u8 {
    if (c_hints_callback) |cHintsCallback| {
        const lineZ = try allocator.dupeZ(u8, line);
        defer allocator.free(lineZ);

        var color: c_int = -1;
        var bold: c_int = 0;
        const maybe_hint = cHintsCallback(lineZ, &color, &bold);
        if (maybe_hint) |hintZ| {
            defer {
                if (c_free_hints_callback) |cFreeHintsCallback| {
                    cFreeHintsCallback(hintZ);
                }
            }

            const hint = mem.span(hintZ);
            if (bold == 1 and color == -1) {
                color = 37;
            }

            return try fmt.allocPrint(allocator, "\x1B[{};{};49m{s}\x1B[0m", .{
                bold,
                color,
                hint,
            });
        }
    }

    return null;
}

export fn linenoise(prompt: [*:0]const u8) ?[*:0]u8 {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    const result = global_linenoise.?.linenoise(mem.span(prompt)) catch return null;
    if (result) |line| {
        defer global_allocator.free(line);
        return global_allocator.dupeZ(u8, line) catch return null;
    } else return null;
}

export fn linenoiseFree(ptr: *anyopaque) void {
    global_allocator.free(mem.span(@as([*:0]const u8, @ptrCast(ptr))));
}

export fn linenoiseHistoryAdd(line: [*:0]const u8) c_int {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.history.add(mem.span(line)) catch return -1;
    return 0;
}

export fn linenoiseHistorySetMaxLen(len: c_int) c_int {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.history.setMaxLen(@intCast(len)) catch return -1;
    return 0;
}

export fn linenoiseHistorySave(filename: [*:0]const u8) c_int {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.history.save(mem.span(filename)) catch return -1;
    return 0;
}

export fn linenoiseHistoryLoad(filename: [*:0]const u8) c_int {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.history.load(mem.span(filename)) catch return -1;
    return 0;
}

export fn linenoiseClearScreen() void {
    term.clearScreen() catch return;
}

export fn linenoiseSetMultiLine(ml: c_int) void {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.multiline_mode = ml != 0;
}

/// Not implemented in linenoize
export fn linenoisePrintKeyCodes() void {}

export fn linenoiseMaskModeEnable() void {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.mask_mode = true;
}

export fn linenoiseMaskModeDisable() void {
    if (global_linenoise == null) global_linenoise = Linenoise.init(global_allocator);
    global_linenoise.?.mask_mode = false;
}
