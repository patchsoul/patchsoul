const common = @import("common.zig");

const std = @import("std");

// TODO: make ShtickN(i16), (i32), (i64)
// with corresponding local capacities of 14 bytes (16 bytes total local bytes)
// 20 bytes (24 bytes total), and 24 bytes (32 bytes), respectively.
pub const Shtick = extern struct {
    pub const Error = error{
        string_too_long,
        out_of_memory,
    };
    pub const max_count: usize = -std.math.minInt(i16);
    pub const max_unallocated_count: usize = @sizeOf(Self) - @sizeOf(i16);

    // The sign (optional +1) indicates whether we're allocated (or not).
    // If <= 0, then negate it for the actual count of the allocated Shtick.
    // If > 0, subtract one to get the actual count of the unallocated Shtick.
    special_count: i16 = 1,
    start: [4]u8 = undefined,
    middle: extern union {
        capacity: u16,
        if_unallocated: [2]u8,
    } = undefined,
    end: extern union {
        pointer: *u8,
        if_unallocated: [8]u8,
    } = undefined,

    pub fn count(self: *const Self) usize {
        if (self.isAllocated()) {
            return @intCast(-(self.special_count + 1) + 1);
        } else {
            return @intCast(self.special_count - 1);
        }
    }

    inline fn setUnallocatedCountUnchecked(self: *Self, new_count: usize) void {
        std.debug.assert(new_count <= max_unallocated_count);
        self.special_count = @intCast(new_count + 1);
    }

    inline fn setAllocatedCountUnchecked(self: *Self, new_count: usize) void {
        std.debug.assert(new_count <= max_count);
        const count32: i32 = @intCast(new_count);
        self.special_count = @intCast(-count32);
    }

    inline fn setCountUnchecked(self: *Self, new_count: usize) void {
        if (self.isAllocated()) {
            self.setAllocatedCountUnchecked(new_count);
        } else {
            self.setUnallocatedCountUnchecked(new_count);
        }
    }

    pub inline fn isAllocated(self: *const Self) bool {
        return self.special_count <= 0;
    }

    pub inline fn isUnallocated(self: *const Self) bool {
        return self.special_count > 0;
    }

    pub fn deinit(self: *Self) void {
        if (self.isAllocated()) {
            common.allocator.free(self.buffer());
        }
        self.special_count = 1;
    }

    pub fn moot(self: *Self) Self {
        const new_shtick = self.*;
        self.* = Self{};
        return new_shtick;
    }

    pub fn init(chars: []const u8) !Self {
        var shtick = try Self.withCapacity(chars.len);
        @memcpy(shtick.buffer()[0..chars.len], chars);
        shtick.setCountUnchecked(chars.len);
        return shtick;
    }

    pub fn copyFrom(self: *Self, other: Self) !void {
        try self.copyFromSlice(other.slice());
    }

    pub fn copyFromSlice(self: *Self, chars: []const u8) !void {
        if (self.capacity() < chars.len) {
            try self.setCapacity(chars.len);
        }
        @memcpy(self.buffer()[0..chars.len], chars);
        self.setCountUnchecked(chars.len);
    }

    /// Initializes a `Shtick` that is just on the stack (no allocations on the heap).
    /// For compile-time-known `chars` only.  For anything else, prefer `init` and
    /// just defer `deinit` to be safe.  If you ever do `self.copyFrom` with the shtick
    /// returned here, or any other capacity-modifying methods, you should defer `deinit`.
    pub inline fn unallocated(chars: anytype) Self {
        // We're expecting `chars` to be `*const [n:0]u8` with n <= max_unallocated_count
        if (chars.len > max_unallocated_count) {
            @compileError(std.fmt.comptimePrint("Shtick.unallocated must have {d} characters or less", .{max_unallocated_count}));
        }
        return Self.init(chars) catch unreachable;
    }

    pub inline fn capacity(self: *const Self) usize {
        if (self.isAllocated()) {
            return self.capacityAllocated();
        }
        return max_unallocated_count;
    }

    /// Unchecked as to whether we're really allocated.
    fn capacityAllocated(self: *const Self) usize {
        return self.middle.capacity;
    }

    pub fn setCapacity(self: *Self, new_capacity: usize) !void {
        const old_count = self.count();
        const new_count = @min(old_count, new_capacity);
        if (new_capacity <= max_unallocated_count) {
            // Should make this Shtick unallocated.
            if (self.isAllocated()) {
                var old_buffer = self.buffer();
                defer common.allocator.free(old_buffer);
                @memcpy(self.bufferUnallocated()[0..new_count], old_buffer[0..new_count]);
            }
            self.setUnallocatedCountUnchecked(new_count);
        } else {
            // This Shtick will need to be allocated.
            const old_capacity = self.capacityAllocated();
            if (new_capacity == old_capacity) {
                return;
            }
            // Avoid destroying invariants: allocate first in case we have problems.
            // This will throw if new_capacity > max_count.
            const new_pointer = try allocate(new_capacity);
            if (self.isAllocated()) {
                var old_buffer = self.bufferAllocated();
                defer common.allocator.free(old_buffer);
                @memcpy(maxBuffer(new_pointer, new_capacity)[0..new_count], old_buffer[0..new_count]);
            } else {
                var old_buffer = self.bufferUnallocated();
                @memcpy(maxBuffer(new_pointer, new_capacity)[0..new_count], old_buffer[0..new_count]);
            }
            self.middle.capacity = @intCast(new_capacity);
            self.end.pointer = new_pointer;
            self.setAllocatedCountUnchecked(new_count);
        }
    }

    pub fn withCapacity(starting_capacity: anytype) !Self {
        if (starting_capacity <= max_unallocated_count) {
            return .{};
        }
        var shtick = Self{ .special_count = 0 };
        const pointer = try allocate(starting_capacity);
        shtick.middle.capacity = @intCast(starting_capacity);
        shtick.end.pointer = @ptrCast(pointer);
        return shtick;
    }

    fn allocate(starting_capacity: usize) !*u8 {
        if (starting_capacity > max_count) {
            return Error.string_too_long;
        }
        const heap = common.allocator.alloc(u8, starting_capacity) catch {
            std.debug.print("couldn't allocate {d}-character Shtick...\n", .{starting_capacity});
            return Error.out_of_memory;
        };
        return @ptrCast(heap.ptr);
    }

    /// Only use at start of shtick creation.
    inline fn buffer(self: *Self) []u8 {
        if (self.isUnallocated()) {
            return self.bufferUnallocated();
        } else {
            return self.bufferAllocated();
        }
    }

    /// Doesn't do any checks.
    fn bufferUnallocated(self: *Self) []u8 {
        const current_capacity = max_unallocated_count;
        const full_small_buffer: *[current_capacity]u8 = @ptrCast(&self.start[0]);
        return full_small_buffer[0..current_capacity];
    }

    fn bufferAllocated(self: *Self) []u8 {
        return maxBuffer(self.end.pointer, self.middle.capacity);
    }

    fn maxBuffer(pointer: *u8, max_capacity: usize) []u8 {
        const full_buffer: *[Self.max_count]u8 = @ptrCast(pointer);
        return full_buffer[0..max_capacity];
    }

    pub fn slice(self: *const Self) []const u8 {
        if (self.isUnallocated()) {
            const current_capacity = max_unallocated_count;
            const full_small_buffer: *const [current_capacity]u8 = @ptrCast(&self.start[0]);
            return full_small_buffer[0..self.count()];
        } else {
            const full_buffer: *const [Self.max_count]u8 = @ptrCast(self.end.pointer);
            return full_buffer[0..self.count()];
        }
    }

    pub const PascalCase = enum {
        keep_starting_case, // lower_case -> lowerCase, Upper_case -> UpperCase
        start_lower, // Upper_case -> upperCase, lower_case -> lowerCase
        start_upper, // Upper_case -> UpperCase, lower_case -> LowerCase

        fn transform(self: PascalCase, char: u8, at_start: bool) u8 {
            if (!at_start) return char;

            return switch (self) {
                .keep_starting_case => char,
                .start_lower => uncapitalize(char),
                .start_upper => capitalize(char),
            };
        }
    };

    pub fn toPascalCase(self: *const Self, case: PascalCase) !Self {
        if (self.count() == 0) {
            return Self{};
        }
        var work_buffer: [32768]u8 = undefined;
        var index: usize = 0;
        var capitalize_next = false;
        var at_start = true;
        for (self.slice()) |char| if (char == '_') {
            capitalize_next = true;
        } else {
            const modified_char = if (capitalize_next) capitalize(char) else char;
            capitalize_next = false;
            work_buffer[index] = case.transform(modified_char, at_start);
            at_start = false;
            index += 1;
        };
        return Self.init(work_buffer[0..index]);
    }

    pub const SnakeCase = enum {
        start_lower, // LowerSnakeCase -> lower_snake_case
        start_upper, // initialUpperSnakeCase -> Initial_upper_snake_case
        /// Like `keep_starting_case`, this case doesn't force the initial char to be
        /// "capitalized" or "uncapitalized".
        no_uppers, // Upper_case -> _upper_case
        keep_starting_case, // keepLower -> keep_lower or KeepUpper -> Keep_upper, _prefix_ok -> _prefix_ok

        // Since SnakeCase can add chars (e.g., myPascal -> my_pascal), return
        // up to two chars in a u16, little-endian style.  (First char is (result & 255)
        // and second char is (result >> 8).)
        fn transform(self: SnakeCase, char: u8, at_start: bool, saw_underscore: bool) u16 {
            return switch (self) {
                .start_lower => transformStartLower(char, at_start),
                .start_upper => transformStartUpper(char, at_start),
                .no_uppers => transformNoUppers(char, at_start),
                .keep_starting_case => transformKeepStartingCase(char, at_start, saw_underscore),
            };
        }

        inline fn transformStartLower(char: u8, at_start: bool) u16 {
            if (!isCapital(char)) {
                return char;
            } else if (at_start) {
                return uncapitalize(char);
            } else {
                return underscoreChar(char);
            }
        }

        inline fn transformStartUpper(char: u8, at_start: bool) u16 {
            if (at_start) {
                return capitalize(char);
            } else if (!isCapital(char)) {
                return char;
            } else {
                return underscoreChar(char);
            }
        }

        inline fn transformNoUppers(char: u8, at_start: bool) u16 {
            _ = at_start;
            if (!isCapital(char)) {
                return char;
            } else {
                return underscoreChar(char);
            }
        }

        inline fn transformKeepStartingCase(char: u8, at_start: bool, saw_underscore: bool) u16 {
            if ((at_start and !saw_underscore) or !isCapital(char)) {
                return char;
            } else {
                return underscoreChar(char);
            }
        }

        inline fn underscoreChar(char: u8) u16 {
            const char16: u16 = uncapitalize(char);
            return '_' | (char16 << 8);
        }
    };

    pub fn toSnakeCase(self: *const Self, case: SnakeCase) !Self {
        var work_buffer: [32768]u8 = undefined;
        var index: usize = 0;
        // If the shtick has an underscore before the next letter.
        var underscore_next = false;
        var at_start = true; // until we see a non-underscore character.
        for (self.slice()) |char| {
            if (char == '_') {
                underscore_next = true;
                continue;
            }
            // We'll pretend to capitalize after an underscore, but then transform
            // it back as needed in `case.transform`.
            const modified_char = if (underscore_next) capitalize(char) else char;
            const sequence16 = case.transform(modified_char, at_start, underscore_next);
            underscore_next = false;
            at_start = false;
            if (index >= work_buffer.len) {
                return Error.string_too_long;
            }
            work_buffer[index] = @intCast(sequence16 & 255);
            const next_char: u8 = @intCast(sequence16 >> 8);
            index += 1;

            if (next_char == 0) continue;

            if (index >= work_buffer.len) {
                return Error.string_too_long;
            }
            work_buffer[index] = uncapitalize(next_char);
            index += 1;
        }
        return Self.init(work_buffer[0..index]);
    }

    pub fn contains(self: Self, message: []const u8, where: common.At) bool {
        const self_count = self.count();
        if (self_count < message.len) {
            return false;
        }
        return switch (where) {
            common.At.start => std.mem.eql(u8, self.slice()[0..message.len], message),
            common.At.end => std.mem.eql(u8, self.slice()[self_count - message.len .. self_count], message),
        };
    }

    pub inline fn printLine(self: *const Self, writer: anytype) !void {
        try writer.print("{s}\n", .{self.slice()});
    }

    pub inline fn print(self: *const Self, writer: anytype) !void {
        try writer.print("{s}", .{self.slice()});
    }

    pub fn equals(self: Self, other: Self) bool {
        if (self.count() != other.count()) {
            return false;
        }
        return std.mem.eql(u8, self.slice(), other.slice());
    }

    pub fn expectEquals(a: Self, b: Self) !void {
        const equal = a.equals(b);
        if (!equal) {
            std.debug.print("expected {s}, got {s}\n", .{ b.slice(), a.slice() });
        }
        try std.testing.expect(equal);
    }

    pub fn expectNotEquals(a: Self, b: Self) !void {
        const equal = a.equals(b);
        if (equal) {
            std.debug.print("expected {s} to NOT equal {s}\n", .{ a.slice(), b.slice() });
        }
        try std.testing.expect(!equal);
    }

    pub fn expectEqualsSlice(self: Self, other_slice: []const u8) !void {
        try std.testing.expectEqualStrings(other_slice, self.slice());
    }

    pub inline fn isUncapital(char: u8) bool {
        return char >= 'a' and char <= 'z';
    }

    pub inline fn capitalize(char: u8) u8 {
        return if (isUncapital(char))
            char - 32
        else
            char;
    }

    pub inline fn isCapital(char: u8) bool {
        return char >= 'A' and char <= 'Z';
    }

    pub inline fn uncapitalize(char: u8) u8 {
        return if (isCapital(char))
            char + 32
        else
            char;
    }

    const Self = @This();
};

