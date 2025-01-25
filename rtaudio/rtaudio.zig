const lib = @import("lib");

const time = lib.time;
const Shtick = lib.Shtick;
const common = lib.common;

const std = @import("std");
const c = @cImport({
    @cInclude("rtaudio_c.h");
});

pub const StereoSample = struct {
    left: f32,
    right: f32,
};

const Running = enum(u8) {
    not_running,
    ready,
    running,
};

var running = lib.mutex.Mutex(Running).init(.not_running);

fn make(run_value: Running) void {
    running.acquire();
    running.value = run_value;
    running.release();
}

pub const RtAudio = struct {
    rt: c.rtaudio_t,
    log_file: ?std.fs.File,

    pub fn init() Self {
        if (!running.tryAcquire() or running.value != .not_running) {
            @panic("don't use more than one RtAudio at a time");
        }
        running.value = .ready;
        running.release();

        const log_file = std.fs.cwd().createFile("audio.out", .{}) catch null;
        writeLogFile(log_file, "audio init...\n", .{});
        const rt = c.rtaudio_create(c.RTAUDIO_API_UNSPECIFIED);
        writeLogFile(log_file, "audio init complete.\n", .{});
        return Self{
            .log_file = log_file,
            .rt = rt,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stopWith(.not_running);
        // TODO: For some reason we are having trouble synchronizing the stop and leaking memory...
        c.rtaudio_destroy(self.rt);
        self.rt = null;
        if (self.log_file) |file| {
            file.close();
            self.log_file = null;
        }
    }

    fn writeLogFile(log_file: ?std.fs.File, comptime format: []const u8, data: anytype) void {
        if (log_file) |file| {
            std.fmt.format(file.writer(), format, data) catch {};
        }
    }

    inline fn writeLog(self: *Self, comptime format: []const u8, data: anytype) void {
        writeLogFile(self.log_file, format, data);
    }

    pub fn stop(self: *Self) void {
        self.stopWith(.ready);
    }

    fn stopWith(self: *Self, run_value: Running) void {
        self.writeLog("stopping audio...\n", .{});
        make(run_value);
        self.writeLog("audio stopped.\n", .{});
    }

    const Self = @This();
};
