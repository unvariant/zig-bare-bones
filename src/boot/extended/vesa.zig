const std = @import("std");
const arch = @import("arch");
const util = @import("util");

pub const Info = extern struct {
    signature: [4]u8 align(1), // == "VESA"
    version: u16 align(1), // == 0x0300 for VBE 3.0
    oem: arch.FarPtr align(1),
    capabilities: [4]u8 align(1),
    modes: arch.FarPtr align(1),
    blocks: u16 align(1), // as # of 64KB blocks
    reversed: [492]u8 align(1),

    const Self = @This();

    pub fn query(self: *Self) u32 {
        var status: u32 = undefined;
        var ptr = arch.FarPtr.from(@intFromPtr(self));
        asm (
            \\movw %si, %es
            \\int $0x10
            : [status] "={eax}" (status),
            : [magic] "{eax}" (0x4f00),
              [offset] "{di}" (ptr.offset),
              [segment] "{si}" (ptr.segment),
            : "memory"
        );
        return status;
    }

    pub fn len(self: Self) usize {
        return self.blocks * 64 * 1024;
    }
};

pub const Mode = packed struct {
    const Raw = packed struct {
        attributes: u16,
        window_a: u8,
        window_b: u8,
        granularity: u16,
        window_size: u16,
        segment_a: u16,
        segment_b: u16,
        win_func_ptr: u32,
        pitch: u16,
        width: u16,
        height: u16,
        w_char: u8,
        y_char: u8,
        planes: u8,
        bpp: u8,
        banks: u8,
        memory_model: u8,
        bank_size: u8,
        image_pages: u8,
        reserved0: u8,
        red_mask: u8,
        red_position: u8,
        green_mask: u8,
        green_position: u8,
        blue_mask: u8,
        blue_position: u8,
        reserved_mask: u8,
        reserved_position: u8,
        direct_color_attributes: u8,
        framebuffer: u32,
        off_screen_mem_off: u32,
        off_screen_mem_size: u16,
        reserved1: util.u(206 * 8),
    };

    raw: Raw,
    mode: u16,

    const Self = @This();

    pub fn query(self: *Self, mode: u16) u32 {
        var status: u32 = undefined;
        var ptr = arch.FarPtr.from(@intFromPtr(self));
        asm (
            \\movw %si, %es
            \\int $0x10
            : [status] "={eax}" (status),
            : [magic] "{eax}" (0x4f01),
              [mode] "{ecx}" (mode),
              [offset] "{di}" (ptr.offset),
              [segment] "{si}" (ptr.segment),
            : "memory"
        );
        self.mode = mode;
        return status;
    }

    pub fn set(self: Self) u32 {
        var status: u32 = undefined;
        asm (
            \\int $0x10
            : [status] "={eax}" (status),
            : [magic] "{eax}" (0x4f02),
              [mode] "{ebx}" (self.mode),
            : "memory"
        );
        return status;
    }
};

comptime {
    if (@sizeOf(Info) != @bitSizeOf(Info) / 8) {
        @compileError("size mismatch between reported byte size and bit size");
    }
    if (@sizeOf(Info) != 512) {
        @compileError("VBE struct should be 512 bytes long");
    }

    if (@sizeOf(Mode.Raw) != @bitSizeOf(Mode.Raw) / 8) {
        @compileError("size mismatch between reported byte size and bit size");
    }
    if (@sizeOf(Mode.Raw) != 256) {
        @compileError("Mode struct should be 256 bytes long");
    }
}