test "Shtick size is correct" {
    try std.testing.expectEqual(16, @sizeOf(Shtick));
    const shtick: Shtick = .{};
    try std.testing.expectEqual(2, @sizeOf(@TypeOf(shtick.special_count)));
    try std.testing.expectEqual(4, @sizeOf(@TypeOf(shtick.start)));
    try std.testing.expectEqual(2, @sizeOf(@TypeOf(shtick.middle)));
    try std.testing.expectEqual(8, @sizeOf(@TypeOf(shtick.end)));
    try std.testing.expectEqual(14, Shtick.max_unallocated_count);
    // TODO: check for `shtick.end.pointer` being at +8 from start of shtick
    // try std.testing.expectEqual(8, @typeInfo(@TypeOf(shtick.end.pointer)).Pointer.alignment);
}

test "too large of a shtick" {
    try std.testing.expectError(Shtick.Error.string_too_long, Shtick.init("g" ** (Shtick.max_count + 1)));
}

test "unallocated works" {
    try std.testing.expectEqualStrings("this is ok man", Shtick.unallocated("this is ok man").slice());
}

test "slice works for large shticks" {
    var shtick = try Shtick.init("Thumb thunk rink?");
    defer shtick.deinit();

    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(false, shtick.isUnallocated());
    try common.expectEqualSlices(shtick.slice(), "Thumb thunk rink?");
}

