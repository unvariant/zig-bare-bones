const std = @import("std");
//const filesystem = @import("fs.zig");
const term = @import("term.zig");

const Partitions = @import("partitions");
const Partition = Partitions.Partition;

export fn _extended_entry(drive: u8, partition: *Partition, idx: u8) linksection(".entry") callconv(.C) noreturn {
    term.print("[+] enter extended bootloader\r\n", .{});

    term.print("[+] boot args:\r\n- drive: 0x{X:0>2}\r\n- partition: {any}\r\n- index: {}\r\n", .{ drive, partition, idx });
    term.print("__heap: {X}\r\n", .{@ptrToInt(&__heap)});

    //var fs = filesystem.from(drive, partition, @intToPtr(*filesystem.Parameters, 0x7C00));
    //term.print("[+] boot fs: {any}\r\n", .{fs.kind()});

    @panic("failed extended bootloader\r\n");
}

pub fn panic(static: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    term.fail("[-] PANIC: {s}", .{static});
}
