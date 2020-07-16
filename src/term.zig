const std = @import("std");
const Allocator = std.mem.Allocator;
const expectEqualSlices = std.testing.expectEqualSlices;

const wcwidth = @import("wcwidth/src/main.zig").wcwidth;

pub fn width(s: []const u8) usize {
    var result: usize = 0;

    var escape_seq = false;
    const view = std.unicode.Utf8View.init(s) catch return 0;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |codepoint| {
        if (escape_seq) {
            if (codepoint == 'm') {
                escape_seq = false;
            }
        } else {
            if (codepoint == '\x1b') {
                escape_seq = true;
            } else {
                const wcw = wcwidth(codepoint);
                if (wcw < 0) return 0;
                result += @intCast(usize, wcw);
            }
        }
    }

    return result;
}

pub fn toUtf8(allocator: *Allocator, s: []const u21) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    var buf: [4]u8 = undefined;

    for (s) |c| {
        const amt = try std.unicode.utf8Encode(c, &buf);
        try result.appendSlice(buf[0..amt]);
    }

    return result.toOwnedSlice();
}

test "toUtf8" {
    const unicode = [_]u21{ 'a', 'b', 'ü' };
    const utf8 = "abü";

    const allocator = std.testing.allocator;

    const converted = try toUtf8(allocator, &unicode);
    defer allocator.free(converted);

    expectEqualSlices(u8, utf8, converted);
}

pub fn fromUtf8(allocator: *Allocator, s: []const u8) ![]const u21 {
    var result = std.ArrayList(u21).init(allocator);

    var i: usize = 0;
    while (i < s.len) {
        const utf8_len = try std.unicode.utf8CodepointSequenceLength(s[i]);
        try result.append(try std.unicode.utf8Decode(s[i .. i + utf8_len]));

        i += utf8_len;
    }

    return result.toOwnedSlice();
}

test "fromUtf8" {
    const unicode = [_]u21{ 'a', 'b', 'ü' };
    const utf8 = "abü";

    const allocator = std.testing.allocator;

    const converted = try fromUtf8(allocator, utf8);
    defer allocator.free(converted);

    expectEqualSlices(u21, &unicode, converted);
}
