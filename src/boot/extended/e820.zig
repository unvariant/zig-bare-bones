const std = @import("std");

pub const Region = packed struct {
    base: u64,
    capacity: u64,
    type: Region.Type,
    acpi: u32,

    pub const Type = enum(u32) {
        Undefined,
        Usable,
        Reserved,
        UsableACPI,
        ReservedACPI,
        Corrupt,
    };
};

pub const Error = error{};

pub const Query = struct {
    ax: u32 = 0,
    bx: u32,
    carry: bool = false,
};

pub fn query(region: *Region, prev_bx: u32) Query {
    var ax: u32 = undefined;
    var bx: u32 = undefined;
    var carry: u8 = undefined;
    var addr = @intFromPtr(region);
    var segment: u16 = @truncate(addr >> 16 << 12);
    var offset: u16 = @truncate(addr);
    asm (
        \\movw %si, %es
        \\int $0x15
        \\setc %cl
        : [a] "={eax}" (ax),
          [b] "={ebx}" (bx),
          [carry] "={cl}" (carry),
        : [func] "{eax}" (0xe820),
          [magic] "{edx}" (0x534d4150),
          [zero] "{ebx}" (prev_bx),
          [size] "{ecx}" (24),
          [segment] "{si}" (segment),
          [offset] "{di}" (offset),
        : "memory"
    );
    return .{ .ax = ax, .bx = bx, .carry = carry == 1 };
}

test "packed struct array stride" {
    const size = @bitSizeOf(Region) / 8;
    const regions: [2]Region = undefined;
    const ptrs: [*]const Region = @ptrCast(&regions);
    const stride = @intFromPtr(&ptrs[1]) - @intFromPtr(&ptrs[0]);
    try std.testing.expect(size == stride);
}

test "packed struct load semantics" {
    const addr: [*]u8 = @ptrFromInt(0x100000);
    const memory = std.os.linux.mmap(addr, 0x1000, 7, std.os.linux.MAP.ANONYMOUS | std.os.linux.MAP.PRIVATE | std.os.linux.MAP.FIXED, -1, 0);

    const ptr: *align(1) Region = @ptrFromInt(memory + 0x1000 - @bitSizeOf(Region) / 8);
    const region = ptr.*;
    try std.testing.expectEqual(region.base, 0);
}