test "slice works for short shticks" {
    var shtick = try Shtick.init("Thumb 123");
    defer shtick.deinit();

    try std.testing.expectEqual(false, shtick.isAllocated());
    try std.testing.expectEqual(true, shtick.isUnallocated());
    try common.expectEqualSlices(shtick.slice(), "Thumb 123");
}

test "unallocated copyFrom long allocated works" {
    var shtick = Shtick.unallocated("asdf");
    defer shtick.deinit();

    var source = try Shtick.withCapacity(100);
    defer source.deinit();
    const source_str = "this is pretty big well maybe not but bigger than 14 and less than 100";
    try source.copyFromSlice(source_str);
    try source.expectEqualsSlice(source_str);
    try std.testing.expectEqual(true, source.isAllocated());
    try std.testing.expectEqual(100, source.capacity());
    try std.testing.expectEqual(70, source.count());

    try shtick.copyFrom(source);
    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(70, shtick.capacity());
    try std.testing.expectEqual(70, shtick.count());
    try shtick.expectEquals(source);
}

test "unallocated copyFrom short allocated works" {
    var shtick = Shtick.unallocated("hjkl;");
    defer shtick.deinit();

    var source = try Shtick.withCapacity(125);
    defer source.deinit();
    const source_str = "abc";
    try source.copyFromSlice(source_str);
    try source.expectEqualsSlice(source_str);
    try std.testing.expectEqual(true, source.isAllocated());
    try std.testing.expectEqual(125, source.capacity());
    try std.testing.expectEqual(3, source.count());

    try shtick.copyFrom(source);
    try std.testing.expectEqual(false, shtick.isAllocated());
    try std.testing.expectEqual(14, shtick.capacity());
    try std.testing.expectEqual(3, shtick.count());
    try shtick.expectEquals(source);
}

