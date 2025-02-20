const context = @import("context.zig");
const Harmony = @import("Harmony.zig");
const TrackEditor = @import("TrackEditor.zig");
const Event = @import("event.zig").Event;
const lib = @import("lib");
const RtAudio = @import("rtaudio").RtAudio;
const RtMidi = @import("rtmidi").RtMidi;
const vaxis = @import("vaxis");
const zsynth = @import("ziggysynth");

const std = @import("std");
const math = std.math;

// TODO: work columns 1-9 + 0.
// each work column is a vertical sliver of screen real estate, about 120 columns each.
// if your screen is wide enough for 2 columns, it will put two work columns on screen.
// e.g., if navigating to work column 1, it will put work column 1 on the left and 2 on the right.
// it uses wrap around, so navigating to 9 will give 9 on the left and 0 on the right.
// if your screen is wide enough for 3 columns, we'll show 3 work columns, etc.
// if your screen isn't wide enough for 2, we'll always show 1, regardless of width.
// doing it this way means that we don't need to worry about shrinking our terminal (e.g.,
// to go side-by-side with a browser or other terminal) and messing up the workspace.
// TODO: every open file will get put into a canonical form path in an in-memory `Files` struct.
// `Files` will eventually watch OS files for changes and trigger file-change events.

/// This will reset the terminal if panics occur.
pub const panic_handler = vaxis.panic_handler;

const Sample = RtAudio.Sample;
const Wim = @This();

allocator: std.mem.Allocator,
should_quit: bool = false,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
harmony: Harmony,
rtaudio: RtAudio,
rtmidi: ?RtMidi,
midi_connected: bool = false,
last_port_count: usize = 0,
port_update_message: lib.Shtick,
log_file: ?std.fs.File,
track_editor: TrackEditor,
messages: context.Messages = .{},

pub fn init(allocator: std.mem.Allocator) !Self {
    // TODO: make this a command-line option, defaulting to SoundFont.sf2 if nothing else is passed in.
    const sound_font_path = lib.Shtick.unallocated("SoundFont.sf2");
    return .{
        .allocator = allocator,
        .tty = try vaxis.Tty.init(),
        .vx = try vaxis.init(allocator, .{}),
        .harmony = Harmony.init(sound_font_path) catch {
            @panic("Copy a sound font like TimGM6mb.sf2 or FluidR3_GM.sf2 into the patchsoul directory as SoundFont.sf2");
        },
        .rtaudio = RtAudio.init(),
        .rtmidi = RtMidi.init() catch null,
        .port_update_message = lib.Shtick.withCapacity(100) catch {
            @panic("should have enough capacity");
        },
        .log_file = std.fs.cwd().createFile("wim.out", .{}) catch null,
        .track_editor = TrackEditor.init(),
    };
}

pub fn deinit(self: *Self) void {
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
    self.harmony.deinit();
    self.track_editor.deinit();
}

fn midiCallback(loop: *vaxis.Loop(Event), event: RtMidi.Event) void {
    loop.postEvent(.{ .midi = event });
}

fn sampleZiggy(data: *anyopaque, samples: []Sample) void {
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
    self.rtaudio.callable = .{
        .data = &self.harmony.synthesizer,
        .callback = sampleZiggy,
    };
    self.rtaudio.start() catch {
        @panic("can't start RtAudio, but this is required");
    };
    defer self.rtaudio.stop();

    while (!self.should_quit) {
        loop.pollEvent();
        var windowless = context.Windowless{ .harmony = &self.harmony, .messages = &self.messages };
        while (loop.tryEvent()) |event| {
            try self.update(&windowless, event);
        }

        var windowed = windowless.windowed(&self.vx);
        self.draw(&windowed);

        var buffered = self.tty.bufferedWriter();
        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
}

pub fn update(self: *Self, ctx: *context.Windowless, event: Event) !void {
    switch (event) {
        .redraw_request => {
            ctx.needs_full_redraw = true;
        },
        .key_press => |key| {
            if (key.matches('q', .{ .ctrl = true }))
                self.should_quit = true;
        },
        .mouse => |mouse| ctx.mouse = mouse,
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
                ctx.harmony.noteOn(note_on.pitch, note_on.velocity);
                try self.track_editor.update(ctx, event);
            },
            .note_off => |note_off| {
                ctx.harmony.noteOff(note_off.pitch, note_off.velocity);
                try self.track_editor.update(ctx, event);
            },
        },
        .winsize => |ws| {
            try self.vx.resize(self.allocator, self.ttyWriter(), ws);
            ctx.needs_full_redraw = true;
        },
        else => {},
    }
}
pub fn draw(self: *Self, ctx: *context.Windowed) void {
    if (ctx.needs_full_redraw) {
        ctx.window.clear();
    }
    self.vx.setMouseShape(.default);

    if (self.midi_connected) {
        try self.drawMidiConnected(ctx);
    }
    try self.drawPortConnected(ctx);

    try ctx.drawChild(&self.track_editor, .{
        .x_off = 0,
        .y_off = 0,
        .width = .{ .limit = @min(128, ctx.window.width) },
        .height = .{ .limit = ctx.window.height - 1 },
    });
}

// TODO: migrate this to a child text container.
fn drawMidiConnected(self: *Self, ctx: *context.Windowed) !void {
    const msg = "midi ports connected";

    const child = ctx.window.child(.{
        .x_off = (ctx.window.width - msg.len) / 2,
        .y_off = ctx.window.height / 2 - 2,
        .width = .{ .limit = msg.len },
        .height = .{ .limit = 1 },
    });

    // Mouse events are easier to handle in the draw cycle, because we can check
    // if the event occurred in the target window.
    const style: vaxis.Style = if (child.hasMouse(ctx.mouse)) |_| blk: {
        // We handled the mouse event, so set it to null
        ctx.mouse = null;
        self.vx.setMouseShape(.pointer);
        break :blk .{ .reverse = true };
    } else .{};

    _ = try child.printSegment(.{ .text = msg, .style = style }, .{});
}

// TODO: migrate this to a child text container.
fn drawPortConnected(self: *Self, ctx: *context.Windowed) !void {
    const msg = self.port_update_message.slice();
    const length = self.port_update_message.capacity();

    const child = ctx.window.child(.{
        .x_off = 0,
        .y_off = ctx.window.height - 1,
        .width = .{ .limit = length },
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

// TODO: show notes like this: https://www.compart.com/en/unicode/block/U+2580

const Self = @This();
