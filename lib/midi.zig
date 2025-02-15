const common = @import("common.zig");
const lib_file = @import("file.zig");
const owned_list = @import("owned_list.zig");
const Shtick = @import("shtick.zig").Shtick;

const ByteCountReader = lib_file.ByteCountReader;
const FileHelper = lib_file.Helper;
const OwnedTrackEvents = owned_list.OwnedList(TrackEvent);
const OwnedTracks = owned_list.OwnedList(Track);

const std = @import("std");

pub const TrackEvent = struct {
    ticks: i32,
    event: Event,

    pub fn equals(a: Self, b: Self) bool {
        return common.structEqual(a, b);
    }

    const Self = @This();
};

pub const Event = union(enum) {
    /// Ports were connected or disconnected.
    ports_updated,
    note_on: Note,
    note_off: Note,

    pub fn equals(a: Self, b: Self) bool {
        return common.taggedEqual(a, b);
    }

    const Self = @This();
};

pub const Note = struct {
    port: u8,
    pitch: u8,
    // How fast to hit (or release) a note.
    velocity: u8,

    pub fn equals(a: Self, b: Self) bool {
        return common.structEqual(a, b);
    }

    const Self = @This();
};

pub const Track = struct {
    // TODO: maybe come up with some cooler data structure here
    // to support efficient insertion/deletion anywhere.
    events: OwnedTrackEvents,

    pub const Error = error{
        close_to_overflow,
    };

    pub fn init() Self {
        return Self{ .events = OwnedTrackEvents.init() };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit();
    }

    pub inline fn count(self: *const Self) usize {
        return self.events.count();
    }

    // try not to add multiple events that are the same.
    pub fn insert(self: *Self, track_event: TrackEvent) !void {
        if (track_event.ticks >= std.math.maxInt(i32)) {
            return Error.close_to_overflow;
        }
        if (self.count() > 0) {
            if (self.findNextIndex(track_event.ticks + 1)) |insertion_index| {
                // As a slight optimization, insert at the end of the current list
                // of events with the same ticks as `track_event.ticks`:
                try self.events.insert(insertion_index, track_event);
                return;
            }
        }
        try self.events.append(track_event);
    }

    // Returns true iff the track event got erased (i.e., was present).
    // Erases only the first instance.
    pub fn erase(self: *Self, track_event: TrackEvent) bool {
        var index = self.findNextIndex(track_event.ticks) orelse return false;
        while (index < self.count()) {
            const index_event = self.events.inBounds(index);
            if (index_event.ticks != track_event.ticks) return false;
            if (index_event.event.equals(track_event.event)) {
                _ = self.events.remove(index);
                return true;
            }
            index += 1;
        }
        return false;
    }

    pub fn findNext(self: *Self, range: Range) ?TrackEvent {
        // TODO
        _ = self;
        _ = range;
        return null;
    }

    pub fn allEvents(self: *Self, range: Range) []TrackEvent {
        // TODO
        _ = range;
        return self.events.items();
    }

    // Finds the index of the first event whose `ticks >= at_ticks`.
    fn findNextIndex(self: *Self, at_ticks: i32) ?usize {
        var low: usize = 0;
        var high = common.before(self.events.count()) orelse return null;
        while (true) {
            const middle = (low + high) / 2;
            if (self.events.inBounds(middle).ticks >= at_ticks) {
                if (middle == low) {
                    return middle;
                }
                high = middle;
            } else {
                // events[middle].ticks < at_ticks
                if (middle == low) {
                    return if (self.events.inBounds(high).ticks >= at_ticks)
                        high
                    else
                        null;
                }
                low = middle;
            }
        }
    }

    // Finds the indices of the event whose `ticks >= start_ticks` and `ticks < end_ticks`.
    fn findNextRange(self: *Self, start_ticks: i32, end_ticks: i32) ?IndexRange {
        const start_index = self.findNextIndex(start_ticks) orelse return null;
        const end_index = self.findNextIndex(end_ticks) orelse self.events.count();
        return .{ .start_index = start_index, .end_index = end_index };
    }

    const IndexRange = struct {
        start_index: usize,
        end_index: usize,
    };

    pub const Range = TrackRange;

    const Self = @This();
};

pub const TickRange = struct { start: i32, end: i32 };

pub const TrackRange = union(enum) {
    at_ticks: i32,
    tick_range: TickRange,
    all: void,

    fn to_tick_range(self: Self) TickRange {
        return switch (self) {
            .at_ticks => |at_ticks| .{ .start = at_ticks, .end = at_ticks + 1 },
            .tick_range => |tick_range| tick_range,
            .all => .{ .start = std.math.minInt(i32), .end = std.math.maxInt(i32) },
        };
    }

    const Self = @This();
};

