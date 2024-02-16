pub fn SliceChildType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Pointer => |ptr| if (ptr.size == .Slice) ptr.child else @compileError("pointer type " ++ @typeName(T) ++ " is not a slice"),
        else => @compileError("invalid pointer type " ++ @typeName(T)),
    };
}

pub fn isPtr(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Pointer => true,
        else => false,
    };
}
