const c = @cImport({
    @cInclude("rtmidi_c.h");
});

pub const RtMidi = struct {
    // Number of ticks to wait before checking for plug/unplugs.
    update_port_wait: u16 = 15,
    update_port_counter: u16 = 0,
    rt_midi_in: c.RtMidiInPtr,

    pub fn init() Self {
        return Self{
            .rt_midi_in = c.rtmidi_in_create(c.RTMIDI_API_UNSPECIFIED, "patchsoul", 128),
        };
    }

    pub fn deinit(self: *Self) void {
        c.rtmidi_in_free(self.rt_midi_in);
    }

    pub fn notify(self: *Self, loop: anytype) void {
        self.update_port_counter += 1;
        if (self.update_port_counter >= self.update_port_wait) {
            self.update_port_counter = 0;
            self.updatePorts(loop);
        }
    }

    pub fn updatePorts(self: *Self, loop: anytype) void {
        _ = self;
        _ = loop;
    }

    const Self = @This();
};
