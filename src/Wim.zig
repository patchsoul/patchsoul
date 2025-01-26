const Event = @import("event.zig").Event;
const lib = @import("lib");
const RtAudio = @import("rtaudio").RtAudio;
const RtMidi = @import("rtmidi").RtMidi;
const vaxis = @import("vaxis");
const zsynth = @import("ziggysynth");

const std = @import("std");
const math = std.math;

/// This will reset the terminal if panics occur.
pub const panic_handler = vaxis.panic_handler;

const Sample = RtAudio.Sample;
const Wim = @This();

allocator: std.mem.Allocator,
should_quit: bool = false,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
rtaudio: RtAudio,
rtmidi: ?RtMidi,
/// Mouse event to be handled during draw cycle.
mouse: ?vaxis.Mouse = null,
midi_connected: bool = false,
last_port_count: usize = 0,
port_update_message: lib.Shtick,
needs_full_redraw: bool = true,
log_file: ?std.fs.File,
sound_font: zsynth.SoundFont,

pub fn init(allocator: std.mem.Allocator) !Self {
    // TODO: make this a command-line option, defaulting to SoundFont.sf2 if nothing else is passed in.
    var sf2 = std.fs.cwd().openFile("SoundFont.sf2", .{}) catch {
        @panic("Copy a sound font like TimGM6mb.sf2 or FluidR3_GM.sf2 into the patchsoul directory as SoundFont.sf2");
    };
    return .{
        .allocator = allocator,
        .tty = try vaxis.Tty.init(),
        .vx = try vaxis.init(allocator, .{}),
        .rtaudio = RtAudio.init(),
        .rtmidi = RtMidi.init() catch null,
        .port_update_message = lib.Shtick.withCapacity(100) catch {
            @panic("should have enough capacity");
        },
        .log_file = std.fs.cwd().createFile("wim.out", .{}) catch null,
        .sound_font = try zsynth.SoundFont.init(lib.common.allocator, sf2.reader()),
    };
}

pub fn deinit(self: *Self) void {
    self.sound_font.deinit();
    self.vx.deinit(self.allocator, self.ttyWriter());
    self.tty.deinit();
    if (self.rtmidi) |*rtmidi| {
        rtmidi.deinit();
    }
    self.rtaudio.deinit();
    if (self.log_file) |file| {
        file.close();
        self.log_file = null;
    }
}

fn midiCallback(loop: *vaxis.Loop(Event), event: RtMidi.Event) void {
    loop.postEvent(.{ .midi = event });
}

fn sample_ziggy(data: *anyopaque, samples: []Sample) void {
    const synthesizer: *zsynth.Synthesizer = @alignCast(@ptrCast(data));
    var buffer_left: [512]f32 = undefined;
    var buffer_right: [512]f32 = undefined;
    std.debug.assert(samples.len <= 512);
    synthesizer.render(buffer_left[0..samples.len], buffer_right[0..samples.len]);
    var i: usize = 0;
    for (samples) |*sample| {
        sample.left = buffer_left[i];
        sample.right = buffer_right[i];
        i += 1;
    }
}

