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
        resolution: i16 = 360,
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
    }

    /// Writes the file to disk.  Returns an error if unsuccessful.
    pub fn write(self: *const Self) !void {
        var file = try std.fs.cwd().openFile(self.path.slice(), .{.mode = .write_only});
        defer file.close();
        errdefer file.close();
        const writer = file.writer();

        try self.writeHeader(writer);
        try self.writeTracks(writer);
    }

    fn readHeader(reader: anytype) !Header {
        const file_type = try lib_file.Reader.readBytes(4, reader);
        if (!std.mem.eql(u8, &file_type, "MThd")) {
            return Error.invalid_midi_file;
        }
        return Header{ .track_count = 0, .resolution = 0 };
    }

    fn writeHeader(self: *const Self, writer: anytype) !void {
        try std.fmt.format(writer, "MThd", .{});
        _ = self;
    }

    fn readTracks(reader: anytype) !OwnedTracks {
        const tracks = OwnedTracks.init();
        // TODO
        _ = reader;
        return tracks;
    }

    fn writeTracks(self: *const Self, writer: anytype) !void {
        _ = self;
        _ = writer;
        // TODO
    }

    const Self = @This();
};
