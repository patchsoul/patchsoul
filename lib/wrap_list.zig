const common = @import("common.zig");

const std = @import("std");

const WrapListError = error{
    out_of_bounds,
};

/// Doesn't allow more than `N` elements, but overwrites old ones if appending
/// more than `N` before clearing.
pub fn WrapList(N: comptime_int, comptime T: type) type {
    std.debug.assert(N > 1);
    return struct {
        const Self = @This();

        internal_start: usize = 0,
        internal_count: usize = 0,
        array: [N]T = undefined,

        pub inline fn init() Self {
            return .{};
        }

        pub inline fn deinit(self: *Self) void {
            if (std.meta.hasMethod(T, "deinit")) {
                self.clear();
            }
        }

        // This will take ownership of the items.
        pub inline fn of(my_items: []const T) Self {
            var result = Self{};
            result.appendAll(my_items);
            return result;
        }

        pub inline fn count(self: *const Self) usize {
            return self.internal_count;
        }

        inline fn internalIndex(self: *const Self, index: usize) ?usize {
            if (index >= self.internal_count) return null;
            return (self.internal_start + index) % N;
        }

        /// Does not return a clone, don't deinit.
        pub inline fn inBounds(self: *const Self, index: usize) T {
            return self.array[self.internalIndex(index) orelse unreachable];
        }

        pub inline fn maybe(self: *const Self, index: usize) ?T {
            const internal_index = self.internalIndex(index) orelse return null;
            return self.array[internal_index];
        }

        /// Returns true if the value was present in the list.
        pub fn removeValue(self: *Self, value: T) bool {
            for (0..self.count()) |external_index| {
                const internal_index = (self.start_index + external_index) % N;
                if (common.equal(self.array[internal_index], value)) {
                    var to_deinit = self.removeInternalIndex(internal_index, external_index);
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
            const internal_index = self.internalIndex(index) orelse return null;
            return self.removeInternalIndex(internal_index, index);
        }

        pub fn removeInternalIndex(self: *Self, internal_index: usize, external_index: usize) T {
            std.debug.assert(external_index < self.count());
            const result = self.array[internal_index];
            // if count == 5
            //            external_index: 0, 1, 2, 3, 4
            //      count-external_index: 5, 4, 3, 2, 1
            // if count == 4
            //            external_index: 0, 1, 2, 3
            //      count-external_index: 4, 3, 2, 1
            // Bias towards deleting towards the end.
            if (external_index + 1 >= self.internal_count - external_index) {
                // Delete "upwards":
                var i = external_index;
                while (i + 1 < self.count()) {
                    self.array[(self.internal_start + i) % N] = self.array[
                        (self.internal_start + i + 1) % N
                    ];
                    i += 1;
                }
            } else {
                // Delete "downwards".  -1 == +(N - 1) mod N, to avoid a negative usize.
                var i = external_index;
                while (i > 0) {
                    self.array[(self.internal_start + i) % N] = self.array[
                        (self.internal_start + i + (N - 1)) % N
                    ];
                    i -= 1;
                }
                self.internal_start += 1;
            }
            self.internal_count -= 1;
            return result;
        }

        // Returns the value at the end of the list, make sure to `deinit()` it if necessary.
        pub inline fn pop(self: *Self) ?T {
            const last_index = common.before(self.count()) orelse return null;
            const internal_index = (self.internal_start + last_index) % N;
            const result = self.array[internal_index];
            self.internal_count -= 1;
            return result;
        }

        /// This list will take ownership of `item`.
        /// If attempting to add more than N items, it will wrap around and remove the first one
        /// before adding this one.
        pub inline fn append(self: *Self, item: T) void {
            if (self.count() >= N) {
                const internal_index = self.internal_start;
                var to_deinit = self.array[internal_index];
                if (std.meta.hasMethod(T, "deinit")) {
                    to_deinit.deinit();
                }
                self.array[internal_index] = item;
                self.internal_start = (internal_index + 1) % N;
            } else {
                self.array[(self.internal_start + self.internal_count) % N] = item;
                self.internal_count += 1;
            }
        }

        /// This list will take ownership of all `more_items`.
        /// This is a thin wrapper around `append`, so it won't do anything smart
        /// if `more_items.len >= N`.
        pub inline fn appendAll(self: *Self, more_items: []const T) void {
            for (more_items) |item| {
                self.append(item);
            }
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
            self.internal_start = 0;
            self.internal_count = 0;
        }

        pub inline fn expectEquals(self: *Self, other: anytype) !void {
            try common.expectEqualIndexables(other, self);
        }

        pub inline fn printLine(self: *Self, writer: anytype) !void {
            try self.print(writer);
            try writer.print("\n", .{});
        }

        // Don't include a final `\n` here.
        pub fn printTabbed(self: *Self, writer: anytype, tab: u16) !void {
            try common.printIndexableTabbed(writer, self.items(), tab);
        }

        pub fn print(self: *Self, writer: anytype) !void {
            try common.printIndexable(writer, self.items());
        }
    };
}

test "append wraps around" {
    var list = WrapList(5, u32).init();
    defer list.deinit();

    list.append(56);
    list.append(57);
    list.append(58);
    list.append(59);
    try list.expectEquals(&[_]u32{
        56,
        57,
        58,
        59,
    });

    list.append(60);
    try list.expectEquals(&[_]u32{
        56,
        57,
        58,
        59,
        60,
    });

    list.append(61);
    try list.expectEquals(&[_]u32{
        57,
        58,
        59,
        60,
        61,
    });
}

test "append wraps around and deinits old if necessary" {
    // Use a `Shtick` in order to make sure allocations are freed.
    const Shtick = @import("shtick.zig").Shtick;
    var list = WrapList(2, Shtick).init();
    defer list.deinit();
    try std.testing.expectEqual(0, list.count());

    list.append(try Shtick.init("over fourteen" ** 4));
    list.append(try Shtick.init("definitely allocated" ** 3));
    try std.testing.expectEqual(2, list.count());
    try list.expectEquals(&[_][]const u8{
        "over fourteenover fourteenover fourteenover fourteen",
        "definitely allocateddefinitely allocateddefinitely allocated",
    });

    list.append(try Shtick.init("still going to be allocated for sure"));
    try std.testing.expectEqual(2, list.count());
    try list.expectEquals(&[_][]const u8{
        "definitely allocateddefinitely allocateddefinitely allocated",
        "still going to be allocated for sure",
    });

    list.append(Shtick.unallocated("ok"));
    try std.testing.expectEqual(2, list.count());
    try list.expectEquals(&[_][]const u8{
        "still going to be allocated for sure",
        "ok",
    });
}

test "clear gets rid of everything" {
    // Use a `Shtick` in order to make sure allocations are freed.
    const Shtick = @import("shtick.zig").Shtick;
    var list = WrapList(2, Shtick).init();
    defer list.deinit();

    list.append(try Shtick.init("over fourteen" ** 4));
    list.append(try Shtick.init("definitely allocated" ** 10));
    try std.testing.expectEqual(2, list.count());

    list.clear();

    try std.testing.expectEqual(0, list.count());
}
