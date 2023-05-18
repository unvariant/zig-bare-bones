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
    e820.init();
    term.init();

    rsdt.parse();

    alloc.map(0xFFFFFF0000, e820.regions[1].base);
    const buf = @intToPtr([*]u8, 0xFFFFFF0000)[0..0x1000];
    @memset(buf, 0);

    // asm volatile (
    //     \\.intel_syntax noprefix
    //     \\cli
    //     \\.att_syntax prefix
    // );
    // _ = @intToPtr(* volatile u8, 0x8000000).*;

    @panic("halted execution.");
}

extern const __debug_info_lo: usize;
extern const __debug_info_hi: usize;
extern const __debug_abbrev_lo: usize;
extern const __debug_abbrev_hi: usize;
extern const __debug_str_lo: usize;
extern const __debug_str_hi: usize;
extern const __debug_str_offsets_lo: usize;
extern const __debug_str_offsets_hi: usize;
extern const __debug_line_lo: usize;
extern const __debug_line_hi: usize;
extern const __debug_line_str_lo: usize;
extern const __debug_line_str_hi: usize;
extern const __debug_ranges_lo: usize;
extern const __debug_ranges_hi: usize;
extern const __debug_loclists_lo: usize;
extern const __debug_loclists_hi: usize;
extern const __debug_rnglists_lo: usize;
extern const __debug_rnglists_hi: usize;
extern const __debug_addr_lo: usize;
extern const __debug_addr_hi: usize;
extern const __debug_names_lo: usize;
extern const __debug_names_hi: usize;
extern const __debug_frame_lo: usize;
extern const __debug_frame_hi: usize;

fn sect(lo: *const usize, hi: *const usize) []const u8 {
    const base = @ptrToInt(lo);
    const len = @ptrToInt(hi) - base;
    return @ptrCast([*]const u8, lo)[0..len];
}

pub fn panic(message: []const u8, stack_trace: ?*builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_trace;
    _ = ret_addr;

    var heap: [10 * 1024]u8 = undefined;
    var manager = std.heap.FixedBufferAllocator.init(&heap);
    var allocator = manager.allocator();

    var dwarf_info = std.dwarf.DwarfInfo{
        .endian = .Little,
        .debug_info = sect(&__debug_info_lo, &__debug_info_hi),
        .debug_abbrev = sect(&__debug_abbrev_lo, &__debug_abbrev_hi),
        .debug_str = sect(&__debug_str_lo, &__debug_str_hi),
        .debug_str_offsets = sect(&__debug_str_offsets_lo, &__debug_str_offsets_hi),
        .debug_line = sect(&__debug_line_lo, &__debug_line_hi),
        .debug_line_str = sect(&__debug_line_str_lo, &__debug_line_str_hi),
        .debug_ranges = sect(&__debug_ranges_lo, &__debug_ranges_hi),
        .debug_loclists = sect(&__debug_loclists_lo, &__debug_loclists_hi),
        .debug_rnglists = sect(&__debug_rnglists_lo, &__debug_rnglists_hi),
        .debug_addr = sect(&__debug_addr_lo, &__debug_addr_hi),
        .debug_names = sect(&__debug_names_lo, &__debug_names_hi),
        .debug_frame = sect(&__debug_frame_lo, &__debug_frame_hi),
    };
    std.dwarf.openDwarfDebugInfo(&dwarf_info, allocator) catch |err| {
        term.printf("panic failed: {s}\n", .{@errorName(err)});
        hang();
    };

    var it = std.debug.StackIterator.init(@returnAddress(), null);
    while (it.next()) |rt| {
        var unit = dwarf_info.findCompileUnit(rt) catch |err| {
            term.printf("panic failed: {s}\n", .{@errorName(err)});
            hang();
        };
        var line_info = dwarf_info.getLineNumberInfo(allocator, unit.*, rt) catch |err| {
            term.printf("panic failed: {s}\n", .{@errorName(err)});
            hang();
        };
        var sym_name = dwarf_info.getSymbolName(rt);
        printLineInfo(
            term.writer,
            line_info,
            rt,
            sym_name orelse "???",
            "???",
            .no_color,
        ) catch |err| {
            term.printf("panic failed: {s}\n", .{@errorName(err)});
            hang();
        };
    }

    term.set_color(term.TermColor{
        .fg = term.Color.BrightYellow,
        .bg = term.Color.Black,
    });
    term.printf("\n!KERNEL PANIC!: {s}", .{message});

    hang();
}

const source_files = [_][]const u8{
    "src/main.zig",
};

fn printLineInfo(
    out_stream: anytype,
    line_info: ?std.debug.LineInfo,
    address: usize,
    symbol_name: []const u8,
    compile_unit_name: []const u8,
    tty_config: std.debug.TTY.Config,
) !void {
    nosuspend {
        try tty_config.setColor(out_stream, .Bold);

        if (line_info) |*li| {
            try out_stream.print("{s}:{d}:{d}", .{ li.file_name, li.line, li.column });
        } else {
            try out_stream.writeAll("???:?:?");
        }

        try tty_config.setColor(out_stream, .Reset);
        try out_stream.writeAll(": ");
        try tty_config.setColor(out_stream, .Dim);
        try out_stream.print("0x{x} in {s} ({s})", .{ address, symbol_name, compile_unit_name });
        try tty_config.setColor(out_stream, .Reset);
        try out_stream.writeAll("\n");

        // Show the matching source code line if possible

        if (line_info) |li| {
            if (printLineFromFile(out_stream, li)) {
                if (li.column > 0) {
                    // The caret already takes one char

                    const space_needed = @intCast(usize, li.column - 1);

                    try out_stream.writeByteNTimes(' ', space_needed);
                    try tty_config.setColor(out_stream, .Green);
                    try out_stream.writeAll("^");
                    try tty_config.setColor(out_stream, .Reset);
                }
                try out_stream.writeAll("\n");
            } else |err| switch (err) {
                error.EndOfFile, error.FileNotFound => {},
                error.BadPathName => {},
                error.AccessDenied => {},
                else => return err,
            }
        }
    }
}

fn printLineFromFile(stdout: anytype, line_info: std.debug.LineInfo) anyerror!void {
    inline for (source_files) |src_path| {
        if (std.mem.endsWith(u8, line_info.file_name, src_path)) {
            const contents = @embedFile("../" ++ src_path);
            var lines = mem.split(u8, contents, "\n");
            for (0..line_info.line) |_| {
                _ = lines.next();
            }
            try stdout.print("{any}\n", .{lines.next()});
            return;
        }
    }
    try stdout.print("(source file {s} not added in std/debug.zig)\n", .{line_info.file_name});
}

pub fn hang() noreturn {
    while (true) {}
}
