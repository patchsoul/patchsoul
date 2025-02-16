const lib = @import("lib");
const RtAudio = @import("rtaudio").RtAudio;
const zsynth = @import("ziggysynth");

const std = @import("std");

const Harmony = @This();
const Self = @This();

active_pitches: [128]u8 = .{0} ** 128,
synthesizer: zsynth.Synthesizer,
sound_font: *zsynth.SoundFont,
log_file: ?std.fs.File,

pub fn init(sound_font_path: lib.Shtick) !Self {
    var path = sound_font_path;
    defer path.deinit();
    const sound_font = try lib.common.allocator.create(zsynth.SoundFont);
    var sf2 = try std.fs.cwd().openFile(sound_font_path.slice(), .{});
    sound_font.* = try zsynth.SoundFont.init(lib.common.allocator, sf2.reader());
    var settings = zsynth.SynthesizerSettings.init(RtAudio.frequency_hz);
    const synthesizer = try zsynth.Synthesizer.init(lib.common.allocator, sound_font, &settings);
    return Self{ .synthesizer = synthesizer, .sound_font = sound_font,
        .log_file = std.fs.cwd().createFile("harmony.out", .{}) catch null,
    };
}

pub fn deinit(self: *Self) void {
    self.synthesizer.deinit();
    self.sound_font.deinit();
    lib.common.allocator.destroy(self.sound_font);
    if (self.log_file) |file| {
        file.close();
        self.log_file = null;
    }
}

pub fn noteOn(self: *Self, pitch: u8, velocity: u8) void {
    const channel: i32 = 0;
    // a velocity of 0 is considered a `noteOff` in ziggysynth, so normalize the velocity a bit.
    const normalized_velocity: u8 = 64 + velocity / 2;
    self.synthesizer.noteOn(channel, pitch, normalized_velocity);
    // TODO: whether recording or not, put into a "master midi file" that you can open read-only
    // and copy from.  master midi file "sleeps" if there's no input for a while.
    // make the master midi file have i64 ticks and 5040 resolution (ticks/beat).
    // don't do any snapping/autotuning here.  when copying into a local file, adjust ticks/resolution,
    // and if necessary, autotune or snap.
}

pub fn noteOff(self: *Self, pitch: u8, velocity: u8) void {
    // ziggysynth ignores note_off velocity.
    _ = velocity;
    const channel: i32 = 0;
    self.synthesizer.noteOff(channel, pitch);
    // TODO: add to master midi file
}

inline fn writeLog(self: *Self, comptime format: []const u8, data: anytype) void {
    if (self.log_file) |file| {
        std.fmt.format(file.writer(), format, data) catch {};
    }
}
