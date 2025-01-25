const common = @import("lib").common;
pub const Event = @import("event.zig").Event;
pub const Notification = @import("Notification.zig");
pub const Wim = @import("Wim.zig");

const std = @import("std");

pub const panic = Wim.panic_handler;

pub fn main() !void {
    // Initialize our application
    var wim = try Wim.init(common.allocator);
    defer cleanUp(&wim);
    errdefer cleanUp(&wim);

    // Run the application
    try wim.run();
}

fn cleanUp(wim: *Wim) void {
    wim.deinit();
    common.cleanUp();
}

test "other dependencies (import using pub)" {
    std.testing.refAllDecls(@This());
}
