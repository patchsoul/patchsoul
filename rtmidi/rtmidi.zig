const lib = @import("lib");

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
};

pub const RtMidi = struct {
    pub const Event = MidiEvent;

    // Number of ticks to wait before checking for plug/unplugs.
    update_port_wait: u16 = 15,
    update_port_counter: u16 = 0,
    rt: c.RtMidiInPtr,
    ports: OwnedPorts = OwnedPorts.init(),

    pub fn init() Self {
        return Self{
            .rt = c.rtmidi_in_create(c.RTMIDI_API_UNSPECIFIED, "patchsoul", 0),
        };
    }

    pub fn deinit(self: *Self) void {
        c.rtmidi_in_free(self.rt);
    }

    pub fn notify(self: *Self) ?Event {
        for (self.ports.items()) |*port| {
            if (port.notify()) |event| {
                return event;
            }
        }
        self.update_port_counter += 1;
        if (self.update_port_counter >= self.update_port_wait) {
            self.update_port_counter = 0;
            return self.updatePorts();
        }
        return null;
    }

    pub fn updatePorts(self: *Self) ?Event {
        const port_count = self.portCount();
        var result: ?Event = if (port_count != self.ports.count())
            Event.ports_updated
        else
            null;

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
            std.debug.assert(self.ports.count() == p);
            self.ports.append(Port.init(port_name.moot(), p)) catch {
                @panic("expected not a lot of ports open");
            };
        }
        return result;
    }

    pub inline fn portCount(self: *const Self) u32 {
        return c.rtmidi_get_port_count(self.rt);
    }

    // Caller needs to deinit the Shtick.
    pub fn portName(self: *Self, port: u32) Shtick {
        var buffer: [Shtick.max_count + 1]u8 = undefined;
        var name_count: c_int = @intCast(buffer.len);
        if (c.rtmidi_get_port_name(self.rt, port, &buffer, &name_count) != 0) {
            // TODO: log error
            return Shtick.unallocated("?!");
        }
        if (name_count > 0) {
            // ignore trailing zero byte.
            name_count -= 1;
        }
        return Shtick.init(buffer[0..@intCast(name_count)]) catch {
            @panic("ran out of memory for port names");
        };
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
        c.rtmidi_open_port(device, port, &buffer);
        return Self{ .name = name, .port = port, .device = device };
    }

    fn deinit(self: *Self) void {
        c.rtmidi_close_port(self.device);
        self.name.deinit();
    }

    fn notify(self: *Self) ?MidiEvent {
        // TODO
        _ = self;
        return null;
    }

    const Self = @This();
};
