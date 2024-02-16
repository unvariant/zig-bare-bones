const Disk = @import("disk.zig");

const Partition = @This();

// Offset 	Size 	Description
// 0x00 	1 byte 	Boot indicator bit flag: 0 = no, 0x80 = bootable (or "active")
// 0x01 	1 byte 	Starting head
// 0x02 	6 bits 	Starting sector (Bits 6-7 are the upper two bits for the Starting Cylinder field.)
// 0x03 	10 bits 	Starting Cylinder
// 0x04 	1 byte 	System ID
// 0x05 	1 byte 	Ending Head
// 0x06 	6 bits 	Ending Sector (Bits 6-7 are the upper two bits for the ending cylinder field)
// 0x07 	10 bits 	Ending Cylinder
// 0x08 	4 bytes 	Relative Sector (to start of partition -- also equals the partition's starting LBA value)
// 0x0C 	4 bytes 	Total Sectors in partition

active: bool,
chs_start: DiskRange,
id: u8,
chs_final: DiskRange,
lba_start: u32,
lba_count: u32,
disk: *Disk,

const DiskRange = packed struct {
    head: u8,
    sector: u6,
    cylinder: u10,
};

pub fn from(disk: *Disk, raw: *Raw) Partition {
    return .{
        .active = raw.active >> 7 == 1,
        .chs_start = @bitCast(raw.chs_start),
        .id = raw.id,
        .chs_final = @bitCast(raw.chs_final),
        .lba_start = raw.lba_start,
        .lba_count = raw.lba_count,
        .disk = disk,
    };
}

pub fn load(self: *const Partition, options: struct {
    sector_start: usize,
    sector_count: usize,
    buffer: [*]u8,
}) void {
    var sectors_left = options.sector_count;
    while (sectors_left > 0) {
        const sector_count: u16 = @min(0xff80, sectors_left);
        self.disk.load(.{
            .sector_start = self.lba_start + options.sector_start,
            .sector_count = sector_count,
            .buffer = options.buffer,
        });
        sectors_left -= sector_count;
    }
}

pub const Raw = extern struct {
    active: u8 align(1),
    chs_start: [3]u8 align(1),
    id: u8 align(1),
    chs_final: [3]u8 align(1),
    lba_start: u32 align(1),
    lba_count: u32 align(1),
};
