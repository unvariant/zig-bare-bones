const meta = @import("util/meta.zig");

pub fn Slice(comptime T: type) type {
    if (!meta.isPtr(T)) {
        @compileError(@typeName(T) ++ " is not a pointer");
    }

    return struct {
        const Self = @This();
        const child = T;

        base: usize,
        len: usize,

        pub fn init(ptr: anytype, len: usize) Self {
            if (@TypeOf(ptr) != T) {
                @compileError(@typeName(ptr) ++ " is not of type " ++ @typeName(T));
            }

            return .{
                .base = @intFromPtr(switch (@typeInfo(@TypeOf(ptr)).Pointer.size) {
                    .Slice => ptr.ptr,
                    else => ptr,
                }),
                .len = len,
            };
        }

        pub fn get(self: *const Self, idx: usize) T {
            if (idx >= self.len) @panic("index of out bounds");

            const elem: *align(1) T = @ptrFromInt(self.base + @bitSizeOf(T) / 8 * idx);
            return elem.*;
        }
    };
}
