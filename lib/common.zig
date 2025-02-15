const testing = @import("testing.zig");

const std = @import("std");
const builtin = @import("builtin");

pub const debug = builtin.mode == .Debug;
pub const in_test = builtin.is_test;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub fn cleanUp() void {
    if (gpa.deinit() == .leak) {
        stderr.print("had memory leak :(\n", .{}) catch {};
    }
    stdout_data.reset();
    stderr_data.reset();
}

pub fn isLittleEndian() bool {
    return builtin.target.cpu.arch.endian() == .little;
}

pub const allocator: std.mem.Allocator = if (in_test)
    std.testing.allocator
else
    gpa.allocator();

pub const At = enum {
    start,
    end,
};

pub const Error = error{
    unknown,
    invalid_argument,
};

// TODO: ideally we wouldn't create these in non-test environments.
//       probably the best we can do is minimize the buffers internally.
var stdout_data = testing.TestWriterData{};
var stderr_data = testing.TestWriterData{};

pub var stdout = if (in_test)
    testing.TestWriter.init(&stdout_data)
else
    std.io.getStdOut().writer();

pub var stderr = if (in_test)
    testing.TestWriter.init(&stderr_data)
else
    std.io.getStdErr().writer();

pub inline fn logError(format: anytype, values: anytype) void {
    const Values = @TypeOf(values);
    if (std.meta.hasMethod(Values, "printLine")) {
        stderr.print(format, .{}) catch return;
        values.printLine(debug_stderr) catch return;
    } else {
        stderr.print(format, values) catch return;
    }
}

/// Use `stderr` for real code errors, `debug_stderr` for when debugging.
pub const debug_stderr = std.io.getStdErr().writer();

pub inline fn debugPrint(format: anytype, values: anytype) void {
    const Values = @TypeOf(values);
    if (std.meta.hasMethod(Values, "printLine")) {
        debug_stderr.print(format, .{}) catch {};
        values.printLine(debug_stderr) catch {};
    } else {
        debug_stderr.print(format, values) catch {};
    }
}

pub fn boolSlice(b: bool) []const u8 {
    return if (b) "true" else "false";
}

pub fn Found(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Optional => |optional| optional.child,
        .ErrorUnion => |error_union| error_union.payload,
        else => @compileError("should use an `Optional` or `ErrorUnion` type inside `Found`"),
    };
}

pub inline fn assert(a: anytype) Found(@TypeOf(a)) {
    return switch (@typeInfo(@TypeOf(a))) {
        .Optional => if (a) |not_null| not_null else @panic("expected `assert` argument to be non-null"),
        .ErrorUnion => a catch @panic("expected `assert` argument to not be an error"),
        else => @compileError("should use an `Optional` or `ErrorUnion` type inside `assert`"),
    };
}

pub inline fn when(a: anytype, comptime predicate: fn (Found(@TypeOf(a))) bool) bool {
    return switch (@typeInfo(@TypeOf(a))) {
        .Optional => if (a) |not_null| predicate(not_null) else false,
        .ErrorUnion => {
            const not_error = a catch return false;
            return predicate(not_error);
        },
        else => @compileError("should use an `Optional` or `ErrorUnion` type inside `when`"),
    };
}

pub fn printSlice(writer: anytype, slice: anytype) !void {
    try writer.print("[", .{});
    for (slice) |item| {
        if (std.meta.hasMethod(@TypeOf(item), "print")) {
            try item.print(writer);
            try writer.print(", ", .{});
        } else {
            try writer.print("{}, ", .{item});
        }
    }
    try writer.print("]", .{});
}

pub fn printIndexed(writer: anytype, i: usize, tab: u16) !void {
    if (i % 5 == 0) {
        for (0..tab) |_| {
            try writer.print(" ", .{});
        }
        try writer.print("// [{d}]:\n", .{i});
        for (0..tab + 4) |_| {
            try writer.print(" ", .{});
        }
    } else {
        for (0..tab + 4) |_| {
            try writer.print(" ", .{});
        }
    }
}

// Doesn't include a final `\n` here.
pub fn printSliceTabbed(writer: anytype, slice: anytype, tab: u16) !void {
    for (0..tab) |_| {
        try writer.print(" ", .{});
    }
    try writer.print("{{\n", .{});
    for (0..slice.len) |i| {
        const item = slice[i];
        try printIndexed(writer, i, tab);
        if (std.meta.hasMethod(@TypeOf(item), "printTabbed")) {
            try item.printTabbed(writer, tab + 4);
            try writer.print(",\n", .{});
        } else if (std.meta.hasMethod(@TypeOf(item), "print")) {
            try item.print(writer);
            try writer.print(",\n", .{});
        } else {
            try writer.print("{},\n", .{item});
        }
    }
    try writer.print("}}", .{});
}

