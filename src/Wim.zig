const std = @import("std");
const vaxis = @import("vaxis");

/// This will reset the terminal if panics occur.
pub const panic_handler = vaxis.panic_handler;

pub const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    /// Window resize, also sent when loop begins.
    winsize: vaxis.Winsize,
};

const Wim = @This();

allocator: std.mem.Allocator,
should_quit: bool,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
/// Mouse event to be handled during draw cycle.
mouse: ?vaxis.Mouse,

pub fn init(allocator: std.mem.Allocator) !Wim {
    return .{
        .allocator = allocator,
        .should_quit = false,
        .tty = try vaxis.Tty.init(),
        .vx = try vaxis.init(allocator, .{}),
        .mouse = null,
    };
}

pub fn deinit(self: *Wim) void {
    self.vx.deinit(self.allocator, self.ttyWriter());
    self.tty.deinit();
}

pub fn run(self: *Wim) !void {
    var loop: vaxis.Loop(Event) = .{
        .tty = &self.tty,
        .vaxis = &self.vx,
    };
    try loop.init();
    try loop.start();
    try self.vx.enterAltScreen(self.ttyWriter());
    try self.vx.queryTerminal(self.ttyWriter(), 1 * std.time.ns_per_s);
    try self.vx.setMouseMode(self.ttyWriter(), true);

    while (!self.should_quit) {
        loop.pollEvent();
        while (loop.tryEvent()) |event| {
            try self.update(event);
        }

        self.draw();

        var buffered = self.tty.bufferedWriter();
        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
}

pub fn update(self: *Wim, event: Event) !void {
    switch (event) {
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true }))
                self.should_quit = true;
        },
        .mouse => |mouse| self.mouse = mouse,
        .winsize => |ws| try self.vx.resize(self.allocator, self.ttyWriter(), ws),
        else => {},
    }
}

pub fn draw(self: *Wim) void {
    const msg = "Hello, world!";

    const window = self.vx.window();

    window.clear();
    self.vx.setMouseShape(.default);

    const child = window.child(.{
        .x_off = (window.width / 2) - 7,
        .y_off = window.height / 2 + 1,
        .width = .{ .limit = msg.len },
        .height = .{ .limit = 1 },
    });

    // Mouse events are easier to handle in the draw cycle, because we can check
    // if the event occurred in the target window.
    const style: vaxis.Style = if (child.hasMouse(self.mouse)) |_| blk: {
        // We handled the mouse event, so set it to null
        self.mouse = null;
        self.vx.setMouseShape(.pointer);
        break :blk .{ .reverse = true };
    } else .{};

    _ = try child.printSegment(.{ .text = msg, .style = style }, .{});
}

fn ttyWriter(self: *Wim) std.io.AnyWriter {
    return self.tty.anyWriter();
}
