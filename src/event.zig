const vaxis = @import("vaxis");
const rtmidi = @import("rtmidi");

pub const Key = vaxis.Key;
pub const Mouse = vaxis.Mouse;
pub const Midi = rtmidi.MidiEvent;

pub const Event = union(enum) {
    /// request to fully redraw the screen.
    redraw_request: void,
    key_press: Key,
    key_release: Key,
    mouse: Mouse,
    /// Window resize, also sent when loop begins.
    winsize: vaxis.Winsize,
    midi: Midi,
};
