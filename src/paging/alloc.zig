const std = @import("std");
const mem = std.mem;

const zterm = @import("../zterm.zig");

extern const page_table_unused: usize;
extern const __page_table_memory_end: usize;

pub fn get_frame () anyerror![]u8 {
    const page_table_memory_end = @ptrToInt(&__page_table_memory_end);
    if (page_table_unused != page_table_memory_end) {
        const frame = @intToPtr([*]u8, page_table_unused)[0 .. 0x1000];
        mem.set(u8, frame, 0);
        page_table_unused += 0x1000;
        zterm.printf("frame allocated\n", .{});
        return frame;
    }
    return mem.Allocator.Error.OutOfMemory;
}