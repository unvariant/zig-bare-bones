const std = @import("std");
const mem = std.mem;
const elf = std.elf;
const builtin = std.builtin;
const e820 = @import("e820.zig");
const term = @import("zterm.zig");
const atapio = @import("atapio.zig");
const pic = @import("pic.zig");
const idt = @import("idt.zig");
const ebda = @import("ebda.zig");
const rsdp = @import("rsdp.zig");
const rsdt = @import("rsdt.zig");
const paging = @import("paging/paging.zig");

extern const vesa_framebuffer: usize;
extern const vesa_width: u16;
extern const vesa_height: u16;
extern const vesa_pitch: u16;
extern const vesa_bits_per_pixel: u8;
extern const vesa_off_screen_offset: u32;
extern const vesa_off_screen_size: u16;

extern const __font_map: usize;

export fn _start() callconv(.C) noreturn {
    pic.init();
    idt.fill_table();
    idt.load();
    term.init();

    rsdt.parse();

    // asm volatile (
    //     \\.intel_syntax noprefix
    //     \\cli
    //     \\.att_syntax prefix
    // );
    // _ = @intToPtr(* volatile u8, 0x8000000).*;

    @panic("halted execution.");
}

pub fn panic(message: []const u8, stack_trace: ?*builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_trace;
    _ = ret_addr;

    term.set_color(term.TermColor{
        .fg = term.Color.BrightYellow,
        .bg = term.Color.Black,
    });
    term.printf("\n!KERNEL PANIC!: {s}", .{message});

    hang();
}

pub fn hang() noreturn {
    while (true) {}
}
