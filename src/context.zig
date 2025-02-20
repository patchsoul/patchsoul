const lib = @import("lib");
const Harmony = @import("Harmony.zig");
const vaxis = @import("vaxis");

pub const Event = @import("event.zig").Event;
pub const ChildOptions = vaxis.Window.ChildOptions;
pub const Segment = vaxis.Segment;
pub const Style = vaxis.Style;

pub const Message = lib.Shtick;
pub const max_message_count = 32;
pub const Messages = lib.wrap_list.WrapList(max_message_count, Message);

pub const Windowed = struct {
    window: vaxis.Window,
    harmony: *Harmony,
    // TODO: add `loop: *vaxis.Loop(Event)` for posting events
    /// Mouse event to be handled during draw cycle.
    mouse: ?vaxis.Mouse = null,
    needs_full_redraw: bool = false,
    messages: *Messages,
    // TODO: add a `focused` argument

    pub fn drawChild(self: *Self, child: anytype, options: ChildOptions) !void {
        const restore = self.window;
        self.window = self.window.child(options);
        const result = child.draw(self);
        self.window = restore;
        return result;
    }

    const Self = @This();
};

pub const Windowless = struct {
    harmony: *Harmony,
    // TODO: add `loop: *vaxis.Loop(Event)` for posting events
    /// Mouse event to be handled during draw cycle.
    mouse: ?vaxis.Mouse = null,
    needs_full_redraw: bool = false,
    messages: *Messages,

    pub fn windowed(self: *Self, vx: *vaxis.Vaxis) Windowed {
        return Windowed{
            .window = vx.window(),
            .harmony = self.harmony,
            .mouse = self.mouse,
            .needs_full_redraw = self.needs_full_redraw,
            .messages = self.messages,
        };
    }

    const Self = @This();
};
