const context = @import("context.zig");
const MidiEvent = @import("event.zig").Midi;
const lib = @import("lib");

const Piano = @This();
const Self = @This();

/// Pitch to start showing on the left side of the screen
pitch_offset: u8 = 0,

pub fn update(self: *Self, midi: MidiEvent) !void {
    switch (midi) {
        // TODO:
    }
}

pub fn draw(self: *Self, ctx: *context.Windowed) !void {
    // TODO: when a mouse clicks a note, play the note on the synthesizer
    // TODO
}
