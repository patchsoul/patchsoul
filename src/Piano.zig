const context = @import("context.zig");
const MidiEvent = @import("event.zig").Midi;
const lib = @import("lib");
const SetList128 = lib.set_list.SetList128;
const common = lib.common;

const Piano = @This();
const Self = @This();

/// Pitch to start showing on the left side of the screen
pitch_offset: u7 = 0,
pitches_to_activate: SetList128 = SetList128{},
pitches_to_deactivate: SetList128 = SetList128{},

pub fn init() Self {
    return Self{};
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn update(self: *Self, midi: MidiEvent) void {
    switch (midi) {
        .note_on => |note_on| {
            _ = self.pitches_to_activate.add(@intCast(note_on.pitch));
            _ = self.pitches_to_deactivate.remove(@intCast(note_on.pitch));
        },
        .note_off => |note_off| {
            _ = self.pitches_to_deactivate.add(@intCast(note_off.pitch));
            _ = self.pitches_to_activate.remove(@intCast(note_off.pitch));
        },
        else => {},
    }
}

pub fn draw(self: *Self, ctx: *context.Windowed) !void {
    if (ctx.needs_full_redraw) {
        for (0..ctx.window.width) |col| {
            const pitch: u7 = common.to(u7, col + self.pitch_offset) orelse break;
            _ = try ctx.window.printSegment(upperKeySegment(pitch, false), .{
                .col_offset = @intCast(col),
                .row_offset = 0,
            });
        }
        for (0..ctx.window.width) |col| {
            const pitch: u7 = common.to(u7, col + self.pitch_offset) orelse break;
            _ = try ctx.window.printSegment(lowerKeySegment(pitch, false), .{
                .col_offset = @intCast(col),
                .row_offset = 1,
            });
        }
    }
    try self.maybeActivate(ctx, true);
    try self.maybeActivate(ctx, false);
    // TODO: when a mouse clicks a note, play the note on the synthesizer
    // TODO
}

fn maybeActivate(self: *Self, ctx: *context.Windowed, activated: bool) !void {
    const pitches: *SetList128 = if (activated) &self.pitches_to_activate else &self.pitches_to_deactivate;
    while (pitches.pop()) |pitch| {
        const col = common.back(pitch, self.pitch_offset) orelse continue;
        if (col >= ctx.window.width) continue;
        _ = try ctx.window.printSegment(upperKeySegment(pitch, activated), .{
            .col_offset = @intCast(col),
            .row_offset = 0,
        });
        _ = try ctx.window.printSegment(lowerKeySegment(pitch, activated), .{
            .col_offset = @intCast(col),
            .row_offset = 1,
        });
    }
}

// TODO: when in a different key, use the correct C#/Db flats vs. sharps, etc.
fn upperKeySegment(pitch: u7, activated: bool) context.Segment {
    if (activated) {
        return activatedKeySegment(pitch);
    }
    return switch (pitch % 12) {
        0 => .{ .text = " ", .style = .{ .reverse = true } }, // C
        1 => .{ .text = " ", .style = .{ .reverse = false } }, // C# or Db
        2 => .{ .text = " ", .style = .{ .reverse = true } }, // D
        3 => .{ .text = " ", .style = .{ .reverse = false } }, // D# or Eb
        4 => .{ .text = " ", .style = .{ .reverse = true } }, // E
        5 => .{ .text = " ", .style = .{ .reverse = true } }, // F
        6 => .{ .text = " ", .style = .{ .reverse = false } }, // F# or Gb
        7 => .{ .text = " ", .style = .{ .reverse = true } }, // G
        8 => .{ .text = " ", .style = .{ .reverse = false } }, // G# or Ab
        9 => .{ .text = " ", .style = .{ .reverse = true } }, // A
        10 => .{ .text = " ", .style = .{ .reverse = false } }, // A# or Bb
        11 => .{ .text = " ", .style = .{ .reverse = true } }, // B
        else => unreachable,
    };
}

fn lowerKeySegment(pitch: u7, activated: bool) context.Segment {
    return switch (pitch % 12) {
        0 => if (activated)
            activatedKeySegment(pitch)
        else
            .{ .text = "C", .style = .{ .reverse = true } },
        1 => .{ .text = "░", .style = .{ .reverse = false } }, // C# or Db
        2 => if (activated)
            activatedKeySegment(pitch)
        else
            .{ .text = "D", .style = .{ .reverse = true } },
        3 => .{ .text = "░", .style = .{ .reverse = false } }, // D# or Eb
        4 => if (activated)
            activatedKeySegment(pitch)
        else
            .{ .text = "E", .style = .{ .reverse = true } },
        5 => if (activated)
            activatedKeySegment(pitch)
        else
            .{ .text = "F", .style = .{ .reverse = true } },
        6 => .{ .text = "░", .style = .{ .reverse = false } }, // F# or Gb
        7 => if (activated)
            activatedKeySegment(pitch)
        else
            .{ .text = "G", .style = .{ .reverse = true } },
        8 => .{ .text = "░", .style = .{ .reverse = false } }, // G# or Ab
        9 => if (activated)
            activatedKeySegment(pitch)
        else
            .{ .text = "A", .style = .{ .reverse = true } },
        10 => .{ .text = "░", .style = .{ .reverse = false } }, // A# or Bb
        11 => if (activated)
            activatedKeySegment(pitch)
        else
            .{ .text = "B", .style = .{ .reverse = true } },
        else => unreachable,
    };
}

fn activatedKeySegment(pitch: u7) context.Segment {
    return switch (pitch % 12) {
        0 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 226 } } }, // C
        1 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 22 } } }, // C# or Db
        2 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 76 } } }, // D
        3 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 24 } } }, // D# or Eb
        4 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 51 } } }, // E
        5 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 27 } } }, // F
        6 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 20 } } }, // F# or Gb
        7 => .{ .text = " ", .style = .{.reverse = false,  .bg = .{ .index = 165 } } }, // G
        8 => .{ .text = " ", .style = .{.reverse = false,  .bg = .{ .index = 54 } } }, // G# or Ab
        9 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 196 } } }, // A
        10 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 130 } } }, // A# or Bb
        11 => .{ .text = " ", .style = .{ .reverse = false, .bg = .{ .index = 208 } } }, // B
        else => unreachable,
    };
}
