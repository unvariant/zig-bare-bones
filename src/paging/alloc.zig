const std = @import("std");
const mem = std.mem;

const term = @import("../zterm.zig");

extern const page_table_unused: usize;
extern const __page_table_memory_end: usize;

pub fn get_frame() anyerror![]u8 {
    const page_table_memory_end = @ptrToInt(&__page_table_memory_end);
    if (page_table_unused != page_table_memory_end) {
        const frame = @intToPtr([*]u8, page_table_unused)[0..0x1000];
        @memset(frame, 0);
        page_table_unused += 0x1000;
        //term.printf("page frame allocated\n", .{});
        return frame;
    } else {
        //term.printf("unable to allocate page frame", .{});
    }
    return mem.Allocator.Error.OutOfMemory;
}
