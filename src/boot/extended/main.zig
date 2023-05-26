const std = @import("std");
const fs = @import("fs.zig");
const term = @import("term.zig");
const disk = @import("disk.zig");

const Partitions = @import("partitions");
const Partition = Partitions.Partition;

export fn _extended_entry(drive: u8, partition: *Partition, idx: u8) linksection(".entry") callconv(.C) noreturn {
    main(drive, partition, idx) catch |err| @panic(@errorName(err));

    @panic("failed to load next stages");
}

fn main(drive: u8, partition: *Partition, idx: u8) !void {
    enable_a20();
    enable_unreal_mode();

    term.print("[+] enter extended bootloader\r\n", .{});

    term.print("[+] boot args:\r\n- drive: 0x{X:0>2}\r\n- partition: {any}\r\n- index: {}\r\n", .{ drive, partition, idx });

    fs.init(drive, partition, 0x7C00);
    var boot = try fs.open(fs.root(), "NEXT.BIN");

    var offset: u32 = 0;
    var scratch = [_]u8{0} ** 512;
    var cluster = boot.cluster();
    while (offset < boot.size) {
        var sector = cluster.sector() + partition.start_lba;

        disk.load(.{
            .sector_count = 1,
            .buffer = @ptrCast([*]u8, &scratch),
            .sector = sector,
        });

        copy(0x100000 + offset, scratch);

        cluster = cluster.next() catch |err| {
            if (err != fs.Cluster.Error.EndOfChain) {
                @panic(@errorName(err));
            } else {
                break;
            }
        };
        offset += 512;
    }

    term.print("[+] switching to bootstrap\r\n", .{});

    asm volatile ("jmp _code_16");

    @panic("failed extended bootloader\r\n");
}

pub fn panic(static: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    term.fail("[-] PANIC: {s}", .{static});
}

fn copy(dst: u32, src: [512]u8) void {
    asm volatile (
        \\.intel_syntax noprefix
        \\mov ecx, 512
        \\rep movsb [esi], [edi]
        \\.att_syntax prefix
        :
        : [_] "{esi}" (&src),
          [_] "{edi}" (dst),
        : "ecx", "esi", "edi"
    );
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
    descriptor.gdt = @ptrToInt(&gdt);
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
