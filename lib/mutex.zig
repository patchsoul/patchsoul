const std = @import("std");

pub fn Mutex(comptime T: type) type {
    return struct {
        value: T,
        mutex: std.Thread.Mutex,

        pub fn init(t: T) Self {
            return Self{ .value = t, .mutex = std.Thread.Mutex{} };
        }

        pub inline fn acquire(self: *Self) void {
            self.mutex.lock();
        }

        pub inline fn tryAcquire(self: *Self) bool {
            return self.mutex.tryLock();
        }

        pub inline fn release(self: *Self) void {
            self.mutex.unlock();
        }

        const Self = @This();
    };
}
