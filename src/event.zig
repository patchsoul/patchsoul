const vaxis = @import("vaxis");
const rtmidi = @import("rtmidi");

pub const Event = union(enum) {
    /// request to fully redraw the screen.
    redraw_request: void,
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    /// Window resize, also sent when loop begins.
    winsize: vaxis.Winsize,
    midi: rtmidi.MidiEvent,
};
