const lib = @import("lib");
const Shtick = lib.Shtick;
const time = lib.time;

const std = @import("std");

const Notification = @This();
const Self = @This();

/// Avoid messing with `message.capacity` so that it can be used
/// to determine the max length of the notification.
message: Shtick,
invalid_after_ns: i64,

/// Values less than Shtick.max_unallocated_count will be ignored.
pub fn init(max_count: u9) Self {
    return Self{
        .message = Shtick.withCapacity(max_count) catch {
            @panic("not enough memory for a Notification");
        },
        .invalid_after_ns = -123_456,
    };
}

pub fn deinit(self: *Self) void {
    self.message.deinit();
}

pub fn maxCount(self: *const Self) usize {
    return self.message.capacity();
}

pub fn showFor(self: *Self, duration: time.Duration) void {
    self.invalid_after_ns = time.now(.ns) + duration.to_ns();
}

pub fn shouldShow(self: *const Self) bool {
    return time.now(.ns) < self.invalid_after_ns;
}

test "capacity is max count" {
    var notification = Notification.init(123);
    defer notification.deinit();
    try std.testing.expectEqual(123, notification.maxCount());
    try std.testing.expectEqual(123, notification.message.capacity());
}

test "should show for 2 ms works" {
    var notification = Notification.init(14);
    try std.testing.expectEqual(false, notification.shouldShow());
    notification.showFor(.{ .ms = 2 });
    try std.testing.expectEqual(true, notification.shouldShow());

    time.sleep(.{ .us = 1500 });
    try std.testing.expectEqual(true, notification.shouldShow());

    time.sleep(.{ .us = 1000 });
    try std.testing.expectEqual(false, notification.shouldShow());
}

test "should show for 15_000 us works" {
    var notification = Notification.init(14);
    try std.testing.expectEqual(false, notification.shouldShow());
    notification.showFor(.{ .us = 15_000 });
    try std.testing.expectEqual(true, notification.shouldShow());

    time.sleep(.{ .us = 13_000 });
    try std.testing.expectEqual(true, notification.shouldShow());

    time.sleep(.{ .us = 2_500 });
    try std.testing.expectEqual(false, notification.shouldShow());
}
