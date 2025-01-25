const lib = @import("lib");

const time = lib.time;
const Shtick = lib.Shtick;
const common = lib.common;

const OwnedPorts = lib.owned_list.OwnedList(Port);

const std = @import("std");
const c = @cImport({
    @cInclude("rtmidi_c.h");
});

pub const MidiEvent = union(enum) {
    /// Ports were connected or disconnected.
    ports_updated,
    note_on: Note,
    note_off: Note,

    pub const Note = MidiNote;
};

pub const MidiNote = struct {
    port: u8,
    pitch: u8,
    // How fast to hit (or release) a note.
    velocity: u8,
};

const Running = enum(u8) {
    not_running,
    ready,
    running,
};

pub fn MidiEventCallback(comptime D: type) type {
    return *const fn (data: D, e: MidiEvent) void;
}

var running = lib.mutex.Mutex(Running).init(.not_running);

fn make(run_value: Running) void {
    running.acquire();
    running.value = run_value;
    running.release();
}

pub const RtMidi = struct {
    pub const Error = error{
        could_not_init,
    };
    pub const Event = MidiEvent;
    pub fn Callback(comptime D: type) type {
        return MidiEventCallback(D);
    }

    // Number of ticks to wait before checking for plug/unplugs.
    update_port_wait: u16 = 15,
    update_port_counter: u16 = 0,
    ports: OwnedPorts = OwnedPorts.init(),
    rt: c.RtMidiInPtr,
    log_file: ?std.fs.File,

    pub fn init() Error!Self {
        if (!running.tryAcquire() or running.value != .not_running) {
            @panic("don't use more than one RtMidi at a time");
        }
        running.value = .ready;
        running.release();

        const log_file = std.fs.cwd().createFile("rtmidi.out", .{}) catch null;
        writeLogFile(log_file, "midi init...\n", .{});
        const rt = c.rtmidi_in_create_default();
        if (rt.*.ptr == null) {
            writeLogFile(log_file, "midi init error: {s}!!\n", .{rt.*.msg});
            c.rtmidi_in_free(rt);
            return Error.could_not_init;
        }
        writeLogFile(log_file, "midi init complete.\n", .{});
        return Self{
            .log_file = log_file,
            .rt = rt,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stopWith(.not_running);
        // TODO: For some reason we are having trouble synchronizing the stop and leaking memory...
        self.ports.deinit();
        c.rtmidi_in_free(self.rt);
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
        self.writeLog("stopping midi...\n", .{});
        make(run_value);
        self.writeLog("midi stopped.\n", .{});
    }

    // TODO: add a `context: anytype` that we pass in to the function.
    pub fn start(self: *Self, sleep_duration: time.Duration, data: anytype, callback: Callback(@TypeOf(data))) void {
        self.writeLog("midi starting...\n", .{});
        std.debug.assert(self.rt.*.ptr != null);

        make(.running);
        _ = std.Thread.spawn(.{}, midiLoop, .{ self, sleep_duration, data, callback }) catch {
            @panic("couldn't spawn RtMidi thread");
        };
    }

    fn midiLoop(self: *Self, sleep_duration: time.Duration, data: anytype, callback: Callback(@TypeOf(data))) void {
        while (true) {
            running.acquire();
            if (running.value != .running) {
                running.release();
                break;
            }
            self.maybeUpdatePorts(data, callback);
            self.notify(data, callback);
            running.release();

            time.sleep(sleep_duration);
        }
        self.writeLog("midi loop stopped.\n", .{});
    }

    pub inline fn portCount(self: *const Self) u32 {
        std.debug.assert(self.rt.*.ptr != null);
        return c.rtmidi_get_port_count(self.rt);
    }

    // Caller needs to deinit the Shtick.
    pub fn portName(self: *Self, port: u32) Shtick {
        std.debug.assert(self.rt.*.ptr != null);
        var buffer: [Shtick.max_count + 1]u8 = undefined;
        var buffer_len: c_int = @intCast(buffer.len);
        const name_count = c.rtmidi_get_port_name(self.rt, port, &buffer, &buffer_len);
        if (name_count <= 0) {
            // TODO: log error
            return Shtick.unallocated("BadPort@?!");
        }
        return Shtick.init(buffer[0..@intCast(name_count)]) catch {
            @panic("ran out of memory for port names");
        };
    }

    fn notify(self: *Self, data: anytype, callback: Callback(@TypeOf(data))) void {
        for (self.ports.items()) |*port| {
            while (port.notify()) |event| {
                callback(data, event);
            }
        }
    }

    fn maybeUpdatePorts(self: *Self, data: anytype, callback: Callback(@TypeOf(data))) void {
        self.update_port_counter += 1;
        if (self.update_port_counter < self.update_port_wait) {
            return;
        }
        self.update_port_counter = 0;
        const port_count = self.portCount();
        var result: ?Event = if (port_count != self.ports.count()) blk: {
            self.writeLog("seeing {d} midi ports, had {d} ports.\n", .{ port_count, self.ports.count() });
            while (self.ports.count() > port_count) {
                var port = self.ports.pop() orelse @panic("should have a port to pop");
                self.writeLog("removing port {d} for now: {s}\n", .{ port.port, port.name.slice() });
                port.deinit();
            }
            break :blk Event.ports_updated;
        } else null;

        for (0..port_count) |pusize| {
            const p: u32 = @intCast(pusize);
            var port_name = self.portName(p);
            defer port_name.deinit();

            if (self.ports.maybe(p)) |port| {
                if (port.name.equals(port_name)) {
                    continue;
                }
                // need to deinit some ports here, this one doesn't match.
                // if p == 0, we need to delete all the way down to count 0,
                // then build up again, and same for any p > 0, we need to get
                // to that count.
                while (true) {
                    var mismatched_port = common.assert(self.ports.pop());
                    mismatched_port.deinit();
                    if (self.ports.count() == p) {
                        break;
                    }
                }
            } else {
                // we didn't have a port here, so definitely need to update
            }
            result = Event.ports_updated;
            if (self.ports.count() != p) {
                @panic("expected self.ports.count() == p");
            }
            self.writeLog("got a new/updated port {d}: {s}\n", .{ p, port_name.slice() });
            self.ports.append(Port.init(port_name.moot(), p)) catch {
                @panic("expected not a lot of ports open");
            };
        }
        if (result) |event| {
            callback(data, event);
        }
    }

    const Self = @This();
};

const Port = struct {
    name: Shtick,
    port: u32,
    device: c.RtMidiInPtr,

    fn init(name: Shtick, port: u32) Self {
        var buffer: [12]u8 = .{ 'p', 'a', 't', 'c', 'h', 's', 'o', 'u', 'l', '9', '9', 0 };
        buffer[9] = @intCast('0' + ((port / 10) % 10));
        buffer[10] = @intCast('0' + (port % 10));
        const device = c.rtmidi_in_create(c.RTMIDI_API_UNSPECIFIED, &buffer, 128);
        if (device.*.ptr == null) {
            @panic("Port should have been openable");
        }
        c.rtmidi_open_port(device, port, &buffer);
        return Self{ .name = name, .port = port, .device = device };
    }

    fn deinit(self: *Self) void {
        c.rtmidi_close_port(self.device);
        c.rtmidi_in_free(self.device);
        self.device = null;
        self.name.deinit();
    }

    fn notify(self: *Self) ?MidiEvent {
        var message: [64]u8 = undefined;
        var message_count = message.len;
        const timestamp = c.rtmidi_in_get_message(self.device, &message, &message_count);
        _ = timestamp;
        switch (message_count) {
            3 => switch (message[0]) {
                144 => return .{ .note_on = .{
                    .port = @intCast(self.port),
                    .pitch = message[1],
                    .velocity = message[2],
                } },
                128 => return .{ .note_off = .{
                    .port = @intCast(self.port),
                    .pitch = message[1],
                    .velocity = message[2],
                } },
                else => {},
            },
            0 => return null,
            else => {},
        }
        // TODO: log unknown midi event
        return null;
    }

    const Self = @This();
};
