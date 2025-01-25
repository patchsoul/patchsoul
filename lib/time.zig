const common = @import("common.zig");

const std = @import("std");
const time = std.time;

var start_time_ns: i128 = 0;
var has_reset: bool = false;

inline fn resetWith(ns: i128) void {
    has_reset = true;
    start_time_ns = ns;
}

pub fn reset() void {
    resetWith(time.nanoTimestamp());
}

/// Time since the program started, dependent upon hardware,
/// not necessarily better than 100ns resolution.
pub fn now(units: Units) i64 {
    const current_time_ns = time.nanoTimestamp();
    if (!has_reset) {
        resetWith(current_time_ns);
    }
    return units.from_ns(@intCast(current_time_ns - start_time_ns));
}

/// Note that durations of nanoseconds may not followed accurately.
pub fn sleep(duration: Duration) void {
    std.time.sleep(duration.to_ns());
}

pub const Units = enum {
    s,
    ms,
    us,
    ns,

    pub fn from_ns(units: Units, ns: i64) i64 {
        return switch (units) {
            .s => @divFloor(ns, 1_000_000_000),
            .ms => @divFloor(ns, 1_000_000),
            .us => @divFloor(ns, 1_000),
            .ns => ns,
        };
    }
};

pub const Duration = union(Units) {
    s: u33,
    ms: u43,
    us: u53,
    ns: u63,

    pub fn to_ns(self: Duration) u63 {
        return switch (self) {
            .s => |s| @as(u63, 1_000_000_000) * s,
            .ms => |ms| @as(u63, 1_000_000) * ms,
            .us => |us| @as(u63, 1_000) * us,
            .ns => |ns| ns,
        };
    }
};

test "unit conversions work rounding down" {
    try std.testing.expectEqual(-9, Units.s.from_ns(-8_123_456_789));
    try std.testing.expectEqual(5, Units.s.from_ns(5_000_000_000));
    try std.testing.expectEqual(15, Units.s.from_ns(15_987_654_321));
    try std.testing.expectEqual(-7, Units.ms.from_ns(-6_123_456));
    try std.testing.expectEqual(6, Units.ms.from_ns(6_888_888));
    try std.testing.expectEqual(678, Units.us.from_ns(678_901));
    try std.testing.expectEqual(-601, Units.us.from_ns(-600_001));
    try std.testing.expectEqual(-999, Units.ns.from_ns(-999));
    try std.testing.expectEqual(1_234, Units.ns.from_ns(1_234));
}

test "duration conversions work" {
    try std.testing.expectEqual(999_000_000_000, (Duration{ .s = 999 }).to_ns());
    try std.testing.expectEqual(1_234_000_000, (Duration{ .ms = 1_234 }).to_ns());
    try std.testing.expectEqual(5_678_000, (Duration{ .us = 5_678 }).to_ns());
    try std.testing.expectEqual(999, (Duration{ .ns = 999 }).to_ns());
}

test "now works with sleep in ms" {
    const start_us = now(.us);
    sleep(.{ .ms = 5 });
    const delta_us = now(.us) - start_us;
    try std.testing.expect(delta_us > 4_500 and delta_us < 5_500);
}

test "now works with sleep in us" {
    const start_us = now(.us);
    sleep(.{ .us = 600 });
    const delta_us = now(.us) - start_us;
    try std.testing.expect(delta_us > 500 and delta_us < 700);
}

test "now works with sleep in ns" {
    const start_ns = now(.ns);
    // We don't have huge resolution for sleep with ns, so make it big.
    sleep(.{ .ns = 200_000 });
    const delta_ns = now(.ns) - start_ns;
    try std.testing.expect(delta_ns > 100_000 and delta_ns < 300_000);
}
