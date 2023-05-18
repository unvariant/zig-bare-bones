const mem = @import("std").mem;

// # Extended Bios Data Area
// | address | bytes | value
// |---------|-------|-------
// | 0x40E   | 2     | base address of EBDA >> 4
// | 0x413   | 2     | offset (in KiB) after EDBA base address to usable EBDA memory

fn access(comptime T: type, addr: usize) T {
    return @intToPtr(*align(1) volatile T, addr).*;
}

fn base_addr() usize {
    return @intCast(usize, access(u16, 0x40E)) << 4;
}

fn len() usize {
    return 0xA0000 - base_addr();
}

pub fn memory() []u8 {
    const ebda = base_addr();
    return @intToPtr([*]u8, ebda)[0..len()];
}

pub fn search_for_rdsp() ?usize {
    const rdsp_signature: []const u8 = "RSD PTR";
    const ebda = memory();

    if (mem.indexOf(u8, ebda, rdsp_signature)) |idx| {
        return @ptrToInt(ebda.ptr + idx);
    } else {
        return null;
    }
}