test "short allocated copyFrom unallocated works" {
    var shtick = try Shtick.withCapacity(75);
    try shtick.copyFromSlice("under 14");
    defer shtick.deinit();

    const source = Shtick.unallocated("wxyz");
    try std.testing.expectEqual(14, source.capacity());
    try std.testing.expectEqual(4, source.count());

    try shtick.copyFrom(source);
    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(75, shtick.capacity());
    try std.testing.expectEqual(4, shtick.count());
    try shtick.expectEquals(source);
}

test "long allocated copyFrom unallocated works" {
    var shtick = try Shtick.withCapacity(49);
    try shtick.copyFromSlice("this is great and over 14");
    defer shtick.deinit();

    const source = Shtick.unallocated("is under 14");
    try std.testing.expectEqual(14, source.capacity());
    try std.testing.expectEqual(11, source.count());

    try shtick.copyFrom(source);
    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(49, shtick.capacity());
    try std.testing.expectEqual(11, shtick.count());
    try shtick.expectEquals(source);
}

test "unallocated copyFromSlice shorter unallocated" {
    var shtick = Shtick.unallocated("llllll123");

    try shtick.copyFromSlice("abc");

    try std.testing.expectEqual(false, shtick.isAllocated());
    try std.testing.expectEqual(14, shtick.capacity());
    try std.testing.expectEqual(3, shtick.count());
    try shtick.expectEqualsSlice("abc");
}

