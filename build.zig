const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.createModule(.{
        .root_source_file = b.path("lib/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    var rtaudio = addRtAudioModule(b, target, optimize);
    rtaudio.addImport("lib", lib);

    var rtmidi = addRtMidiModule(b, target, optimize);
    rtmidi.addImport("lib", lib);

    const vaxis = addVaxisDependency(b, target, optimize);
    const ziggysynth = addZiggySynthDependency(b, target, optimize);

    const exe = b.addExecutable(.{
        .name = "patchsoul",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("lib", lib);
    exe.root_module.addImport("rtaudio", rtaudio);
    exe.root_module.addImport("rtmidi", rtmidi);
    exe.root_module.addImport("vaxis", vaxis);
    exe.root_module.addImport("ziggysynth", ziggysynth);

    b.installArtifact(exe);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("lib", lib);
    exe_unit_tests.root_module.addImport("rtaudio", rtaudio);
    exe_unit_tests.root_module.addImport("rtmidi", rtmidi);
    exe_unit_tests.root_module.addImport("vaxis", vaxis);
    exe_unit_tests.root_module.addImport("ziggysynth", ziggysynth);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("lib/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_lib_unit_tests.step);
}

fn addRtAudioModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const rtaudio_dep_c = b.dependency("rtaudio", .{
        .target = target,
        .optimize = optimize,
    });
    const rtaudio_zig = b.addStaticLibrary(.{
        .name = "rtaudio-zig",
        .root_source_file = b.path("rtaudio/rtaudio.zig"),
        .target = target,
        .optimize = optimize,
    });
    // TODO: add other operating system configurations
    if (target.result.os.tag == .linux) {
        // TODO: add option for __UNIX_JACK__
        rtaudio_zig.defineCMacro("__LINUX_ALSA__", "1");
        rtaudio_zig.linkSystemLibrary("alsa");
    }
    rtaudio_zig.linkLibC();
    rtaudio_zig.linkLibCpp();
    rtaudio_zig.addCSourceFiles(.{
        .root = rtaudio_dep_c.path(""),
        .files = &.{ "rtaudio_c.cpp", "RtAudio.cpp" },
    });
    rtaudio_zig.installHeadersDirectory(rtaudio_dep_c.path(""), "", .{
        .include_extensions = &.{ "rtaudio_c.h", "RtAudio.h" },
    });
    b.installArtifact(rtaudio_zig);
    const rtaudio = b.addModule("rtaudio", .{
        .root_source_file = b.path("rtaudio/rtaudio.zig"),
    });
    rtaudio.addIncludePath(rtaudio_dep_c.path(""));
    rtaudio.linkLibrary(rtaudio_zig);
    return rtaudio;
}

fn addRtMidiModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const rtmidi_dep_c = b.dependency("rtmidi", .{
        .target = target,
        .optimize = optimize,
    });
    const rtmidi_zig = b.addStaticLibrary(.{
        .name = "rtmidi-zig",
        .root_source_file = b.path("rtmidi/rtmidi.zig"),
        .target = target,
        .optimize = optimize,
    });
    // TODO: add other operating system configurations
    if (target.result.os.tag == .linux) {
        // TODO: add option for __UNIX_JACK__
        rtmidi_zig.defineCMacro("__LINUX_ALSA__", "1");
        rtmidi_zig.linkSystemLibrary("alsa");
    }
    rtmidi_zig.linkLibC();
    rtmidi_zig.linkLibCpp();
    rtmidi_zig.addCSourceFiles(.{
        .root = rtmidi_dep_c.path(""),
        .files = &.{ "rtmidi_c.cpp", "RtMidi.cpp" },
    });
    rtmidi_zig.installHeadersDirectory(rtmidi_dep_c.path(""), "", .{
        .include_extensions = &.{ "rtmidi_c.h", "RtMidi.h" },
    });
    b.installArtifact(rtmidi_zig);
    const rtmidi = b.addModule("rtmidi", .{
        .root_source_file = b.path("rtmidi/rtmidi.zig"),
    });
    rtmidi.addIncludePath(rtmidi_dep_c.path(""));
    rtmidi.linkLibrary(rtmidi_zig);
    return rtmidi;
}

fn addVaxisDependency(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    return vaxis_dep.module("vaxis");
}

fn addZiggySynthDependency(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const ziggysynth_dep = b.dependency("ziggysynth", .{
        .target = target,
        .optimize = optimize,
    });
    const ziggysynth = b.addModule("ziggysynth", .{
        .root_source_file = ziggysynth_dep.path("src/ziggysynth.zig"),
        .target = target,
        .optimize = optimize,
    });
    return ziggysynth;
}
