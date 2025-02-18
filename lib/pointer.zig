pub fn CallBorrow(comptime T: type) type {
    return struct {
        pointer: *T,
    };
}

pub fn callBorrow(pointer: anytype) CallBorrow(@typeInfo(@TypeOf(pointer)).Pointer.child) {
    return CallBorrow(@typeInfo(@TypeOf(pointer)).Pointer.child){ .pointer = pointer };
}

pub fn LifetimeBorrow(comptime T: type) type {
    return struct {
        pointer: *T,
    };
}

pub fn lifetimeBorrow(pointer: anytype) LifetimeBorrow(@typeInfo(@TypeOf(pointer)).Pointer.child) {
    return LifetimeBorrow(@typeInfo(@TypeOf(pointer)).Pointer.child){ .pointer = pointer };
}
