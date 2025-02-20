const common = @import("common.zig");

const std = @import("std");

const MaxSizeListError = error{
    out_of_bounds,
    out_of_space,
};

// Guarantees pointer stability as long as the list itself isn't moved.
pub fn MaxSizeList(N: comptime_int, comptime T: type) type {
    return struct {
        const Self = @This();

        internal_count: usize = 0,
        array: [N]T = undefined,

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
        }

        // TODO: can we make `self` an `anytype` here and deduce the const'ness of it
        // for the return type `[]T` vs. `[]constT`?
        pub inline fn items(self: *Self) []T {
            return self.array[0..self.count()];
        }

        pub inline fn count(self: *const Self) usize {
            return self.internal_count;
        }

        /// Does not return a clone, don't deinit.
        pub inline fn inBounds(self: *const Self, index: usize) T {
            return self.array[index];
        }

        pub inline fn maybe(self: *const Self, index: usize) ?T {
            return if (index < self.count())
                self.array[index]
            else
                null;
        }

        /// Returns true if the value was present in the list.
        pub fn removeValue(self: *Self, value: T) bool {
            for (0..self.count()) |index| {
                if (common.equal(self.inBounds(index), value)) {
                    var to_deinit = self.removeIndex(index) orelse unreachable;
                    if (std.meta.hasMethod(T, "deinit")) {
                        to_deinit.deinit();
                    }
                    return true;
                }
            }
            return false;
        }

        /// Returns a value, make sure to `deinit()` it if necessary.
        pub fn removeIndex(self: *Self, index: usize) ?T {
            if (index >= self.count()) {
                return null;
            }
            const result = self.array[index];
            var i = index;
            while (i + 1 < self.count()) {
                self.array[i] = self.array[i + 1];
                i += 1;
            }
            self.internal_count -= 1;
            return result;
        }

        // Returns the value at the start of the list, make sure to `deinit()` it if necessary.
        pub inline fn shift(self: *Self) ?T {
            return self.remove(0);
        }

        // Returns the value at the end of the list, make sure to `deinit()` it if necessary.
        pub inline fn pop(self: *Self) ?T {
            const last_index = common.before(self.count()) orelse return null;
            const result = self.array[last_index];
            self.internal_count -= 1;
            return result;
        }

        /// This list will take ownership of `item`.
        pub inline fn append(self: *Self, item: T) !void {
            if (self.internal_count >= N) {
                return MaxSizeListError.out_of_space;
            }
            self.array[self.internal_count] = item;
            self.internal_count += 1;
        }

        /// This list will take ownership of all `more_items`.
        /// If the total count after adding `more_items` will be out of bounds,
        /// then we fail early (no eager appending).
        pub inline fn appendAll(self: *Self, more_items: []const T) !void {
            if (self.count() + more_items.len > N) {
                return MaxSizeListError.out_of_space;
            }
            for (more_items) |item| {
                self.array[self.internal_count] = item;
                self.internal_count += 1;
            }
        }

        pub inline fn insert(self: *Self, index: usize, item: T) !void {
            if (self.internal_count >= N) {
                return MaxSizeListError.out_of_space;
            }
            if (index > self.internal_count) {
                return MaxSizeListError.out_of_bounds;
            }
            var i = self.internal_count;
            while (i > index) {
                self.array[i] = self.array[i - 1];
                i -= 1;
            }
            self.array[index] = item;
            self.internal_count += 1;
        }

        pub inline fn clear(self: *Self) void {
            if (std.meta.hasMethod(T, "deinit")) {
                // TODO: for some reason, this doesn't work (we get a `const` cast problem;
                //      `t` appears to be a `*const T` instead of a `*T`).
                //while (self.array.popOrNull()) |*t| {
                //    t.deinit();
                //}
                while (true) {
                    var t: T = self.pop() orelse break;
                    t.deinit();
                }
            }
            self.internal_count = 0;
        }

        pub inline fn expectEquals(self: *Self, other: anytype) !void {
            try common.expectEqualIndexables(other, self);
        }

        pub inline fn printLine(self: Self, writer: anytype) !void {
            try self.print(writer);
            try writer.print("\n", .{});
        }

        // Don't include a final `\n` here.
        pub fn printTabbed(self: Self, writer: anytype, tab: u16) !void {
            try common.printIndexableTabbed(writer, self.items(), tab);
        }

        pub fn print(self: Self, writer: anytype) !void {
            try common.printIndexable(writer, self.items());
        }
    };
}

test "insert works at end" {
    var list = MaxSizeList(5, u32).init();
    defer list.deinit();

    try list.insert(0, 54);
    try list.insert(1, 55);
    try list.append(56);
    try list.insert(3, 57);

    try std.testing.expectEqualSlices(u32, list.items(), &[_]u32{ 54, 55, 56, 57 });
}

test "insert works at start" {
    var list = MaxSizeList(3, u8).init();
    defer list.deinit();

    try list.insert(0, 100);
    try list.insert(0, 101);
    try list.insert(0, 102);

    try std.testing.expectEqualSlices(u8, list.items(), &[_]u8{ 102, 101, 100 });
}

test "clear gets rid of everything" {
    const Shtick = @import("shtick.zig").Shtick;
    var list = MaxSizeList(2, Shtick).init();
    defer list.deinit();

    try list.append(try Shtick.init("over fourteen" ** 4));
    try list.append(try Shtick.init("definitely allocated" ** 10));
    try std.testing.expectEqual(2, list.count());

    list.clear();

    try std.testing.expectEqual(0, list.count());
}
