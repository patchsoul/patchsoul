const Shtick = @import("shtick.zig").Shtick;
const owned_list = @import("owned_list.zig");

const std = @import("std");

const OwnedShticks = owned_list.OwnedList(Shtick);

pub const TestWriterData = struct {
    buffer: [Shtick.max_count]u8 = undefined,
    current_buffer_offset: usize = 0,
    lines: OwnedShticks = OwnedShticks.init(),
};

pub const TestWriter = struct {
    data: *TestWriterData,

    pub const Error = error{
        out_of_memory,
        line_too_long,
    };

    pub fn init(my_data: *TestWriterData) TestWriter {
        return TestWriter{ .data = my_data };
    }

    pub fn pullLines(self: *Self) OwnedShticks {
        const new_lines = OwnedShticks.init();
        const old_lines = self.data.lines;
        self.data.lines = new_lines;
        return old_lines;
    }

    pub fn print(self: Self, comptime format: []const u8, args: anytype) !void {
        return std.fmt.format(self, format, args);
    }

    pub fn writeAll(self: Self, chars: []const u8) !void {
        for (chars) |char| {
            if (char == '\n') {
                const line = try self.debufferLine();
                self.data.lines.append(line) catch return Error.out_of_memory;
            } else if (self.data.current_buffer_offset < self.data.buffer.len) {
                self.data.buffer[self.data.current_buffer_offset] = char;
                self.data.current_buffer_offset += 1;
            } else {
                return Error.line_too_long;
            }
        }
    }

    pub fn writeBytesNTimes(self: Self, bytes: []const u8, n: usize) !void {
        for (0..n) |i| {
            _ = i;
            try self.writeAll(bytes);
        }
    }

    fn debufferLine(self: Self) !Shtick {
        const line = Shtick.init(self.data.buffer[0..self.data.current_buffer_offset]) catch return Error.out_of_memory;
        self.data.current_buffer_offset = 0;
        return line;
    }

    const Self = @This();
};

test "can get lines printed to stdout" {
    const common = @import("common.zig");

    try common.stdout.print("oh {s}, ", .{"yes"});
    try common.stdout.print("oh {s}\n", .{"no"});
    try common.stdout.print("{d} in\none print\n", .{2});

    var lines = common.stdout.pullLines();
    defer lines.deinit();
    try lines.expectEqualsSlice(&[_]Shtick{
        Shtick.unallocated("oh yes, oh no"),
        Shtick.unallocated("2 in"),
        Shtick.unallocated("one print"),
    });
}

test "can get lines printed to stderr" {
    const common = @import("common.zig");

    try common.stderr.print("one\ntwo\n{s}\n", .{"three"});
    try common.stderr.print("fo..", .{});
    try common.stderr.print("u...", .{});
    try common.stderr.print("r..\n", .{});

    var lines = common.stderr.pullLines();
    defer lines.deinit();
    try lines.expectEqualsSlice(&[_]Shtick{
        Shtick.unallocated("one"),
        Shtick.unallocated("two"),
        Shtick.unallocated("three"),
        Shtick.unallocated("fo..u...r.."),
    });
}

test "can get lines printed to stdout and stderr" {
    const common = @import("common.zig");

    try common.stdout.print("o{s}t", .{"u"});
    try common.stderr.print("E{s}R", .{"R"});
    try common.stdout.print("WARD\n", .{});
    try common.stderr.print("or\n", .{});

    var lines = common.stderr.pullLines();
    try lines.expectEqualsSlice(&[_]Shtick{
        Shtick.unallocated("ERRor"),
    });
    lines.deinit();

    lines = common.stdout.pullLines();
    try lines.expectEqualsSlice(&[_]Shtick{
        Shtick.unallocated("outWARD"),
    });
    lines.deinit();
}
