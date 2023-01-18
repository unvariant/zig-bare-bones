const std = @import("std");
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

extern const __kernel_size: usize;
extern const __kernel_image: usize;

export fn _start() callconv(.C) noreturn {
    pic.init();
    term.init();

    idt.fill_table();
    idt.load();

    rsdt.parse();

    const kernel_size = @ptrToInt(&__kernel_size);
    const kernel_image = @ptrCast(*const align(@alignOf(elf.Elf64_Ehdr)) [@sizeOf(elf.Elf64_Ehdr)]u8, &__kernel_image);

    term.printf("kernel size: {x}h\n", .{kernel_size});
    term.printf("kernel address: {x}h\n", .{@ptrToInt(kernel_image)});

    const hdr = elf.Header.parse(kernel_image) catch |err| @panic(@errorName(err));
    term.printf("kernel elf header: {}\n", .{hdr});

    asm volatile (
        \\.intel_syntax noprefix
        \\int 0x40
        \\int 0x87
        \\cli
        \\.att_syntax prefix
    );

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
