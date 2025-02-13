const common = @import("common.zig");

const std = @import("std");

pub const File = struct {
    // TODO: add Shtick list for an in-memory file.

    const Self = @This();
};

pub const Helper = struct {
    pub fn readBytes(N: comptime_int, reader: anytype) ![N]u8 {
        var data: [N]u8 = undefined;
        _ = try reader.readNoEof(&data);
        return data;
    }

    pub fn readLittleEndian(comptime T: type, reader: anytype) !T {
        return if (common.isLittleEndian())
            readNoSwap(T, reader)
        else
            readWithSwap(T, reader);
    }

    pub fn readBigEndian(comptime T: type, reader: anytype) !T {
        return if (common.isLittleEndian())
            readWithSwap(T, reader)
        else
            readNoSwap(T, reader);
    }

    inline fn readNoSwap(comptime T: type, reader: anytype) !T {
        const data = try readBytes(@sizeOf(T), reader);
        return @bitCast(data);
    }

    inline fn readWithSwap(comptime T: type, reader: anytype) !T {
        return @byteSwap(try readNoSwap(T, reader));
    }
};