pub fn run(self: *Self) !void {
    var loop: vaxis.Loop(Event) = .{
        .tty = &self.tty,
        .vaxis = &self.vx,
    };
    try loop.init();
    try loop.start();
    try self.vx.enterAltScreen(self.ttyWriter());
    try self.vx.queryTerminal(self.ttyWriter(), 1 * std.time.ns_per_s);
    try self.vx.setMouseMode(self.ttyWriter(), true);
    if (self.rtmidi) |*rtmidi| {
        rtmidi.start(.{ .ms = 1 }, &loop, midiCallback);
    }
    var settings = zsynth.SynthesizerSettings.init(RtAudio.frequency_hz);
    var synthesizer = try zsynth.Synthesizer.init(lib.common.allocator, &self.sound_font, &settings);
    defer synthesizer.deinit();
    self.rtaudio.callable = .{
        .data = &synthesizer,
        .callback = sample_ziggy,
    };
    self.rtaudio.start() catch {
        @panic("can't start RtAudio, but this is required");
    };
    defer self.rtaudio.stop();

    while (!self.should_quit) {
        loop.pollEvent();
        while (loop.tryEvent()) |event| {
            try self.update(&synthesizer, event);
        }

        self.draw();

        var buffered = self.tty.bufferedWriter();
        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
}

pub fn update(self: *Self, synthesizer: *zsynth.Synthesizer, event: Event) !void {
    switch (event) {
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true }))
                self.should_quit = true;
        },
        .mouse => |mouse| self.mouse = mouse,
        .midi => |midi| switch (midi) {
            .ports_updated => if (self.rtmidi) |rtmidi| {
                const new_port_count = rtmidi.portCount();
                defer self.last_port_count = new_port_count;
                self.midi_connected = new_port_count > 0;
                if (new_port_count > self.last_port_count) {
                    self.port_update_message.copyFromSlice("connected:  ") catch {};
                    const port_name = rtmidi.ports.items()[new_port_count - 1].name;
                    const max_len = @min(
                        self.port_update_message.capacity() - self.port_update_message.count(),
                        port_name.count(),
                    );
                    self.port_update_message.addSlice(port_name.slice()[0..max_len]) catch {};
                } else if (new_port_count < self.last_port_count) {
                    self.port_update_message.copyFromSlice("disconnected a midi device") catch {};
                }
            },
            .note_on => |note_on| {
                const normalized_velocity: u8 = 64 + note_on.velocity / 2;
                synthesizer.noteOn(0, note_on.pitch, normalized_velocity);
                // TODO: whether recording or not, put into a "master midi file" that you can open read-only
                // and copy from.  master midi file "sleeps" if there's no input for a while.
            },
            .note_off => |note_off| {
                // we ignore note_off velocity in ziggysynth.
                synthesizer.noteOff(0, note_off.pitch);
                // TODO: add to master midi file
            },
        },
        .winsize => |ws| {
            try self.vx.resize(self.allocator, self.ttyWriter(), ws);
            self.needs_full_redraw = true;
        },
        else => {},
    }
}
pub fn draw(self: *Self) void {
    const window = self.vx.window();

    if (self.needs_full_redraw) {
        window.clear();
    }
    self.vx.setMouseShape(.default);

    if (self.midi_connected) {
        try self.drawMidiConnected(window);
    }
    try self.drawPortConnected(window);
}

fn drawMidiConnected(self: *Self, window: vaxis.Window) !void {
    const msg = "midi ports connected";

    const child = window.child(.{
        .x_off = (window.width - msg.len) / 2,
        .y_off = window.height / 2 - 2,
        .width = .{ .limit = msg.len },
        .height = .{ .limit = 1 },
    });

    // Mouse events are easier to handle in the draw cycle, because we can check
    // if the event occurred in the target window.
    const style: vaxis.Style = if (child.hasMouse(self.mouse)) |_| blk: {
        // We handled the mouse event, so set it to null
        self.mouse = null;
        self.vx.setMouseShape(.pointer);
        break :blk .{ .reverse = true };
    } else .{};

    _ = try child.printSegment(.{ .text = msg, .style = style }, .{});
}

fn drawPortConnected(self: *Self, window: vaxis.Window) !void {
    const msg = self.port_update_message.slice();

    const child = window.child(.{
        .x_off = 0,
        .y_off = window.height - 2,
        .width = .{ .limit = self.port_update_message.capacity() },
        .height = .{ .limit = 1 },
    });

    _ = try child.printSegment(.{ .text = msg }, .{});
}

fn ttyWriter(self: *Self) std.io.AnyWriter {
    return self.tty.anyWriter();
}

inline fn writeLog(self: *Self, comptime format: []const u8, data: anytype) void {
    if (self.log_file) |file| {
        std.fmt.format(file.writer(), format, data) catch {};
    }
}

const Self = @This();
