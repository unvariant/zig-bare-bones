const std = @import("std");
const mem = std.mem;
const term = @import("term.zig");

extern const __alloc_start: usize;

var top: usize = undefined;
var prev: usize = undefined;

pub fn init() void {
    top = @intFromPtr(&__alloc_start);
    prev = top;
}

pub fn alloc(comptime T: type, n: usize) []T {
    defer top += @sizeOf(T) * n;

    const base = mem.alignForward(usize, top, @alignOf(T));
    prev = base;

    const slice: [*]T = @ptrFromInt(base);
    return slice[0..n];
}

// pub fn extend(comptime slice: anytype, n: usize) @TypeOf(slice) {
pub fn extend(slice: anytype, n: usize) @TypeOf(slice) {
    const info = @typeInfo(@TypeOf(slice));
    switch (info) {
        .Pointer => |ptr| if (ptr.size == .Slice) {
            const addr = @intFromPtr(slice.ptr);

            if (addr != prev) {
                term.print("attempt to extend slice that is not the top slice\r\n", .{});
                @panic("oops");
            }

            top += @sizeOf(info.Pointer.child) * n;

            return slice.ptr[0 .. slice.len + n];
        },
        else => {},
    }

    @compileError("argument to extend must be a slice, not " ++ @typeName(@TypeOf(slice)));
}
