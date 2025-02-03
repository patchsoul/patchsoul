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
    path: Shtick,
    tracks: OwnedTracks,

    pub fn deinit(self: *Self) void {
        self.path.deinit();
        self.tracks.deinit();
    }

    /// The midi File will take ownership of the path Shtick without making a copy,
    /// so don't free it at the callsite.
    pub fn init(path: Shtick) Self {
        const tracks = if (std.fs.cwd().openFile(path.slice(), .{})) |file| blk: {
            defer file.close();
            break :blk readTracks(file.reader()) catch OwnedTracks.init();
        } else OwnedTracks.init();
        return Self { .path = path, .tracks = tracks };
    }
    
    /// The midi File will take ownership of the path Shtick without making a copy,
    /// so don't free it at the callsite.
    fn readTracks(reader: anytype) !OwnedTracks {
        // TODO
        _ = reader;
        return OwnedTracks.init();
    }

    const Self = @This();
};
