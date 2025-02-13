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
        const t = try readPrimitive(T, reader);
        return if (common.isLittleEndian()) t else @byteSwap(t);
    }

    pub fn readBigEndian(comptime T: type, reader: anytype) !T {
        const t = try readPrimitive(T, reader);
        return if (common.isLittleEndian()) @byteSwap(t) else t;
    }

    inline fn readPrimitive(comptime T: type, reader: anytype) !T {
        const data = try readBytes(@sizeOf(T), reader);
        return @bitCast(data);
    }

    pub fn writeLittleEndian(writer: anytype, t: anytype) !void {
        const to_write = if (common.isLittleEndian()) t else @byteSwap(t);
        try writePrimitive(writer, to_write);
    }

    pub fn writeBigEndian(writer: anytype, t: anytype) !void {
        const to_write = if (common.isLittleEndian()) @byteSwap(t) else t;
        try writePrimitive(writer, to_write);
    }

    inline fn writePrimitive(writer: anytype, t: anytype) !void {
        const data: [@sizeOf(@TypeOf(t))]u8 = @bitCast(t);
        try writer.writeAll(&data);
    }
};

fn ByteCountReader(comptime T: type) type {
    return struct {
        reader: T,
        count: usize = 0,

        pub fn init(reader: T) Self {
            return Self { .reader = reader };
        }

        pub fn readNoEof(self: *Self, buf: []u8) !void {
            try self.reader.readNoEof(buf);
            self.count += buf.len;
        }

        pub fn skipBytes(self: *Self, byte_count: u64, options: anytype) !void {
            try self.reader.skipBytes(byte_count, options);
            self.count += @intCast(byte_count);
        }

        const Self = @This();
    }
}
