const std = @import("std");

pub const File = struct {
    // TODO: add Shtick list for an in-memory file.

    const Self = @This();
};

pub const Reader = struct {
    pub fn readBytes(N: comptime_int, reader: anytype) ![N]u8 {
        var data: [N]u8 = undefined;
        _ = try reader.readNoEof(&data);
        return data;
    }
};