test "unallocated copyFromSlice longer unallocated" {
    var shtick = Shtick.unallocated("123lmn");
    const source_str = "abcdefghijklmn";

    try shtick.copyFromSlice(source_str);

    try std.testing.expectEqual(false, shtick.isAllocated());
    try std.testing.expectEqual(14, shtick.capacity());
    try std.testing.expectEqual(14, shtick.count());
    try shtick.expectEqualsSlice(source_str);
}

test "allocated copyFromSlice longer needing to increase capacity" {
    var shtick = try Shtick.init("this is long but not as long");
    defer shtick.deinit();
    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(28, shtick.capacity());
    try std.testing.expectEqual(28, shtick.count());

    const source_str = "this is longer and will need to increase capacity!";
    try shtick.copyFromSlice(source_str);

    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(50, shtick.capacity());
    try std.testing.expectEqual(50, shtick.count());
    try shtick.expectEqualsSlice(source_str);
}

test "allocated copyFromSlice longer without changing capacity" {
    var shtick = try Shtick.withCapacity(100);
    defer shtick.deinit();
    try shtick.copyFromSlice("this is long but not as long");

    const source_str = "this is longer and should be wow you know!";
    try shtick.copyFromSlice(source_str);

    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(100, shtick.capacity()); // doesn't change
    try std.testing.expectEqual(42, shtick.count());
    try shtick.expectEqualsSlice(source_str);
}

test "allocated copyFromSlice shorter" {
    var shtick = try Shtick.withCapacity(100);
    defer shtick.deinit();
    try shtick.copyFromSlice("this is long but not as long");

    const source_str = "this is shorter.";
    try shtick.copyFromSlice(source_str);

    try shtick.copyFromSlice(source_str);
    try std.testing.expectEqual(true, shtick.isAllocated());
    try std.testing.expectEqual(100, shtick.capacity()); // doesn't change
    try std.testing.expectEqual(16, shtick.count());
    try shtick.expectEqualsSlice(source_str);
}

test "copies all bytes of short shtick" {
    // This is mostly just me verifying how zig does memory.
    // We want shtick copies to be safe.  Note that the address
    // of `shtick.slice()` may change if copied, e.g., for
    // `unallocated` shticks.
    var shtick_src = Shtick.unallocated("0123456789abcd");
    shtick_src.setUnallocatedCountUnchecked(5);

    const shtick_dst = shtick_src;
    shtick_src.setUnallocatedCountUnchecked(14);

    for (shtick_src.buffer()) |*c| {
        c.* += 10;
    }
    try shtick_src.expectEquals(Shtick.unallocated(":;<=>?@ABCklmn"));
    try shtick_dst.expectEquals(Shtick.unallocated("01234"));
}

