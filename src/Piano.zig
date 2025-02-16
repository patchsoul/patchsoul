const Harmony = @import("Harmony.zig");
const vaxis = @import("vaxis");

const Piano = @This();
const Self = @This();

/// Pitch to start showing on the left side of the screen
pitch_offset: u8 = 0,
needs_full_redraw: bool = false,

pub fn update(self: *Self, harmony: *Harmony, event: Event) !void {
    // TODO: when a mouse clicks a note, play the note on the synthesizer
    _ = synthesizer;
    switch (event) {
        .redraw_request => {
            self.needs_full_redraw = true;
        },
        .midi => |midi| switch (midi) {
            // TODO:
        },
    }
}

// TODO: add a `focused` argument
pub fn draw(self: *Self, window: vaxis.Window) !void {
    // TODO
}
