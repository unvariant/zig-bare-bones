const std = @import("std");
const fmt = std.fmt;
const Writer = std.io.Writer;
const pio = @import("pio.zig");
const paging = @import("paging/paging.zig");

pub const Color = enum(u4) {
    Black,
    Blue,
    Green,
    Cyan,
    Red,
    Magenta,
    Yellow,
    White,
    BrightBlack,
    BrightBlue,
    BrightGreen,
    BrightCyan,
    BrightRed,
    BrightMagenta,
    BrightYellow,
    BrightWhite,
};

pub const TermColor = packed struct {
    fg: Color,
    bg: Color,
};

const TermChar = packed struct {
    inner: u8,
    color: TermColor,
};

const default_line: u8 = 0;
const default_column: u8 = 0;
const default_color: TermColor = TermColor{
    .fg = Color.BrightWhite,
    .bg = Color.Black,
};

var line: u16 = default_line;
var column: u16 = default_column;
var width: u16 = 80;
var height: u16 = 25;
var cursor_enabled = true;
const vga: [*]volatile TermChar = @intToPtr([*]volatile TermChar, 0xB8000);
var color: TermColor = default_color;

pub const writer = Writer(void, error{}, writeFn){ .context = {} };

fn writeFn(_: void, string: []const u8) error{}!usize {
    write(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    writer.print(format, args) catch unreachable;
}

extern const vesa_width: u16;
extern const vesa_height: u16;
extern const vesa_pitch: u16;
extern const vesa_bits_per_pixel: u8;
extern const vesa_framebuffer: usize;
extern const __font_map: usize;

pub fn init() void {
    if (cursor_enabled) {
        enable_cursor();
        set_cursor(0, 0);
    } else {
        disable_cursor();
    }
    clear();

    const pixels_height = @intCast(usize, vesa_height);
    const pixels_width = @intCast(usize, vesa_width);
    const pixels_per_line = pixels_width;

    const pages: usize = pixels_per_line * pixels_height * 4 / 0x1000;
    var page: usize = 0;
    while (page < pages) : (page += 1) {
        paging.identity_map(vesa_framebuffer + page * 0x1000);
    }
}

pub fn line_start() void {
    var cols = @intCast(i16, column);
    while (cols >= 0) {
        put_char_at(' ', line, @intCast(u16, cols));
        cols -= 1;
    }
    column = 0;
}

pub fn clear() void {
    const empty = TermChar{
        .inner = ' ',
        .color = color,
    };

    var idx: u16 = 0;
    var all: u16 = width * height;
    while (idx < all) : ({
        idx += 1;
    }) {
        vga[idx] = empty;
    }
}

pub fn enable_cursor() void {
    cursor_enabled = true;
    pio.out8(0x3D4, 0x0A);
    pio.out8(0x3D5, (pio.in8(0x3D5) & 0xC0) | 15);

    pio.out8(0x3D4, 0x0B);
    pio.out8(0x3D5, (pio.in8(0x3D5) & 0xE0) | 15);
}

pub fn disable_cursor() void {
    cursor_enabled = false;
    pio.out8(0x3D4, 0x0A);
    pio.out8(0x3D5, 0x20);
}

pub fn set_cursor(tgt_line: u16, tgt_column: u16) void {
    const pos: u16 = tgt_line * width + tgt_column;
    const lo: u8 = @intCast(u8, pos & 0xFF);
    const hi: u8 = @intCast(u8, (pos >> 8) & 0xFF);

    pio.out8(0x3D4, 0x0F);
    pio.out8(0x3D5, lo);
    pio.out8(0x3D4, 0x0E);
    pio.out8(0x3D5, hi);
}

pub fn update_cursor() void {
    if (cursor_enabled) {
        set_cursor(line, column);
    }
}

pub fn set_color(new_color: TermColor) void {
    color = new_color;
}

pub fn next_line() void {
    column = default_column;
    line += 1;
    if (line >= height) {
        clear();
        line = default_line;
        column = default_column;
    }
}

pub fn put_char(ch: u8) void {
    if (ch == '\n') {
        next_line();
    } else {
        vga[line * width + column] = TermChar{
            .inner = ch,
            .color = color,
        };
        column += 1;
        if (column >= width) {
            next_line();
        }
    }
}

pub fn put_char_at(ch: u8, ln: u16, col: u16) void {
    vga[ln * width + col] = TermChar{
        .inner = ch,
        .color = color,
    };
}

pub fn write(chars: []const u8) void {
    for (chars) |ch| {
        put_char(ch);
    }
    update_cursor();
}