test "contains At.start for long shtick" {
    var shtick = try Shtick.init("long shtick should test this as well");
    defer shtick.deinit();

    try std.testing.expect(shtick.contains("lon", common.At.start));
    try std.testing.expect(shtick.contains("long shtick should tes", common.At.start));
    try std.testing.expect(shtick.contains("long shtick should test this as well", common.At.start));

    try std.testing.expect(!shtick.contains("long shtick should test this as well!", common.At.start));
    try std.testing.expect(!shtick.contains("short shtick", common.At.start));
    try std.testing.expect(!shtick.contains("shtick", common.At.start));
}

test "contains At.start for short shtick" {
    const shtick = Shtick.unallocated("short shtick!");

    try std.testing.expect(shtick.contains("shor", common.At.start));
    try std.testing.expect(shtick.contains("short shti", common.At.start));
    try std.testing.expect(shtick.contains("short shtick!", common.At.start));

    try std.testing.expect(!shtick.contains("short shtick!?", common.At.start));
    try std.testing.expect(!shtick.contains("long shtick", common.At.start));
    try std.testing.expect(!shtick.contains("shtick", common.At.start));
}

test "contains At.end for long shtick" {
    var shtick = try Shtick.init("long shtick should test this as well");
    defer shtick.deinit();

    try std.testing.expect(shtick.contains("ell", common.At.end));
    try std.testing.expect(shtick.contains("is as well", common.At.end));
    try std.testing.expect(shtick.contains("long shtick should test this as well", common.At.end));

    try std.testing.expect(!shtick.contains("a long shtick should test this as well", common.At.end));
    try std.testing.expect(!shtick.contains("not well", common.At.end));
    try std.testing.expect(!shtick.contains("well!", common.At.end));
}

test "contains At.end for short shtick" {
    const shtick = Shtick.unallocated("short shtick!");

    try std.testing.expect(shtick.contains("ick!", common.At.end));
    try std.testing.expect(shtick.contains("shtick!", common.At.end));
    try std.testing.expect(shtick.contains("short shtick!", common.At.end));

    try std.testing.expect(!shtick.contains("1 short shtick!", common.At.end));
    try std.testing.expect(!shtick.contains("long shtick!", common.At.end));
    try std.testing.expect(!shtick.contains("shtick", common.At.end));
}

test "non-allocked String.toPascalCase start_upper works" {
    try (try Shtick.unallocated("_hi_you__a!@").toPascalCase(.start_upper)).expectEqualsSlice("HiYouA!@");
    try (try Shtick.unallocated("hey_jamboree_").toPascalCase(.start_upper)).expectEqualsSlice("HeyJamboree");
    try (try Shtick.unallocated("___ohNo").toPascalCase(.start_upper)).expectEqualsSlice("OhNo");
    try (try Shtick.unallocated("!$eleven#:").toPascalCase(.start_upper)).expectEqualsSlice("!$eleven#:");
    try (try Shtick.unallocated("a_b_c___d___e").toPascalCase(.start_upper)).expectEqualsSlice("ABCDE");
    try (try Shtick.unallocated("_____").toPascalCase(.start_upper)).expectEqualsSlice("");
    try (try Shtick.unallocated("AlreadyCased").toPascalCase(.start_upper)).expectEqualsSlice("AlreadyCased");
    try (try Shtick.unallocated("almostCased").toPascalCase(.start_upper)).expectEqualsSlice("AlmostCased");
}

test "non-allocked String.toPascalCase start_lower works" {
    try (try Shtick.unallocated("_hi_you__a!@").toPascalCase(.start_lower)).expectEqualsSlice("hiYouA!@");
    try (try Shtick.unallocated("hey_jamboree_").toPascalCase(.start_lower)).expectEqualsSlice("heyJamboree");
    try (try Shtick.unallocated("___ohNo").toPascalCase(.start_lower)).expectEqualsSlice("ohNo");
    try (try Shtick.unallocated("!$eleven#:").toPascalCase(.start_lower)).expectEqualsSlice("!$eleven#:");
    try (try Shtick.unallocated("a_b_c___d___e").toPascalCase(.start_lower)).expectEqualsSlice("aBCDE");
    try (try Shtick.unallocated("_____").toPascalCase(.start_upper)).expectEqualsSlice("");
    try (try Shtick.unallocated("alreadyCased").toPascalCase(.start_lower)).expectEqualsSlice("alreadyCased");
    try (try Shtick.unallocated("AlmostCased").toPascalCase(.start_lower)).expectEqualsSlice("almostCased");
}

