const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "patchsoul",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    exe.root_module.addImport("rtmidi", rtmidi);

    const lib = b.createModule(.{
        .root_source_file = b.path("lib/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("lib", lib);

    b.installArtifact(exe);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
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
