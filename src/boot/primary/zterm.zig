const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Writer = std.io.Writer;
const pio = @import("pio.zig");
const paging = @import("paging/paging.zig");

extern const __vesa_width: u16;
extern const __vesa_height: u16;
extern const __vesa_pitch: u16;
extern const __vesa_bits_per_pixel: u8;
extern const __vesa_framebuffer: usize;
extern const __font_map: usize;

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

const default_line: usize = 1;
const default_column: usize = 1;
const default_color: TermColor = TermColor{
    .fg = Color.BrightWhite,
    .bg = Color.Black,
};

var line: usize = default_line;
var column: usize = default_column;
var width: usize = undefined;
var height: usize = undefined;
var pixels_height: usize = undefined;
var pixels_width: usize = undefined;
var pixels_per_line: usize = undefined;
var font_width: usize = 9;
var font_height: usize = 17;
var framebuffer: [*]volatile u32 = undefined;
var font_map: *[4096]u8 = undefined;
var color: TermColor = default_color;

pub const writer = Writer(void, error{}, writeFn){ .context = {} };

fn writeFn(_: void, string: []const u8) error{}!usize {
    write(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    writer.print(format, args) catch unreachable;
}

pub fn init() void {
    pixels_height = @intCast(usize, __vesa_height);
    pixels_width = @intCast(usize, __vesa_width);
    pixels_per_line = @intCast(usize, __vesa_pitch) / 4;

    width = pixels_width / font_width;
    height = pixels_height / font_height;
    framebuffer = @intToPtr([*]volatile u32, __vesa_framebuffer);
    font_map = @ptrCast([*]u8, &__font_map)[0..4096];

    const pages: usize = mem.alignForward(@intCast(usize, __vesa_pitch) * pixels_height, 0x1000) / 0x1000;
    var page: usize = 0;
    while (page < pages) : (page += 1) {
        paging.identity_map(__vesa_framebuffer + page * 0x1000);
    }

    clear();
}

pub fn line_start() void {
    var col: u16 = default_column;
    while (col < column) : (col += 1) {
        put_char_at(' ', line, col);
    }
    column = default_column;
}

pub fn clear() void {
    const size: usize = pixels_per_line * pixels_height;
    mem.set(u32, @intToPtr([*]u32, __vesa_framebuffer)[0..size], 0xFFFFFF);
}

pub fn set_color(new_color: TermColor) void {
    color = new_color;
}

fn next_line() void {
    column = default_column;
    line += 1;
    if (line >= height) {
        clear();
        line = default_line;
        column = default_column;
    }
}

fn put_char(ch: u8) void {
    if (ch == '\n') {
        next_line();
    } else {
        put_char_at(ch, line, column);
        column += 1;
        if (column >= width) {
            next_line();
        }
    }
}

fn put_char_at(ch: u8, ln: usize, col: usize) void {
    var corner = framebuffer + ln * font_height * pixels_per_line + col * font_width;
    var offset: usize = 16 * @as(usize, ch);
    var y: usize = 0;
    while (y < 16) : (y += 1) {
        var x: usize = 0;
        var byte: u8 = font_map[offset + y];
        while (x < 8) : (x += 1) {
            if ((byte & 0x80) != 0) {
                corner[x] = 0;
            } else {
                corner[x] = 0xFFFFFF;
            }
            byte <<= 1;
        }
        corner += pixels_per_line;
    }
}

fn write(chars: []const u8) void {
    for (chars) |ch| {
        put_char(ch);
    }
}
