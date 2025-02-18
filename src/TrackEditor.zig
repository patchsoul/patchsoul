const context = @import("context.zig");
const lib = @import("lib");
const pointer = lib.pointer;
const Piano = @import("Piano.zig");
const Event = context.Event;

const Self = @This();
const TrackEditor = @This();

//track: *lib.midi.Track,
piano: Piano,

//pub fn init(track: pointer.LifetimeBorrow(lib.midi.Track)) Self {
pub fn init() Self {
    return Self{
        // .track = track.pointer,
        .piano = Piano.init(),
    };
}

pub fn deinit(self: *Self) void {
    self.piano.deinit();
}

pub fn update(self: *Self, ctx: *context.Windowless, event: Event) !void {
    _ = ctx;
    switch (event) {
        .midi => |midi| switch (midi) {
            .note_on => |note_on| {
                _ = note_on;
                self.piano.update(midi);
            },
            .note_off => |note_off| {
                _ = note_off;
                self.piano.update(midi);
            },
            else => {},
        },
        else => {},
    }
}

pub fn draw(self: *Self, ctx: *context.Windowed) void {
    if (ctx.window.height > 5) {
        try ctx.drawChild(&self.piano, .{
            .x_off = 0,
            .y_off = ctx.window.height - 3,
            .width = .{ .limit = ctx.window.width },
            .height = .{ .limit = 2 },
        });
    }
}