test "non-allocked String.toPascalCase keep_starting_case works" {
    try (try Shtick.unallocated("_hi_you__a!@").toPascalCase(.keep_starting_case)).expectEqualsSlice("HiYouA!@");
    try (try Shtick.unallocated("hey_jamboree_").toPascalCase(.keep_starting_case)).expectEqualsSlice("heyJamboree");
    try (try Shtick.unallocated("___ohNo").toPascalCase(.keep_starting_case)).expectEqualsSlice("OhNo");
    try (try Shtick.unallocated("!$eleven#:").toPascalCase(.keep_starting_case)).expectEqualsSlice("!$eleven#:");
    try (try Shtick.unallocated("a_b_c___d___e").toPascalCase(.keep_starting_case)).expectEqualsSlice("aBCDE");
    try (try Shtick.unallocated("_____").toPascalCase(.keep_starting_case)).expectEqualsSlice("");
    try (try Shtick.unallocated("alreadyCased").toPascalCase(.keep_starting_case)).expectEqualsSlice("alreadyCased");
    try (try Shtick.unallocated("AlsoCased").toPascalCase(.keep_starting_case)).expectEqualsSlice("AlsoCased");
}

test "non-allocked String.toSnakeCase start_lower works" {
    try (try Shtick.unallocated("HiYouA!@").toSnakeCase(.start_lower)).expectEqualsSlice("hi_you_a!@");
    try (try Shtick.unallocated("HeyJamboree").toSnakeCase(.start_lower)).expectEqualsSlice("hey_jamboree");
    try (try Shtick.unallocated("OhNo").toSnakeCase(.start_lower)).expectEqualsSlice("oh_no");
    try (try Shtick.unallocated("!$eleven#:").toSnakeCase(.start_lower)).expectEqualsSlice("!$eleven#:");
    try (try Shtick.unallocated("aBCDE").toSnakeCase(.start_lower)).expectEqualsSlice("a_b_c_d_e");
    try (try Shtick.unallocated("_____").toSnakeCase(.start_lower)).expectEqualsSlice("");
    try (try Shtick.unallocated("lower_cased").toSnakeCase(.start_lower)).expectEqualsSlice("lower_cased");
    try (try Shtick.unallocated("Upper_cased").toSnakeCase(.start_lower)).expectEqualsSlice("upper_cased");
    try (try Shtick.unallocated("_prefix_cased").toSnakeCase(.start_lower)).expectEqualsSlice("prefix_cased");
    try (try Shtick.unallocated("___super_pix").toSnakeCase(.start_lower)).expectEqualsSlice("super_pix");
}

test "non-allocked String.toSnakeCase start_upper works" {
    try (try Shtick.unallocated("HiYouA!@").toSnakeCase(.start_upper)).expectEqualsSlice("Hi_you_a!@");
    try (try Shtick.unallocated("HeyJamboree").toSnakeCase(.start_upper)).expectEqualsSlice("Hey_jamboree");
    try (try Shtick.unallocated("OhNo").toSnakeCase(.start_upper)).expectEqualsSlice("Oh_no");
    try (try Shtick.unallocated("!$eleven#:").toSnakeCase(.start_upper)).expectEqualsSlice("!$eleven#:");
    try (try Shtick.unallocated("aBCDE").toSnakeCase(.start_upper)).expectEqualsSlice("A_b_c_d_e");
    try (try Shtick.unallocated("_____").toSnakeCase(.start_upper)).expectEqualsSlice("");
    try (try Shtick.unallocated("lower_cased").toSnakeCase(.start_upper)).expectEqualsSlice("Lower_cased");
    try (try Shtick.unallocated("Upper_cased").toSnakeCase(.start_upper)).expectEqualsSlice("Upper_cased");
    try (try Shtick.unallocated("_prefix_cased").toSnakeCase(.start_upper)).expectEqualsSlice("Prefix_cased");
    try (try Shtick.unallocated("___super_pix").toSnakeCase(.start_upper)).expectEqualsSlice("Super_pix");
}