pub const File = struct {
    pub const max_track_count = 32;

    pub const Error = error{
        invalid_midi_file,
    };

    pub const Header = struct {
        track_count: i16 = 0,
        ticks_per_beat: i16 = 360,
    };

    path: Shtick,
    header: Header,
    tracks: OwnedTracks,

    pub fn deinit(self: *Self) void {
        self.path.deinit();
        self.tracks.deinit();
    }

    /// The midi File will take ownership of the path Shtick without making a copy,
    /// so don't free it at the callsite.
    pub fn init(path: Shtick) Self {
        var result = Self{ .path = path, .header = .{}, .tracks = OwnedTracks.init() };
        result.read() catch {};
        return result;
    }

    /// Re-reads the file from disk.  Returns an error if unsuccessful.
    pub fn read(self: *Self) !void {
        var file = try std.fs.cwd().openFile(self.path.slice(), .{});
        defer file.close();
        errdefer file.close();
        const reader = file.reader();

        const new_header = try readHeader(reader);
        const new_tracks = try readTracks(reader);
        self.header = new_header;
        self.tracks = new_tracks;
        if (self.tracks.count() != self.header.track_count) {
            // TODO: print an error somewhere
        }
    }

    /// Writes the file to disk.  Returns an error if unsuccessful.
    pub fn write(self: *const Self) !void {
        var file = try std.fs.cwd().createFile(self.path.slice(), .{});
        defer file.close();
        errdefer file.close();
        const writer = file.writer();

        try self.writeHeader(writer);
        try self.writeTracks(writer);
    }

    fn readHeader(reader: anytype) !Header {
        const file_type = try FileHelper.readBytes(4, reader);
        if (!std.mem.eql(u8, &file_type, "MThd")) {
            return Error.invalid_midi_file;
        }
        const size = try FileHelper.readBigEndian(i32, reader);
        if (size != 6) {
            return Error.invalid_midi_file;
        }
        const format = try FileHelper.readBigEndian(i16, reader);
        // format == 0 is single track, format == 1 is potentially multiple tracks.
        // there is technically a format == 2, but out of scope for us.
        if (!(format == 0 or format == 1)) {
            return Error.invalid_midi_file;
        }
        const track_count = try FileHelper.readBigEndian(i16, reader);
        const ticks_per_beat = try FileHelper.readBigEndian(i16, reader);
        if (track_count > max_track_count) {
            return Error.invalid_midi_file;
        }
        return Header{ .track_count = track_count, .ticks_per_beat = ticks_per_beat };
    }

    fn writeHeader(self: *const Self, writer: anytype) !void {
        const track_count: i16 = @intCast(self.tracks.count());
        if (track_count > max_track_count) {
            return Error.invalid_midi_file;
        }

        try std.fmt.format(writer, "MThd", .{});
        const size: i32 = 6;
        try FileHelper.writeBigEndian(writer, size);
        // format == 0 is single track, format == 1 is potentially multiple tracks.
        const format: i16 = if (track_count == 1) 0 else 1;
        try FileHelper.writeBigEndian(writer, format);

        try FileHelper.writeBigEndian(writer, track_count);
        try FileHelper.writeBigEndian(writer, self.header.ticks_per_beat);
    }

    fn readTracks(reader: anytype) !OwnedTracks {
        var tracks = OwnedTracks.init();
        errdefer tracks.deinit();
        while (true) {
            const next_track = readTrack(reader) catch break;
            try tracks.append(next_track);
        }
        if (tracks.count() > max_track_count) {
            return Error.invalid_midi_file;
        }
        return tracks;
    }

    fn writeTracks(self: *const Self, writer: anytype) !void {
        for (self.tracks.items()) |track| {
            try writeTrack(writer, track);
        }
    }

    fn readTrack(reader: anytype) !Track {
        const chunk_type = try FileHelper.readBytes(4, reader);
        if (!std.mem.eql(u8, &chunk_type, "MTrk")) {
            return Error.invalid_midi_file;
        }
        const track = Track.init();
        errdefer track.deinit();

        //const track_byte_count = try FileHelper.readBigEndian(u32, reader);
        //var byte_counter = ByteCountReader(@TypeOf(reader)).init(reader);

        //var tick: i32 = 0;
        //var last_status: u8 = 0;

        //while (true) {
        //    tick += try FileHelper.readVariableCount(i32, &byte_counter);

        //}

        return track;
    }

    fn writeTrack(writer: anytype, track: Track) !void {
        try writer.writeAll("MTrk");
        _ = track;
    }

    const Self = @This();
};

