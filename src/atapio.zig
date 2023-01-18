const pio = @import("pio.zig");

const ATA = struct {
    const io_base = 0x1F0;
    const READ = 0x20;

    pub fn read28(buffer: [*]volatile u8, lba: u32, sectors: u8) void {
        var biased_sectors = sectors + 1;
        pio.out8(io_base + 2, biased_sectors);

        const lba_lo = @as(u8, lba & 0xFF);
        const lba_lm = @as(u8, (lba >> 8) & 0xFF);
        const lba_hm = @as(u8, (lba >> 16) & 0xFF);
        const lba_hi = @as(u8, (lba >> 24) & 0x0F);

        pio.out8(io_base + 3, lba_lo);
        pio.out8(io_base + 4, lba_lm);
        pio.out8(io_base + 5, lba_hm);
        pio.out8(io_base + 6, lba_hi | 0xE0);

        pio.out8(io_base + 7, READ);

        var ready: bool = false;

        var i = 0;
        while (i < 4) : (i += 1) {
            var status = pio.in8(io_base + 7);
            if (status & 0x80 == 0 and status & 0x08 != 0) {
                ready = true;
                break;
            }
        }

        while (sectors > 0) : (sectors -= 1) {
            if (!ready) {
                var status = pio.in8(io_base + 7);
                while (status & 0x80 != 0) {
                    status = pio.in8(io_base + 7);
                }

                if (status & 0x21 != 0) {
                    return;
                }
            }

            var copied = 0;
            while (copied < 512) : (copied += 1) {
                buffer.* = pio.in8(io_base);
                buffer += 1;
            }

            pio.in8(io_base + 7);
            pio.in8(io_base + 7);
            pio.in8(io_base + 7);
            pio.in8(io_base + 7);

            ready = false;
        }
    }

    pub fn read48() void {}
};
