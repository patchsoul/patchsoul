const common = @import("common.zig");

const std = @import("std");

const OwnedListError = error{
    out_of_bounds,
    out_of_memory,
};

pub fn OwnedList(comptime T: type) type {
    return struct {
        const Self = @This();

        array: std.ArrayListUnmanaged(T) = std.ArrayListUnmanaged(T){},

        pub inline fn init() Self {
            return .{};
        }

        // This will take ownership of the items.
        pub inline fn of(my_items: []const T) !Self {
            var result = Self{};
            try result.appendAll(my_items);
            return result;
        }

        pub inline fn deinit(self: *Self) void {
            if (std.meta.hasMethod(T, "deinit")) {
                self.clear();
            }
            self.array.deinit(common.allocator);
        }

        pub inline fn items(self: *const Self) []T {
            return self.array.items;
        }

        pub inline fn count(self: *const Self) usize {
            return self.array.items.len;
        }

        /// Returns a "reference" -- don't `deinit()` it.
        pub inline fn inBounds(self: *const Self, index: usize) T {
            return self.array.items[index];
        }

        pub inline fn maybe(self: *const Self, index: usize) ?T {
            return if (index < self.count())
                self.array.items[index]
            else
                null;
        }

        // Returns a value, make sure to `deinit()` it if necessary.
        pub inline fn remove(self: *Self, index: usize) ?T {
            return if (index < self.count())
                self.array.orderedRemove(index)
            else
                null;
        }

        // Returns the value at the start of the list, make sure to `deinit()` it if necessary.
        pub inline fn shift(self: *Self) ?T {
            return if (self.count() > 0)
                self.array.orderedRemove(0)
            else
                null;
        }

        // Returns the value at the end of the list, make sure to `deinit()` it if necessary.
        pub inline fn pop(self: *Self) ?T {
            const last_index = common.before(self.count()) orelse return null;
            return self.array.orderedRemove(last_index);
        }

        /// This list will take ownership of `t`.
        pub inline fn append(self: *Self, t: T) !void {
            self.array.append(common.allocator, t) catch {
                return OwnedListError.out_of_memory;
            };
        }

        /// This list will take ownership of all `items`.
        pub inline fn appendAll(self: *Self, more_items: []const T) !void {
            self.array.appendSlice(common.allocator, more_items) catch {
                return OwnedListError.out_of_memory;
            };
        }

        pub inline fn insert(self: *Self, at_index: usize, item: T) !void {
            std.debug.assert(at_index <= self.count());
            self.array.insert(common.allocator, at_index, item) catch {
                return OwnedListError.out_of_memory;
            };
        }

        pub inline fn clear(self: *Self) void {
            if (std.meta.hasMethod(T, "deinit")) {
                // TODO: for some reason, this doesn't work (we get a `const` cast problem;
                //      `t` appears to be a `*const T` instead of a `*T`).
                //while (self.array.popOrNull()) |*t| {
                //    t.deinit();
                //}
                while (true) {
                    var t: T = self.array.popOrNull() orelse break;
                    t.deinit();
                }
            } else {
                self.array.clearRetainingCapacity();
            }
        }

        pub inline fn expectEquals(self: Self, other: Self) !void {
            try self.expectEqualsSlice(other.items());
        }

        pub inline fn expectEqualsSlice(self: Self, other: []const T) !void {
            try common.expectEqualSlices(other, self.items());
        }

        pub inline fn printLine(self: Self, writer: anytype) !void {
            try self.print(writer);
            try writer.print("\n", .{});
        }

        // Don't include a final `\n` here.
        pub fn printTabbed(self: Self, writer: anytype, tab: u16) !void {
            try common.printSliceTabbed(writer, self.items(), tab);
        }

        pub fn print(self: Self, writer: anytype) !void {
            try common.printSlice(writer, self.items());
        }
    };
}

test "insert works at end" {
    var list = OwnedList(u32).init();
    defer list.deinit();

    try list.insert(0, 54);
    try list.insert(1, 55);
    try list.append(56);
    try list.insert(3, 57);

    try std.testing.expectEqualSlices(u32, list.items(), &[_]u32{ 54, 55, 56, 57 });
}

test "insert works at start" {
    var list = OwnedList(u8).init();
    defer list.deinit();

    try list.insert(0, 100);
    try list.insert(0, 101);
    try list.insert(0, 102);

    try std.testing.expectEqualSlices(u8, list.items(), &[_]u8{ 102, 101, 100 });
}

test "clear gets rid of everything" {
    const Shtick = @import("shtick.zig").Shtick;
    var list = OwnedList(Shtick).init();
    defer list.deinit();

    try list.append(try Shtick.init("over fourteen" ** 4));
    try list.append(try Shtick.init("definitely allocated" ** 10));
    try std.testing.expectEqual(2, list.count());

    list.clear();

    try std.testing.expectEqual(0, list.count());
}
