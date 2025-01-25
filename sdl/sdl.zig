const lib = @import("lib");

const audio = lib.audio;

const std = @import("std");

const c = @cImport({
    @cInclude("SDL/SDL2.h");
});

pub const StereoSample = struct {
    left: f32,
    right: f32,
};

fn mixSdlAudio(sdl: *SDL, u8_stream: *u8, bytes: c_int) void {
    const stereo_count: usize = bytes / (2 * @sizeOf(f32));
    std.debug.assert(stereo_count == sdl.samples);
    const stereo_stream: *StereoSample = @ptrCast(u8_stream);
    sdl.callback(sdl.data, stereo_stream[0..stereo_count]);
}

pub const AudioCallback = *const fn (data: ?*anyopaque, samples: []StereoSample) void;

fn emptyCallback(data: ?*anyopaque, samples: []StereoSample) void {
    _ = data;
    for (samples) |*sample| {
        sample.left = 0.0;
        sample.right = 0.0;
    }
}

pub const SDL = struct {
    frequency: audio.Frequency = audio.Frequency.Hz_44100,
    samples: u12 = 256,
    data: ?*anyopaque = null,
    callback: AudioCallback = emptyCallback,

    pub fn start(self: *Self) !void {
        if (c.SDL_Init(c.SDL_INIT_AUDIO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }
        var desired_spec = c.SDL_AudioSpec{
            .freq = self.frequency.to_hz(),
            .format = c.AUDIO_F32,
            .channels = 2, // stereo
            .samples = self.samples,
            // Use some indirection so people can change the data/callback if desired.
            .callback = mixSdlAudio,
            .userdata = self,
        };
        if (c.SDL_OpenAudio(&desired_spec, null) != 0) {
            c.SDL_Log("Unable to open SDL audio: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }
        self.mute(false);
    }

    pub fn stop(self: *Self) void {
        self.mute(true);
        c.SDL_CloseAudio();
        c.SDL_Quit();
    }

    pub inline fn mute(self: *Self, value: bool) void {
        _ = self;
        c.SDL_PauseAudio(if (value) 1 else 0);
    }

    const Self = @This();
};
