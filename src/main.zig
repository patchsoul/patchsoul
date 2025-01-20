const std = @import("std");
const Wim = @import("Wim.zig");

pub const panic = Wim.panic_handler;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) {
            std.log.err("Memory leak!", .{});
        }
    }
    const allocator = gpa.allocator();

    // Initialize our application
    var wim = try Wim.init(allocator);
    defer wim.deinit();

    // Run the application
    try wim.run();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
