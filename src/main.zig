const lib_common = @import("lib").common;
pub const Wim = @import("Wim.zig");
pub const Notification = @import("Notification.zig");

const std = @import("std");

pub const panic = Wim.panic_handler;

pub fn main() !void {
    // Initialize our application
    var wim = try Wim.init(lib_common.allocator);
    defer cleanUp(&wim);
    errdefer cleanUp(&wim);

    // Run the application
    try wim.run();
}

fn cleanUp(wim: *Wim) void {
    wim.deinit();
    lib_common.cleanUp();
}

test "other dependencies (import using pub)" {
    std.testing.refAllDecls(@This());
}