pub fn printSliceLine(writer: anytype, slice: anytype) !void {
    try printSliceTabbed(writer, slice, 0);
    try writer.print("\n", .{});
}

pub fn structEqual(a: anytype, b: @TypeOf(a)) bool {
    inline for (@typeInfo(@TypeOf(a)).Struct.fields) |field_info| {
        const SubField = @TypeOf(@field(a, field_info.name));
        const equal = if (std.meta.hasMethod(SubField, "equals"))
            @field(a, field_info.name).equals(@field(b, field_info.name))
        else
            @field(a, field_info.name) == @field(b, field_info.name);
        if (!equal) {
            return false;
        }
    }
    return true;
}

pub fn taggedEqual(a: anytype, b: @TypeOf(a)) bool {
    const tag_a = std.meta.activeTag(a);
    const tag_b = std.meta.activeTag(b);
    if (tag_a != tag_b) return false;
    const Union = @typeInfo(@TypeOf(a)).Union;
    const Tag = Union.tag_type.?;
    inline for (Union.fields) |field_info| {
        if (@field(Tag, field_info.name) == tag_a) {
            const SubField = @TypeOf(@field(a, field_info.name));
            if (std.meta.hasMethod(SubField, "equals")) {
                return @field(a, field_info.name).equals(@field(b, field_info.name));
            } else {
                return @field(a, field_info.name) == @field(b, field_info.name);
            }
        }
    }
    unreachable;
}

pub fn expectEqualSlices(other: anytype, self: anytype) !void {
    errdefer {
        debug_stderr.print("expected:\n", .{}) catch {};
        printSliceLine(debug_stderr, other) catch {};

        debug_stderr.print("got:\n", .{}) catch {};
        printSliceLine(debug_stderr, self) catch {};
    }
    for (0..@min(self.len, other.len)) |index| {
        const self_item = self[index];
        const other_item = other[index];
        (if (std.meta.hasMethod(@TypeOf(self_item), "expectEquals"))
            self_item.expectEquals(other_item)
        else
            std.testing.expectEqual(other_item, self_item)) catch |e| {
            debug_stderr.print("\nnot equal at index {d}\n\n", .{index}) catch {};
            return e;
        };
    }
    // We error out "late" for equal lengths in case it's interesting
    // what's different on the inside (can help with debugging).
    try std.testing.expectEqual(other.len, self.len);
}

pub inline fn before(a: anytype) ?@TypeOf(a) {
    return back(a, 1);
}

pub inline fn back(start: anytype, amount: anytype) ?@TypeOf(start) {
    if (start >= amount) {
        return start - amount;
    }
    return null;
}

test "assert works with nullables" {
    var my_i32: ?i32 = null;
    my_i32 = 123;
    try std.testing.expectEqual(123, assert(my_i32));
}

test "assert works with error unions" {
    const Err = error{out_of_memory};
    var my_i32: Err!i32 = Err.out_of_memory;
    my_i32 = 456;
    try std.testing.expectEqual(456, assert(my_i32));
}

test "when works with nullables" {
    const Test = struct {
        fn small(value: i32) bool {
            return value < 10;
        }
        fn big(value: i32) bool {
            return value >= 10;
        }
        fn alwaysTrue(value: i32) bool {
            _ = value;
            return true;
        }
    };
    var my_i32: ?i32 = null;
    // with null:
    try std.testing.expectEqual(false, when(my_i32, Test.alwaysTrue));

    // when not null...
    my_i32 = 123;
    // ... but predicate is false:
    try std.testing.expectEqual(false, when(my_i32, Test.small));
    // ... and predicate is true:
    try std.testing.expectEqual(true, when(my_i32, Test.big));
}

test "when works with error unions" {
    const Test = struct {
        fn small(value: i32) bool {
            return value < 10;
        }
        fn big(value: i32) bool {
            return value >= 10;
        }
        fn alwaysTrue(value: i32) bool {
            _ = value;
            return true;
        }
    };
    const Err = error{out_of_memory};
    var my_i32: Err!i32 = Err.out_of_memory;
    // with an error:
    try std.testing.expectEqual(false, when(my_i32, Test.alwaysTrue));

    // when not an error...
    my_i32 = 123;
    // ... but predicate is false:
    try std.testing.expectEqual(false, when(my_i32, Test.small));
    // ... and predicate is true:
    try std.testing.expectEqual(true, when(my_i32, Test.big));
}

test "expectEqualSlices fails when different sizes" {
    try std.testing.expectError(error.TestExpectedEqual, expectEqualSlices(
        &[_]u8{ 0, 1, 2, 3 },
        &[_]u8{ 0, 1, 2, 3, 4 },
    ));
}

test "expectEqualSlices fails when different" {
    try std.testing.expectError(error.TestExpectedEqual, expectEqualSlices(
        &[_]u8{ 0, 1, 22, 3, 4 },
        &[_]u8{ 0, 1, 20, 3, 4 },
    ));
}
