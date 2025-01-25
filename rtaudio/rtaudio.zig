const lib = @import("lib");

const time = lib.time;
const Shtick = lib.Shtick;
const common = lib.common;

const std = @import("std");
const c = @cImport({
    @cInclude("rtaudio_c.h");
});

pub const Sample = struct {
    left: f32,
    right: f32,
};

pub const AudioCallback = *const fn (data: *anyopaque, samples: []Sample) void;
pub const AudioCallable = struct { data: *anyopaque, callback: AudioCallback };

const Running = enum(u8) {
    not_running,
    ready,
    // TODO: if we're having trouble synchronizing, we might need this to be `running: AudioCallable`
    running,
};

var running = lib.mutex.Mutex(Running).init(.not_running);

fn make(run_value: Running) void {
    running.acquire();
    running.value = run_value;
    running.release();
}

pub fn rtAudioCallback(
    out: *anyopaque,
    in: *anyopaque,
    frame_count: u32,
    stream_time: f64,
    status: c.rtaudio_stream_status_t,
    user_data: *anyopaque,
) void {
    const out_sample: *Sample = @ptrCast(out);
    const samples = out_sample[0..frame_count];
    _ = in;
    _ = stream_time;
    _ = status;
    const rtaudio: *RtAudio = @ptrCast(user_data);
    if (rtaudio.callable) |callable| {
        callable.callback(callable.data, samples);
    } else {
        RtAudio.defaultCallback(rtaudio, samples);
    }
}

var log_file: ?std.fs.File = null;

inline fn writeLog(comptime format: []const u8, data: anytype) void {
    if (log_file) |file| {
        std.fmt.format(file.writer(), format, data) catch {};
    }
}

pub fn rtErrCallback(err: c.rtaudio_err_t, message: [:0]u8) void {
    writeLog("ERROR {d}: {s}\n", .{ err, message });
}

pub const RtAudio = struct {
    pub const Error = error{
        could_not_start,
    };
    pub const Callback = AudioCallback;
    pub const Callable = AudioCallable;
    rt: c.rtaudio_t,
    callable: ?Callable = null,

    pub fn defaultCallback(data: *anyopaque, samples: []Sample) void {
        _ = data;
        for (samples) |*sample| {
            sample.left = 0.0;
            sample.right = 0.0;
        }
    }

    pub fn init() Self {
        if (!running.tryAcquire() or running.value != .not_running) {
            @panic("don't use more than one RtAudio at a time");
        }
        running.value = .ready;
        running.release();

        log_file = std.fs.cwd().createFile("audio.out", .{}) catch null;
        writeLog("audio init...\n", .{});
        const rt = c.rtaudio_create(c.RTAUDIO_API_UNSPECIFIED);
        writeLog("audio init complete.\n", .{});
        return Self{ .rt = rt };
    }

    pub fn deinit(self: *Self) void {
        self.stopWith(.not_running);
        c.rtaudio_destroy(self.rt);
        self.rt = null;
        if (log_file) |file| {
            file.close();
            log_file = null;
        }
    }

    pub fn start(self: *Self) Error!void {
        running.acquire();
        defer running.release();
        std.debug.assert(running.value == .not_running);
        running.value = .running;
        var output = c.rtaudio_stream_parameters_t{
            .device_id = c.rtaudio_get_default_output_device(self.rt),
            .num_channels = 2, // stereo
            .first_channel = 0,
        };
        var frame_count = 256;
        if (c.rtaudi_open_stream(
            self.rt,
            &output,
            null,
            c.RTAUDIO_FORMAT_FLOAT32,
            44100,
            &frame_count,
            rtAudioCallback,
            self,
            null,
            rtErrCallback,
        ) != 0) {
            return Error.could_not_start;
        }
    }

    pub fn stop(self: *Self) void {
        self.stopWith(.ready);
    }

    fn stopWith(self: *Self, run_value: Running) void {
        _ = self;
        writeLog("stopping audio...\n", .{});
        make(run_value);
        writeLog("audio stopped.\n", .{});
    }

    const Self = @This();
};
