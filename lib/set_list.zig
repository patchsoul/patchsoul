const max_size_list = @import("max_size_list.zig");

const std = @import("std");

const Mask128 = @import("mask.zig").Mask128;
const List128 = max_size_list.MaxSizeList(128, u8);

pub const SetList128 = struct {
    mask128: Mask128 = Mask128{},
    list128: List128 = List128{},

    /// Returns true if the value was added to the SetList.
    /// Returns false if the value was already there.
    pub fn add(self: *Self, value: u7) bool {
        if (self.mask128.get(value)) {
            return false;
        }
        self.mask128.setOn(value);
        self.list128.append(value) catch unreachable;
        return true;
    }

    // TODO: this is O(N); we could technically get faster removals
    // if we made this a "linked list" with a preset 128 values,
    // where the linkages determine what is next/previous in the list
    // and set-behavior is based on whether the value is present there.
    // (we'd lose O(1) random access to the list, but that's not important.)
    // however, the current approach is probably better for the cache,
    // since we normally don't expect list128 to be highly populated.
    /// Returns true if the value was present.
    pub fn remove(self: *Self, value: u7) bool {
        if (!self.mask128.get(value)) {
            return false;
        }
        self.mask128.setOff(value);
        if (!self.list128.removeValue(value)) unreachable;
        return true;
    }

    pub fn pop(self: *Self) ?u7 {
        const result = self.list128.pop() orelse return null;
        self.mask128.setOff(result);
        return @intCast(result);
    }

    pub fn clear(self: *Self) void {
        self.mask128.sixty_fours[0] = 0;
        self.mask128.sixty_fours[1] = 0;
        self.list128.clear();
    }

    pub fn count(self: *const Self) usize {
        return self.list128.count();
    }

    const Self = @This();
    const one: u64 = 1;
};

test "can remove values" {
    var set_list = SetList128{};
    for (0..5) |i| {
        try std.testing.expect(set_list.add(@intCast(i)));
        try std.testing.expect(set_list.add(@intCast(127 - i)));
    }
    try set_list.list128.expectEquals(&[_]u8{ 0, 127, 1, 126, 2, 125, 3, 124, 4, 123 });
    try std.testing.expectEqual(10, set_list.count());

    try std.testing.expect(set_list.remove(3));
    try set_list.list128.expectEquals(&[_]u8{ 0, 127, 1, 126, 2, 125, 124, 4, 123 });
    try std.testing.expectEqual(9, set_list.count());

    try std.testing.expect(set_list.remove(0));
    try set_list.list128.expectEquals(&[_]u8{ 127, 1, 126, 2, 125, 124, 4, 123 });
    try std.testing.expectEqual(8, set_list.count());

    try std.testing.expect(set_list.remove(123));
    try set_list.list128.expectEquals(&[_]u8{ 127, 1, 126, 2, 125, 124, 4 });
    try std.testing.expectEqual(7, set_list.count());
}

test "can add all 128 values" {
    var set_list = SetList128{};
    for (0..128) |i| {
        // Make the order slightly interesting:
        const value: u7 = @intCast(127 - i);
        try std.testing.expect(set_list.add(value));
    }
    try std.testing.expectEqual(std.math.maxInt(u64), set_list.mask128.sixty_fours[0]);
    try std.testing.expectEqual(std.math.maxInt(u64), set_list.mask128.sixty_fours[1]);
    try std.testing.expectEqual(128, set_list.count());

    // Trying to add everyone again fails.
    for (0..128) |i| {
        try std.testing.expect(set_list.add(@intCast(i)) == false);
    }
    try std.testing.expectEqual(128, set_list.count());
}

test "add updates mask and list" {
    var set_list = SetList128{};
    try std.testing.expect(set_list.add(123));

    try std.testing.expectEqual(0, set_list.mask128.sixty_fours[0]);
    try std.testing.expectEqual(SetList128.one << (123 - 64), set_list.mask128.sixty_fours[1]);
    try set_list.list128.expectEquals(&[_]u8{123});
    try std.testing.expectEqual(1, set_list.count());

    try std.testing.expect(set_list.add(62));

    try std.testing.expectEqual(SetList128.one << (62), set_list.mask128.sixty_fours[0]);
    try std.testing.expectEqual(SetList128.one << (123 - 64), set_list.mask128.sixty_fours[1]);
    try set_list.list128.expectEquals(&[_]u8{ 123, 62 });
    try std.testing.expectEqual(2, set_list.count());

    try std.testing.expect(set_list.add(62) == false);
    try set_list.list128.expectEquals(&[_]u8{ 123, 62 });

    try std.testing.expect(set_list.add(123) == false);
    try set_list.list128.expectEquals(&[_]u8{ 123, 62 });
}
