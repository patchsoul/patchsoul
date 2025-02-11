const lib_file = @import("file.zig");
const owned_list = @import("owned_list.zig");
const Shtick = @import("shtick.zig").Shtick;

const OwnedTimedEvents = owned_list.OwnedList(TimedEvent);
const OwnedTracks = owned_list.OwnedList(Track);

const std = @import("std");

pub const Track = struct {
    timed_events: OwnedTimedEvents,
};

pub const TimedEvent = struct {
    tick: i32,
    event: Event,
};

pub const Event = union(enum) {
    /// Ports were connected or disconnected.
    ports_updated,
    note_on: Note,
    note_off: Note,
};

pub const Note = struct {
    port: u8,
    pitch: u8,
    // How fast to hit (or release) a note.
    velocity: u8,
};

pub const File = struct {
    pub const Error = error{
        invalid_midi_file,
    };

    pub const Header = struct {
        track_count: i16 = 0,
        resolution: i16 = 0,
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
        if (std.fs.cwd().openFile(path.slice(), .{})) |file| {
            defer file.close();
            errdefer file.close();
            const reader = file.reader();

            if (readHeader(reader)) |header| {
                const tracks = readTracks(reader) catch OwnedTracks.init();
                return Self{ .path = path, .header = header, .tracks = tracks };
            } else |_| {}
        } else |_| {}
        return Self{ .path = path, .header = .{}, .tracks = OwnedTracks.init() };
    }

    fn readHeader(reader: anytype) !Header {
        const file_type = try lib_file.Reader.readBytes(4, reader);
        if (!std.mem.eql(u8, &file_type, "MThd")) {
            return Error.invalid_midi_file;
        }
        return Header{ .track_count = 0, .resolution = 0 };
    }

    fn readTracks(reader: anytype) !OwnedTracks {
        const tracks = OwnedTracks.init();
        // TODO
        _ = reader;
        return tracks;
    }

    const Self = @This();
};
