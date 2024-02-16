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
const alloc = @import("alloc.zig");
const SymbolHack = @import("symbol-hack.zig");

export fn _start() callconv(.C) noreturn {
    _ = SymbolHack;

    pic.init();
    idt.fill_table();
    idt.load();
    e820.init();
    term.init();

    rsdt.parse();

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