test "midi.Track erase works for degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 1234, .event = .ports_updated });
    try events.append(.{ .ticks = 6789, .event = .ports_updated });
    try events.append(.{ .ticks = 6789, .event = .{ .note_off = .{ .port = 0, .pitch = 1, .velocity = 2 } } });
    var track = Track{ .events = events };
    defer track.deinit();

    try std.testing.expectEqual(
        true,
        track.erase(.{ .ticks = 6789, .event = .{ .note_off = .{ .port = 0, .pitch = 1, .velocity = 2 } } }),
    );

    try track.events.expectEqualsSlice(&[_]TrackEvent{
        .{ .ticks = 1234, .event = .ports_updated },
        .{ .ticks = 6789, .event = .ports_updated },
    });
}

test "midi.Track erase works for non-degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 123, .event = .ports_updated });
    try events.append(.{ .ticks = 456, .event = .ports_updated });
    try events.append(.{ .ticks = 789, .event = .ports_updated });
    var track = Track{ .events = events };
    defer track.deinit();

    try std.testing.expectEqual(
        false,
        track.erase(.{ .ticks = 789, .event = .{ .note_off = .{ .port = 0, .pitch = 1, .velocity = 2 } } }),
    );

    try track.events.expectEqualsSlice(&[_]TrackEvent{
        .{ .ticks = 123, .event = .ports_updated },
        .{ .ticks = 456, .event = .ports_updated },
        .{ .ticks = 789, .event = .ports_updated },
    });

    try std.testing.expectEqual(
        true,
        track.erase(.{ .ticks = 123, .event = .ports_updated }),
    );

    try track.events.expectEqualsSlice(&[_]TrackEvent{
        .{ .ticks = 456, .event = .ports_updated },
        .{ .ticks = 789, .event = .ports_updated },
    });
}

test "midi.Track insert works for degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 1234, .event = .ports_updated });
    try events.append(.{ .ticks = 6789, .event = .ports_updated });
    try events.append(.{ .ticks = 6789, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } });
    var track = Track{ .events = events };
    defer track.deinit();

    try track.insert(.{ .ticks = 6789, .event = .{ .note_off = .{ .port = 0, .pitch = 1, .velocity = 2 } } });

    try track.events.expectEqualsSlice(&[_]TrackEvent{
        .{ .ticks = 1234, .event = .ports_updated },
        .{ .ticks = 6789, .event = .ports_updated },
        .{ .ticks = 6789, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } },
        .{ .ticks = 6789, .event = .{ .note_off = .{ .port = 0, .pitch = 1, .velocity = 2 } } },
    });

    try track.insert(.{ .ticks = 1234, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } });

    try track.events.expectEqualsSlice(&[_]TrackEvent{
        .{ .ticks = 1234, .event = .ports_updated },
        .{ .ticks = 1234, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } },
        .{ .ticks = 6789, .event = .ports_updated },
        .{ .ticks = 6789, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } },
        .{ .ticks = 6789, .event = .{ .note_off = .{ .port = 0, .pitch = 1, .velocity = 2 } } },
    });
}

test "midi.Track insert works for non-degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 1234, .event = .ports_updated });
    try events.append(.{ .ticks = 6789, .event = .ports_updated });
    var track = Track{ .events = events };
    defer track.deinit();

    try track.insert(.{ .ticks = 5555, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } });

    try track.events.expectEqualsSlice(&[_]TrackEvent{
        .{ .ticks = 1234, .event = .ports_updated },
        .{ .ticks = 5555, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } },
        .{ .ticks = 6789, .event = .ports_updated },
    });

    // and test insertions at start and end...
    try track.insert(.{ .ticks = 1000, .event = .{ .note_on = .{ .port = 9, .pitch = 5, .velocity = 4 } } });
    try track.insert(.{ .ticks = 7000, .event = .{ .note_off = .{ .port = 9, .pitch = 5, .velocity = 4 } } });

    try track.events.expectEqualsSlice(&[_]TrackEvent{
        .{ .ticks = 1000, .event = .{ .note_on = .{ .port = 9, .pitch = 5, .velocity = 4 } } },
        .{ .ticks = 1234, .event = .ports_updated },
        .{ .ticks = 5555, .event = .{ .note_on = .{ .port = 0, .pitch = 1, .velocity = 2 } } },
        .{ .ticks = 6789, .event = .ports_updated },
        .{ .ticks = 7000, .event = .{ .note_off = .{ .port = 9, .pitch = 5, .velocity = 4 } } },
    });
}

test "midi.Track binary search works for fully degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 123, .event = .ports_updated });
    try events.append(.{ .ticks = 123, .event = .ports_updated });
    try events.append(.{ .ticks = 123, .event = .ports_updated });
    var track = Track{ .events = events };
    defer track.deinit();

    try std.testing.expectEqual(0, track.findNextIndex(122));
    try std.testing.expectEqual(0, track.findNextIndex(123));
    try std.testing.expectEqual(null, track.findNextIndex(124));
}

