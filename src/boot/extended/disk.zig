const term = @import("term.zig");

extern const __heap: usize;

var drive: u8 = undefined;
var parameters = Parameters{
    .size = 0x1A,
};

pub fn init(drive_number: u8) void {
    term.print("[+] init disk\r\n", .{});
    drive = drive_number;
    if (asm volatile (
        \\mov  $0x41, %ah
        \\mov  $0x55AA, %bx
        \\int  $0x13
        \\setc %al
        : [_] "={al}" (-> bool),
        : [_] "{dl}" (drive),
        : "ah", "bx"
    )) {
        @panic("int 13h extensions not supported");
    }

    parameters.load(drive);

    if (parameters.bytes_per_sector != 512) {
        term.print("bytes per sector: {}\r\n", .{parameters.bytes_per_sector});
        @panic("invalid bytes per sector");
    }
}

pub fn load(options: struct {
    sector_count: u16,
    buffer: [*]u8,
    sector: u32,
}) void {
    const addr = @ptrToInt(options.buffer);
    var packet: Packet align(4) = Packet{
        .size = 0x10,
        .sector_count = undefined,
        .offset = @truncate(u16, addr),
        .segment = @truncate(u16, addr >> 4 & 0xF000),
        .sector = options.sector,
    };

    var leftover = options.sector_count;
    while (leftover > 0) {
        const sectors = @min(127, leftover);
        packet.sector_count = sectors;
        leftover -= sectors;

        internal_load(&packet);

        const overflow = @addWithOverflow(packet.offset, sectors * parameters.bytes_per_sector);
        packet.offset = overflow[0];
        if (overflow[1] == 1) {
            packet.segment += 1;
        }
    }
}

fn internal_load(packet: *Packet) void {
    var success = true;
    var error_code: u8 = 0;
    asm volatile (
        \\mov   $0x42, %ah
        \\int   $0x13
        \\setnc %al
        : [success] "={al}" (success),
          [err] "={ah}" (error_code),
        : [packet] "{si}" (packet),
          [drive] "{dl}" (drive),
        : "ah"
    );
    check(success, error_code);
}

const DiskError = error{};

fn check(success: bool, error_code: u8) void {
    if (success) {
        return;
    }

    term.print("success: {}\r\nerror code: {X:>02}\r\n", .{ success, error_code });
    @panic("disk error");
}

const Packet = packed struct {
    size: u16,
    sector_count: u16,
    offset: u16,
    segment: u16,
    sector: u64,
};

const Parameters = packed struct {
    size: u16,
    flags: u16 = undefined,
    cylinders: u32 = undefined,
    heads: u32 = undefined,
    sectors_per_track: u32 = undefined,
    sectors: u64 = undefined,
    bytes_per_sector: u16 = undefined,
    marker: u32 = undefined,

    const Self = @This();

    fn load(self: *Self, drive_number: u8) void {
        var error_code: u8 = undefined;
        var success = asm volatile (
            \\mov   $0x48, %ah
            \\int   $0x13
            \\setnc %al
            : [success] "={al}" (-> bool),
              [failure] "={ah}" (error_code),
            : [buffer] "{si}" (self),
              [drive] "{dl}" (drive_number),
        );
        check(success, error_code);
    }
};
