const term = @import("term.zig");

extern const __heap: usize;

var parameters = Parameters{
    .size = 0x1A,
};
var heap_bottom = undefined;

pub fn init(drive: u8) void {
    parameters.load(drive);
    heap_bottom = @ptrToInt(&__heap);

    do_sanity_checks();
}

fn do_sanity_checks() void {
    if (0x80000 - heap_bottom < parameters.bytes_per_sector) {
        @panic("not enough space to load disk sectors");
    }
}

const DiskError = error{};

fn check(success: bool, error_code: u8) void {
    if (error_code == 0 and success) {
        return;
    }

    term.print("success: {}\r\nerror code: {X:>02}\r\n", .{ success, error_code });
    @panic("disk error");
}

const Parameters = extern struct {
    size: u16 align(1),
    flags: u16 align(1) = undefined,
    cylinders: u32 align(1) = undefined,
    heads: u32 align(1) = undefined,
    sectors_per_track: u32 align(1) = undefined,
    sectors: u64 align(1) = undefined,
    bytes_per_sector: u16 align(1) = undefined,
    marker: u32 align(1) = undefined,

    const Self = @This();

    fn load(self: *Self, drive: u8) void {
        var success = true;
        var error_code = undefined;
        asm (
            \\mov   $0x48, %ah
            \\int   $0x13
            \\setnc %al
            : [success] "=al" (success),
              [failure] "=ah" (error_code),
            : [buffer] "si" (&self),
              [drive] "dl" (drive),
        );
        check(success, error_code);
    }
};
