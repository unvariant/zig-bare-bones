const term = @import("term.zig");

const Disk = @This();

drive: u8,
parameters: Parameters,

pub fn new(drive: u8) Disk {
    term.print("[+] init disk\r\n", .{});
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

    term.print("[+] loading parameters\r\n", .{});
    var parameters = Parameters.new(0x1A);
    parameters.load(drive);

    return .{
        .drive = drive,
        .parameters = parameters,
    };
}

pub fn load(self: *Disk, options: struct {
    sector_start: u32,
    sector_count: u16,
    buffer: [*]u8,
}) void {
    const addr = @intFromPtr(options.buffer);
    var packet: Packet align(4) = Packet{
        .size = 0x10,
        .sector_count = undefined,
        .offset = @as(u16, @truncate(addr)),
        .segment = @as(u16, @truncate(addr >> 4 & 0xF000)),
        .sector = options.sector_start,
    };

    var leftover = options.sector_count;
    while (leftover > 0) {
        const sectors = @min(127, leftover);
        packet.sector_count = sectors;
        leftover -= sectors;

        self.internal_load(&packet);

        const overflow = @addWithOverflow(packet.offset, sectors * self.parameters.bytes_per_sector);
        packet.offset = overflow[0];
        if (overflow[1] == 1) {
            packet.segment += 1;
        }
    }
}

fn internal_load(self: *const Disk, packet: *Packet) void {
    var success = true;
    var error_code: u8 = 0;
    asm volatile (
        \\mov   $0x42, %ah
        \\int   $0x13
        \\setnc %al
        : [success] "={al}" (success),
          [err] "={ah}" (error_code),
        : [packet] "{si}" (packet),
          [drive] "{dl}" (self.drive),
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

    fn new(size: u16) Self {
        return .{
            .size = size,
        };
    }

    fn load(self: *Self, drive: u8) void {
        var error_code: u8 = undefined;
        var success = asm volatile (
            \\mov   $0x48, %ah
            \\int   $0x13
            \\setnc %al
            : [success] "={al}" (-> bool),
              [failure] "={ah}" (error_code),
            : [buffer] "{si}" (self),
              [drive] "{dl}" (drive),
        );
        check(success, error_code);
    }
};
