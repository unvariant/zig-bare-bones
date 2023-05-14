const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const term = @import("../zterm.zig");

const LinkedList = packed struct {
    physaddr: usize,
    // total size of the section
    capacity: usize,
    // pointer to next free section of memory
    next: ?*LinkedList,
};

var free_pages: ?*LinkedList = null;