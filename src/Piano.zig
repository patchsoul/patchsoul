const context = @import("context.zig");
const MidiEvent = @import("event.zig").Midi;
const lib = @import("lib");
const common = lib.common;

const Piano = @This();
const Self = @This();

/// Pitch to start showing on the left side of the screen
pitch_offset: u8 = 0,

pub fn init() Self {
    return Self{};
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn update(self: *Self, midi: MidiEvent) !void {
    _ = self;
    _ = midi;
}

pub fn draw(self: *Self, ctx: *context.Windowed) !void {
    // TODO: don't do a full redraw every time
    for (0..ctx.window.width) |i| {
        const pitch: u7 = common.to(u7, i + self.pitch_offset) orelse break;
        _ = try ctx.window.printSegment(upperKeySegment(pitch), .{
            .col_offset = @intCast(i),
            .row_offset = 0,
        });
    }
    for (0..ctx.window.width) |i| {
        const pitch: u7 = common.to(u7, i + self.pitch_offset) orelse break;
        _ = try ctx.window.printSegment(lowerKeySegment(pitch), .{
            .col_offset = @intCast(i),
            .row_offset = 1,
        });
    }
    // TODO: when a mouse clicks a note, play the note on the synthesizer
    // TODO
}

// TODO: when in a different key, use the correct C#/Db flats vs. sharps, etc.
fn upperKeySegment(pitch: u7) context.Segment {
    return switch (pitch % 12) {
        0 => .{ .text = " ", .style = .{ .reverse = true } }, // A
        1 => .{ .text = " ", .style = .{ .reverse = false } }, // A# or Bb
        2 => .{ .text = " ", .style = .{ .reverse = true } }, // B
        3 => .{ .text = " ", .style = .{ .reverse = true } }, // C
        4 => .{ .text = " ", .style = .{ .reverse = false } }, // C# or Db
        5 => .{ .text = " ", .style = .{ .reverse = true } }, // D
        6 => .{ .text = " ", .style = .{ .reverse = false } }, // D# or Eb
        7 => .{ .text = " ", .style = .{ .reverse = true } }, // E
        8 => .{ .text = " ", .style = .{ .reverse = true } }, // F
        9 => .{ .text = " ", .style = .{ .reverse = false } }, // F# or Gb
        10 => .{ .text = " ", .style = .{ .reverse = true } }, // G
        11 => .{ .text = " ", .style = .{ .reverse = false } }, // G# or Ab
        else => unreachable,
    };
}

fn lowerKeySegment(pitch: u7) context.Segment {
    return switch (pitch % 12) {
        0 => .{ .text = "A", .style = .{ .reverse = true } },
        1 => .{ .text = "░", .style = .{ .reverse = false } }, // A# or Bb
        2 => .{ .text = "B", .style = .{ .reverse = true } },
        3 => .{ .text = "C", .style = .{ .reverse = true } },
        4 => .{ .text = "░", .style = .{ .reverse = false } }, // C# or Db
        5 => .{ .text = "D", .style = .{ .reverse = true } },
        6 => .{ .text = "░", .style = .{ .reverse = false } }, // D# or Eb
        7 => .{ .text = "E", .style = .{ .reverse = true } },
        8 => .{ .text = "F", .style = .{ .reverse = true } },
        9 => .{ .text = "░", .style = .{ .reverse = false } }, // F# or Gb
        10 => .{ .text = "G", .style = .{ .reverse = true } },
        11 => .{ .text = "░", .style = .{ .reverse = false } }, // G# or Ab
        else => unreachable,
    };
}
