const std = @import("std");
const mem = std.mem;

const e820 = @import("e820.zig");

const Allocator = mem.Allocator;