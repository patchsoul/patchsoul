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

/// Time since the program started, dependent upon hardware
pub fn now(units: Units) i64 {
    const current_time_ns = time.nanoTimestamp();
    if (!has_reset) {
        resetWith(current_time_ns);
    }
    const ns: i64 = @intCast(current_time_ns - start_time_ns);
    return switch (units) {
        .ms => @divFloor(ns, 1_000_000),
        .us => @divFloor(ns, 1_000),
        .ns => ns,
    };
}

pub const Units = enum {
    ms,
    us,
    ns,
};

/// Note that durations of nanoseconds may not be super consistent.
pub fn sleep(duration: Duration) void {
    std.time.sleep(duration.to_ns());
}

pub const Duration = union(Units) {
    ms: u43,
    us: u53,
    ns: u63,

    pub fn to_ns(self: Duration) u63 {
        return switch (self) {
            .ms => |ms| @as(u63, 1_000_000) * ms,
            .us => |us| @as(u63, 1_000) * us,
            .ns => |ns| ns,
        };
    }
};
