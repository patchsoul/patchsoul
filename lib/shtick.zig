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
    pub const max_unallocated_count: usize = getMaxUnallocatedCount();

    fn getMaxUnallocatedCount() comptime_int {
        return @sizeOf(Self) - @sizeOf(i16);
    }

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
        const new_string = *self;
        self.* = Self{};
        return new_string;
    }

    pub fn init(chars: []const u8) !Self {
        var string = try Self.withCapacity(chars.len);
        @memcpy(string.buffer()[0..chars.len], chars);
        string.setCountUnchecked(chars.len);
        return string;
    }

    /// Initializes a `Shtick` that is just on the stack (no allocations on the heap).
    /// For compile-time-known `chars` only.  For anything else, prefer `init` and
    /// just defer `deinit` to be safe.
    pub inline fn unallocated(chars: anytype) Self {
        // We're expecting `chars` to be `*const [n:0]u8` with n <= getMaxUnallocatedCount()
        if (chars.len > comptime getMaxUnallocatedCount()) {
            @compileError(std.fmt.comptimePrint("Shtick.unallocated must have {d} characters or less", .{getMaxUnallocatedCount()}));
        }
        return Self.init(chars) catch unreachable;
    }

    pub fn withCapacity(capacity: anytype) !Self {
        if (capacity > max_count) {
            return Error.string_too_long;
        }
        if (capacity <= comptime getMaxUnallocatedCount()) {
            return .{};
        }
        var shtick = Self{ .special_count = 0 };
        const heap = common.allocator.alloc(u8, capacity) catch {
            std.debug.print("couldn't allocate {d}-character string...\n", .{capacity});
            return Error.out_of_memory;
        };
        shtick.middle.capacity = @intCast(capacity);
        shtick.end.pointer = @ptrCast(heap.ptr);
        return shtick;
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
        // If the string has an underscore before the next letter.
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

    /// Only use at start of string creation.
    fn buffer(self: *Self) []u8 {
        if (self.isUnallocated()) {
            const capacity = comptime getMaxUnallocatedCount();
            const full_small_buffer: *[capacity]u8 = @ptrCast(&self.start[0]);
            return full_small_buffer[0..capacity];
        } else {
            const full_buffer: *[Self.max_count]u8 = @ptrCast(self.end.pointer);
            return full_buffer[0..self.middle.capacity];
        }
    }

    pub fn slice(self: *const Self) []const u8 {
        if (self.isUnallocated()) {
            const capacity = comptime getMaxUnallocatedCount();
            const full_small_buffer: *const [capacity]u8 = @ptrCast(&self.start[0]);
            return full_small_buffer[0..self.count()];
        } else {
            const full_buffer: *const [Self.max_count]u8 = @ptrCast(self.end.pointer);
            return full_buffer[0..self.count()];
        }
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
    try std.testing.expectEqual(14, Shtick.getMaxUnallocatedCount());
    // TODO: check for `shtick.end.pointer` being at +8 from start of shtick
    // try std.testing.expectEqual(8, @typeInfo(@TypeOf(shtick.end.pointer)).Pointer.alignment);
}

test "unallocated works" {
    try std.testing.expectEqualStrings("this is ok man", Shtick.unallocated("this is ok man").slice());
}

test "equals works for unallocated strings" {
    const empty_string: Shtick = .{};
    try std.testing.expectEqual(true, empty_string.equals(Shtick.unallocated("")));

    const string1 = Shtick.unallocated("hi");
    const string2 = Shtick.unallocated("hi");
    try std.testing.expectEqual(true, string1.equals(string2));
    try std.testing.expectEqualStrings("hi", string1.slice());
    try string1.expectEquals(string2);

    const string3 = Shtick.unallocated("hI");
    try std.testing.expectEqual(false, string1.equals(string3));
    try string1.expectNotEquals(string3);

    var string4 = try Shtick.init("hi this is going to be more than 16 characters");
    defer string4.deinit();
    try std.testing.expectEqual(false, string1.equals(string4));
    try string1.expectNotEquals(string4);
}

test "equals works for large shticks" {
    var string1 = try Shtick.init("hello world this is over 16 characters");
    defer string1.deinit();
    var string2 = try Shtick.init("hello world this is over 16 characters");
    defer string2.deinit();
    try std.testing.expectEqual(true, string1.equals(string2));
    try std.testing.expectEqualStrings("hello world this is over 16 characters", string1.slice());
    try string1.expectEquals(string2);

    var string3 = try Shtick.init("hello world THIS is over 16 characters");
    defer string3.deinit();
    try std.testing.expectEqual(false, string1.equals(string3));
    try string1.expectNotEquals(string3);

    const string4 = Shtick.unallocated("hello");
    try std.testing.expectEqual(false, string1.equals(string4));
    try string1.expectNotEquals(string4);
}

test "slice works for large shticks" {
    var string = try Shtick.init("Thumb thunk rink?");
    defer string.deinit();

    try std.testing.expectEqual(true, string.isAllocated());
    try std.testing.expectEqual(false, string.isUnallocated());
    try common.expectEqualSlices(string.slice(), "Thumb thunk rink?");
}

test "slice works for short shticks" {
    var string = try Shtick.init("Thumb 123");
    defer string.deinit();

    try std.testing.expectEqual(false, string.isAllocated());
    try std.testing.expectEqual(true, string.isUnallocated());
    try common.expectEqualSlices(string.slice(), "Thumb 123");
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

test "too large of a string" {
    try std.testing.expectError(Shtick.Error.string_too_long, Shtick.init("g" ** (Shtick.max_count + 1)));
}

test "copies all bytes of short string" {
    // This is mostly just me verifying how zig does memory.
    // We want string copies to be safe.  Note that the address
    // of `string.slice()` may change if copied, e.g., for
    // `unallocated` strings.
    var string_src = Shtick.unallocated("0123456789abcd");
    string_src.setUnallocatedCountUnchecked(5);

    const string_dst = string_src;
    string_src.setUnallocatedCountUnchecked(14);

    for (string_src.buffer()) |*c| {
        c.* += 10;
    }
    try string_src.expectEquals(Shtick.unallocated(":;<=>?@ABCklmn"));
    try string_dst.expectEquals(Shtick.unallocated("01234"));
}

test "contains At.start for long string" {
    var string = try Shtick.init("long string should test this as well");
    defer string.deinit();

    try std.testing.expect(string.contains("lon", common.At.start));
    try std.testing.expect(string.contains("long string should tes", common.At.start));
    try std.testing.expect(string.contains("long string should test this as well", common.At.start));

    try std.testing.expect(!string.contains("long string should test this as well!", common.At.start));
    try std.testing.expect(!string.contains("short string", common.At.start));
    try std.testing.expect(!string.contains("string", common.At.start));
}

test "contains At.start for short string" {
    const string = Shtick.unallocated("short string!");

    try std.testing.expect(string.contains("shor", common.At.start));
    try std.testing.expect(string.contains("short strin", common.At.start));
    try std.testing.expect(string.contains("short string!", common.At.start));

    try std.testing.expect(!string.contains("short string!?", common.At.start));
    try std.testing.expect(!string.contains("long string", common.At.start));
    try std.testing.expect(!string.contains("string", common.At.start));
}

test "contains At.end for long string" {
    var string = try Shtick.init("long string should test this as well");
    defer string.deinit();

    try std.testing.expect(string.contains("ell", common.At.end));
    try std.testing.expect(string.contains("is as well", common.At.end));
    try std.testing.expect(string.contains("long string should test this as well", common.At.end));

    try std.testing.expect(!string.contains("a long string should test this as well", common.At.end));
    try std.testing.expect(!string.contains("not well", common.At.end));
    try std.testing.expect(!string.contains("well!", common.At.end));
}

test "contains At.end for short string" {
    const string = Shtick.unallocated("short string!");

    try std.testing.expect(string.contains("ing!", common.At.end));
    try std.testing.expect(string.contains("string!", common.At.end));
    try std.testing.expect(string.contains("short string!", common.At.end));

    try std.testing.expect(!string.contains("1 short string!", common.At.end));
    try std.testing.expect(!string.contains("long string!", common.At.end));
    try std.testing.expect(!string.contains("string", common.At.end));
}
