const c = @cImport({
    @cInclude("rtmidi_c.h");
});

const RtMidi = @This();

// Number of ticks to wait before checking for plug/unplugs.
update_port_wait: u16 = 15,
update_port_counter: u16 = 0,

pub fn notify(self: *RtMidi, loop: anytype) void {
    self.update_port_counter += 1;
    if (self.update_port_counter >= self.update_port_wait) {
        self.update_port_counter = 0;
        self.updatePorts(loop);
    }
}

pub fn updatePorts(self: *RtMidi, loop: anytype) void {
    _ = self;
    _ = loop;
}
