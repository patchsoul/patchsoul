pub const common = @import("common.zig");
pub const owned_list = @import("owned_list.zig");
pub const Shtick = @import("shtick.zig").Shtick;
pub const testing = @import("testing.zig");
pub const file = @import("file.zig");

const std = @import("std");

test "other dependencies (import using pub)" {
    std.testing.refAllDecls(@This());
}
