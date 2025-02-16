const std = @import("std");

const OneTwoEight = @This();
const Self = @This();

sixty_fours: [2]u64 = .{0} ** 2,
const one: u64 = 1;

pub fn get(self: *const Self, bit: u8) bool {
    return switch (bit / 64) {
        0 => self.indexGet(0, @intCast(bit & 63)),
        1 => self.indexGet(1, @intCast(bit & 63)),
        else => false,
    };
}

pub inline fn set(self: *Self, bit: u7, value: bool) void {
    if (value) {
        self.setOn(bit);
    } else {
        self.setOff(bit);
    }
}

pub fn setOn(self: *Self, bit: u8) void {
    switch (bit / 64) {
        0 => self.indexSetOn(0, @intCast(bit & 63)),
        1 => self.indexSetOn(1, @intCast(bit & 63)),
        else => {},
    }
}

pub fn setOff(self: *Self, bit: u8) void {
    switch (bit / 64) {
        0 => self.indexSetOff(0, @intCast(bit & 63)),
        1 => self.indexSetOff(1, @intCast(bit & 63)),
        else => {},
    }
}

pub inline fn indexGet(self: *const Self, which_64: comptime_int, bit: u6) bool {
    const bit_mask: u64 = one << bit;
    return (self.sixty_fours[which_64] & bit_mask) != 0;
}

pub inline fn indexSetOn(self: *Self, which_64: comptime_int, bit: u6) void {
    const bit_mask: u64 = one << bit;
    self.sixty_fours[which_64] |= bit_mask;
}

pub inline fn indexSetOff(self: *Self, which_64: comptime_int, bit: u6) void {
    const bit_mask: u64 = one << bit;
    self.sixty_fours[which_64] &= ~bit_mask;
}

test "128 setting and getting bits" {
    const full64: u64 = 18446744073709551615; // 2**64 - 1
    const start0: u64 = full64 - (1 << 3); // 2**64 - 1 - 2**3
    const start1: u64 = full64 - (1 << 62); // 2**64 - 1 - 2**62
    var a128 = OneTwoEight{ .sixty_fours = .{ start0, start1 } };

    // Turn on and off:
    try std.testing.expectEqual(false, a128.get(3));
    a128.set(3, true);
    try std.testing.expectEqual(true, a128.get(3));
    try std.testing.expectEqual(full64, a128.sixty_fours[0]);
    a128.set(3, false);
    try std.testing.expectEqual(false, a128.get(3));
    // Doesn't change the other bits:
    try std.testing.expectEqual(start0, a128.sixty_fours[0]);

    // Turn on via `setOn` and off via `setOff`:
    try std.testing.expectEqual(false, a128.get(126));
    a128.setOn(126);
    try std.testing.expectEqual(true, a128.get(126));
    try std.testing.expectEqual(full64, a128.sixty_fours[1]);
    a128.setOff(126);
    try std.testing.expectEqual(false, a128.get(126));
    // Doesn't change the other bits:
    try std.testing.expectEqual(start1, a128.sixty_fours[1]);
}

test "128 default is zero" {
    var a128 = OneTwoEight{};
    for (0..128) |bit| {
        try std.testing.expectEqual(false, a128.get(@intCast(bit)));
    }
}
