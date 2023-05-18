const memory = @import("memory.zig");

export fn _zig_start16(drive: u8, partition: u16) callconv(.C) noreturn {
    _start(drive, partition) catch @panic("_zig_start fail");
}

fn _start(drive: u8, partition: u16) !noreturn {
    _ = drive;
    _ = partition;

    try memory.query();

    while (true) {}
}
