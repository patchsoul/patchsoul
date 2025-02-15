const lib = @import("lib");
const Shtick = lib.Shtick;

pub const Event = @import("event.zig").Event;
pub const Notification = @import("Notification.zig");
pub const Wim = @import("Wim.zig");

const std = @import("std");

pub const panic = Wim.panic_handler;

pub fn main() !void {
    // Try some junk
    var midi_file = lib.midi.File.init(Shtick.unallocated("flourish.mid"));
    defer midi_file.deinit();
    std.debug.assert(midi_file.header.ticks_per_beat == 384);
    std.debug.assert(midi_file.header.track_count == 16);
    // Don't overwrite flourish.mid!
    midi_file.path = Shtick.unallocated("test.mid");
    try midi_file.write();

    // Initialize our application
    var wim = try Wim.init(lib.common.allocator);
    defer cleanUp(&wim);
    errdefer cleanUp(&wim);

    // Run the application
    try wim.run();
}

fn cleanUp(wim: *Wim) void {
    wim.deinit();
    lib.common.cleanUp();
}

test "other dependencies (import using pub)" {
    std.testing.refAllDecls(@This());
}
