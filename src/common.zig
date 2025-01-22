const vaxis = @import("vaxis");
const rtmidi = @import("rtmidi");

pub const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    /// Window resize, also sent when loop begins.
    winsize: vaxis.Winsize,
    midi_event: rtmidi.MidiEvent,
};
