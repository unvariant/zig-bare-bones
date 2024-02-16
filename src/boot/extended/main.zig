const std = @import("std");
const mem = std.mem;
const Fs = @import("fs.zig");
const term = @import("term.zig");
const Disk = @import("disk.zig");
const Partition = @import("partition.zig");
const e820 = @import("e820.zig");
const allocator = @import("alloc.zig");
const vesa = @import("vesa.zig");
const RawPartition = Partition.Raw;

export fn _extended_entry(drive: u8, raw_partition: *RawPartition, idx: u8) linksection(".entry") callconv(.C) noreturn {
    term.print("[+] entered extended bootloader\r\n", .{});

    main(drive, raw_partition, idx) catch |err| @panic(@errorName(err));

    @panic("failed to load next stages");
}

fn main(drive: u8, raw_partition: *RawPartition, idx: u8) !void {
    enable_a20();
    enable_unreal_mode();

    allocator.init();

    var regions = allocator.alloc(e820.Region, 0);
    var query: e820.Query = .{ .bx = 0 };
    var i: usize = 0;
    while (true) : (i += 1) {
        regions = allocator.extend(regions, 1);

        query = e820.query(&regions[i], query.bx);

        if (query.bx == 0 or query.carry) break;
    }

    var vesa_info: vesa.Info = undefined;
    if (0x4f != vesa.Info.query(&vesa_info)) {
        @panic("failed to query vesa vbe info");
    }

    var modes: [*]u16 = @ptrFromInt(vesa_info.modes.addr());
    var vesa_mode: vesa.Mode = undefined;
    while (modes[0] != 0xffff) : (modes += 1) {
        const mode = modes[0];

        if (0x4f != vesa.Mode.query(&vesa_mode, mode)) {
            @panic("failed to query vesa mode info");
        }

        if (vesa_mode.raw.width == 640 and vesa_mode.raw.height == 480) {
            term.print("setting {d}x{d} mode\r\n", .{ vesa_mode.raw.width, vesa_mode.raw.height });
            if (0x4f != vesa_mode.set()) {
                @panic("failed to set vesa mode info");
            }
            break;
        }
    }

    if (modes[0] == 0xffff) @panic("failed to find suitable vesa mode");

    term.print("[+] enter extended bootloader\r\n", .{});

    term.print("[+] boot args:\r\n- drive: 0x{x:0>2}\r\n- partition: {}\r\n- index: {}\r\n", .{ drive, raw_partition, idx });

    var disk = Disk.new(drive);
    var partition = Partition.from(&disk, raw_partition);
    var fs = Fs.from(&partition, 0x7C00);

    var boot = try fs.root().open("NEXT.BIN");
    const kernel = @as([*]u8, @ptrFromInt(0x100000))[0..mem.alignForward(usize, boot.raw.size, 0x1000)];
    _ = try boot.reader().read(kernel);

    term.print("[+] switching to bootstrap\r\n", .{});

    // asm volatile ("jmp _code_16");

    @panic("extended bootloader should not reach here\r\n");
}

pub fn panic(static: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    term.fail("[-] PANIC: {s}", .{static});
}

//// pillaged from https://wiki.osdev.org/A20_Line
fn enable_a20() void {
    asm volatile (
        \\.intel_syntax noprefix
        \\in al, 0x92
        \\test al, 2
        \\jnz after
        \\or al, 2
        \\and al, 0xFE
        \\out 0x92, al
        \\after:
        \\.att_syntax prefix
    );
}

const Segment = packed struct {
    limit_lo: u16 = 0,
    base_lo: u24 = 0,
    accessed: bool = false,
    readwrite: bool = false,
    grows_down: bool = false,
    executable: bool = false,
    normal: bool = false,
    ring: u2 = 0,
    present: bool = false,
    limit_hi: u4 = 0,
    reserved: bool = false,
    long_mode: bool = false,
    protected_mode: bool = false,
    large: bool = false,
    base_hi: u8 = 0,
};

const Descriptor = extern struct {
    size: u16 align(1),
    gdt: u64 align(1),
};

const gdt = [3]Segment{
    .{},
    .{ .limit_lo = 0xFFFF, .limit_hi = 0, .base_lo = 0, .base_hi = 0, .readwrite = true, .grows_down = false, .executable = true, .normal = true, .ring = 0, .present = true, .large = false },
    .{ .limit_lo = 0xFFFF, .limit_hi = 0xF, .base_lo = 0, .base_hi = 0, .readwrite = true, .grows_down = false, .executable = false, .normal = true, .ring = 0, .present = true, .large = true },
};
export var descriptor = Descriptor{
    .size = @sizeOf(@TypeOf(gdt)),
    .gdt = undefined,
};

fn enable_unreal_mode() void {
    descriptor.gdt = @intFromPtr(&gdt);
    asm volatile (
        \\.intel_syntax noprefix
        \\cli
        \\push ds
        \\lgdt [esi]
        \\mov eax, cr0
        \\or al, 1
        \\mov cr0, eax
        \\.att_syntax prefix
        \\jmp $0x08, $pmode
        \\.intel_syntax noprefix
        \\pmode:
        \\mov bx, 0x10
        \\mov ds, bx
        \\and al, ~1
        \\mov cr0, eax
        \\.att_syntax prefix
        \\jmp $0x00, $unreal
        \\.intel_syntax noprefix
        \\unreal:
        \\pop ds
        \\sti
        \\.att_syntax prefix
        :
        : [desc] "{esi}" (&descriptor),
        : "eax", "bx"
    );
}
