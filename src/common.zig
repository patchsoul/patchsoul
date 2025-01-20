const vaxis = @import("vaxis");

pub const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    /// Window resize, also sent when loop begins.
    winsize: vaxis.Winsize,
    midi_connect: i32,
    midi_disconnect: i32,
};