test "non-allocked String.toSnakeCase no_uppers works" {
    try (try Shtick.unallocated("HiYouA!@").toSnakeCase(.no_uppers)).expectEqualsSlice("_hi_you_a!@");
    try (try Shtick.unallocated("HeyJamboree").toSnakeCase(.no_uppers)).expectEqualsSlice("_hey_jamboree");
    try (try Shtick.unallocated("OhNo").toSnakeCase(.no_uppers)).expectEqualsSlice("_oh_no");
    try (try Shtick.unallocated("!$eleven#:").toSnakeCase(.no_uppers)).expectEqualsSlice("!$eleven#:");
    try (try Shtick.unallocated("aBCDE").toSnakeCase(.no_uppers)).expectEqualsSlice("a_b_c_d_e");
    try (try Shtick.unallocated("_____").toSnakeCase(.no_uppers)).expectEqualsSlice("");
    try (try Shtick.unallocated("lower_cased").toSnakeCase(.no_uppers)).expectEqualsSlice("lower_cased");
    try (try Shtick.unallocated("Upper_cased").toSnakeCase(.no_uppers)).expectEqualsSlice("_upper_cased");
    try (try Shtick.unallocated("_prefix_cased").toSnakeCase(.no_uppers)).expectEqualsSlice("_prefix_cased");
    try (try Shtick.unallocated("___super_pix").toSnakeCase(.no_uppers)).expectEqualsSlice("_super_pix");
}

test "non-allocked String.toSnakeCase keep_starting_case works" {
    try (try Shtick.unallocated("HiYouA!@").toSnakeCase(.keep_starting_case)).expectEqualsSlice("Hi_you_a!@");
    try (try Shtick.unallocated("HeyJamboree").toSnakeCase(.keep_starting_case)).expectEqualsSlice("Hey_jamboree");
    try (try Shtick.unallocated("OhNo").toSnakeCase(.keep_starting_case)).expectEqualsSlice("Oh_no");
    try (try Shtick.unallocated("!$eleven#:").toSnakeCase(.keep_starting_case)).expectEqualsSlice("!$eleven#:");
    try (try Shtick.unallocated("aBCDE").toSnakeCase(.keep_starting_case)).expectEqualsSlice("a_b_c_d_e");
    try (try Shtick.unallocated("_____").toSnakeCase(.keep_starting_case)).expectEqualsSlice("");
    try (try Shtick.unallocated("lower_cased").toSnakeCase(.keep_starting_case)).expectEqualsSlice("lower_cased");
    try (try Shtick.unallocated("Upper_cased").toSnakeCase(.keep_starting_case)).expectEqualsSlice("Upper_cased");
    try (try Shtick.unallocated("_prefix_cased").toSnakeCase(.keep_starting_case)).expectEqualsSlice("_prefix_cased");
    try (try Shtick.unallocated("___super_pix").toSnakeCase(.keep_starting_case)).expectEqualsSlice("_super_pix");
}

test "equals works for unallocated shticks" {
    const empty_shtick: Shtick = .{};
    try std.testing.expectEqual(true, empty_shtick.equals(Shtick.unallocated("")));

    const shtick1 = Shtick.unallocated("hi");
    const shtick2 = Shtick.unallocated("hi");
    try std.testing.expectEqual(true, shtick1.equals(shtick2));
    try std.testing.expectEqualStrings("hi", shtick1.slice());
    try shtick1.expectEquals(shtick2);

    const shtick3 = Shtick.unallocated("hI");
    try std.testing.expectEqual(false, shtick1.equals(shtick3));
    try shtick1.expectNotEquals(shtick3);

    var shtick4 = try Shtick.init("hi this is going to be more than 16 characters");
    defer shtick4.deinit();
    try std.testing.expectEqual(false, shtick1.equals(shtick4));
    try shtick1.expectNotEquals(shtick4);
}

test "equals works for large shticks" {
    var shtick1 = try Shtick.init("hello world this is over 16 characters");
    defer shtick1.deinit();
    var shtick2 = try Shtick.init("hello world this is over 16 characters");
    defer shtick2.deinit();
    try std.testing.expectEqual(true, shtick1.equals(shtick2));
    try std.testing.expectEqualStrings("hello world this is over 16 characters", shtick1.slice());
    try shtick1.expectEquals(shtick2);

    var shtick3 = try Shtick.init("hello world THIS is over 16 characters");
    defer shtick3.deinit();
    try std.testing.expectEqual(false, shtick1.equals(shtick3));
    try shtick1.expectNotEquals(shtick3);

    const shtick4 = Shtick.unallocated("hello");
    try std.testing.expectEqual(false, shtick1.equals(shtick4));
    try shtick1.expectNotEquals(shtick4);
}
