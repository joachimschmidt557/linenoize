const std = @import("std");
const ArrayList = std.ArrayList;

pub const History = struct {
    hist: ArrayList([]const u8),

    const Self = @This();

    pub fn load(path: []const u8) Self {

    }

    pub fn save(path: []const u8) Self {

    }
};