test "midi.Track binary search works for degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 123, .event = .ports_updated });
    try events.append(.{ .ticks = 123, .event = .ports_updated });
    try events.append(.{ .ticks = 456, .event = .ports_updated });
    try events.append(.{ .ticks = 456, .event = .ports_updated });
    try events.append(.{ .ticks = 789, .event = .ports_updated });
    try events.append(.{ .ticks = 789, .event = .ports_updated });
    var track = Track{ .events = events };
    defer track.deinit();

    try std.testing.expectEqual(0, track.findNextIndex(122));
    try std.testing.expectEqual(0, track.findNextIndex(123));

    try std.testing.expectEqual(2, track.findNextIndex(455));
    try std.testing.expectEqual(2, track.findNextIndex(456));

    try std.testing.expectEqual(4, track.findNextIndex(788));
    try std.testing.expectEqual(4, track.findNextIndex(789));

    try std.testing.expectEqual(null, track.findNextIndex(790));
}

test "midi.Track binary search works for odd-count non-degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 123, .event = .ports_updated });
    try events.append(.{ .ticks = 456, .event = .ports_updated });
    try events.append(.{ .ticks = 789, .event = .ports_updated });
    var track = Track{ .events = events };
    defer track.deinit();

    try std.testing.expectEqual(0, track.findNextIndex(122));
    try std.testing.expectEqual(0, track.findNextIndex(123));

    try std.testing.expectEqual(1, track.findNextIndex(455));
    try std.testing.expectEqual(1, track.findNextIndex(456));

    try std.testing.expectEqual(2, track.findNextIndex(788));
    try std.testing.expectEqual(2, track.findNextIndex(789));

    try std.testing.expectEqual(null, track.findNextIndex(790));
}

test "midi.Track binary search works for even-count non-degenerate case" {
    var events = OwnedTrackEvents.init();
    try events.append(.{ .ticks = 12, .event = .ports_updated });
    try events.append(.{ .ticks = 34, .event = .ports_updated });
    try events.append(.{ .ticks = 56, .event = .ports_updated });
    try events.append(.{ .ticks = 78, .event = .ports_updated });
    var track = Track{ .events = events };
    defer track.deinit();

    try std.testing.expectEqual(0, track.findNextIndex(11));
    try std.testing.expectEqual(0, track.findNextIndex(12));

    try std.testing.expectEqual(1, track.findNextIndex(33));
    try std.testing.expectEqual(1, track.findNextIndex(34));

    try std.testing.expectEqual(2, track.findNextIndex(55));
    try std.testing.expectEqual(2, track.findNextIndex(56));

    try std.testing.expectEqual(3, track.findNextIndex(77));
    try std.testing.expectEqual(3, track.findNextIndex(78));

    try std.testing.expectEqual(null, track.findNextIndex(79));
}

test "midi.TrackEvent works with equals" {
    try std.testing.expectEqual(
        true,
        (TrackEvent{ .ticks = 123, .event = .ports_updated }).equals(
            TrackEvent{ .ticks = 123, .event = .ports_updated },
        ),
    );
    const note_on = TrackEvent{ .ticks = 123, .event = .{ .note_on = Note{ .port = 0, .pitch = 1, .velocity = 2 } } };
    try std.testing.expectEqual(true, note_on.equals(note_on));
    const note_off = TrackEvent{ .ticks = 123, .event = .{ .note_off = Note{ .port = 0, .pitch = 1, .velocity = 2 } } };
    try std.testing.expectEqual(true, note_off.equals(note_off));

    // events are different (note_on vs. note_off)
    try std.testing.expectEqual(false, note_on.equals(note_off));

    // ticks are different
    try std.testing.expectEqual(
        false,
        (TrackEvent{ .ticks = 123, .event = .ports_updated }).equals(
            TrackEvent{ .ticks = 456, .event = .ports_updated },
        ),
    );

    // events are different (note_on specifics)
    var note_on2 = note_on;
    note_on2.event.note_on.velocity += 1;
    try std.testing.expectEqual(false, note_on2.equals(note_on));
}

test "midi.Note works with equals" {
    try std.testing.expectEqual(
        true,
        (Note{ .port = 1, .pitch = 2, .velocity = 3 }).equals(
            Note{ .port = 1, .pitch = 2, .velocity = 3 },
        ),
    );
    // first field off
    try std.testing.expectEqual(
        false,
        (Note{ .port = 1, .pitch = 2, .velocity = 3 }).equals(
            Note{ .port = 0, .pitch = 2, .velocity = 3 },
        ),
    );
    // middle field off
    try std.testing.expectEqual(
        false,
        (Note{ .port = 1, .pitch = 2, .velocity = 3 }).equals(
            Note{ .port = 1, .pitch = 3, .velocity = 3 },
        ),
    );
    // last field off
    try std.testing.expectEqual(
        false,
        (Note{ .port = 1, .pitch = 2, .velocity = 3 }).equals(
            Note{ .port = 1, .pitch = 2, .velocity = 4 },
        ),
    );
}
