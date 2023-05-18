const fs = @import("fs.zig");

const Partitions = @import("partitions");
const Partition = Partitions.Partition;

pub fn _extended_entry(drive: u8, partition: *Partition, idx: u8) linksection(".entry") callconv(.C) noreturn {
    _ = drive;
    _ = partition;
    _ = idx;

    fail("[+] enter extended bootsector\r\n");
}

fn fail(static: []const u8) noreturn {
    print(static);
    while (true) {}
}

fn print(static: []const u8) void {
    for (static) |ch| {
        putchar(ch);
    }
}

fn putchar(ch: u8) void {
    asm volatile (
        \\xor %bx,   %bx
        \\int $0x10
        :
        //// mov $imm, %ax
        //// is slightly shorter than
        //// mov $imm, %ah
        //// mov $imm, %al
        : [info] "{al}" (0x0E00 | @as(u16, ch)),
        : "bx"
    );
}
