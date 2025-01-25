const Event = @import("event.zig").Event;
const RtAudio = @import("rtaudio").RtAudio;
const RtMidi = @import("rtmidi").RtMidi;
const lib = @import("lib");

const std = @import("std");
const vaxis = @import("vaxis");

/// This will reset the terminal if panics occur.
pub const panic_handler = vaxis.panic_handler;

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

pub fn init(allocator: std.mem.Allocator) !Self {
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
}

fn midiCallback(loop: *vaxis.Loop(Event), event: RtMidi.Event) void {
    loop.postEvent(.{ .midi = event });
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
    self.rtaudio.start() catch {
        @panic("need audio for this utility, can't start RtAudio");
    };
    defer self.rtaudio.stop();

    while (!self.should_quit) {
        loop.pollEvent();
        while (loop.tryEvent()) |event| {
            try self.update(event);
        }

        self.draw();

        var buffered = self.tty.bufferedWriter();
        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
}

pub fn update(self: *Self, event: Event) !void {
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
                self.writeLog("note on {d}\n", .{note_on.pitch});
            },
            .note_off => |note_off| {
                self.writeLog("note off {d}\n", .{note_off.pitch});
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
