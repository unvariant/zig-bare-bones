const zterm = @import("zterm.zig");
const rsdp = @import("rsdp.zig");
const alloc = @import("alloc.zig");

const ACPI_SDT_Header = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    OEM_id: [6]u8,
    OEM_table_id: [8]u8,
    OEM_revision: u32,
    creator_id: u32,
    creator_revision: u32,
};

fn log_signature(header: *align(1) ACPI_SDT_Header) void {
    zterm.printf("found table: {s}\n", .{header.signature});
}

pub fn parse() void {
    if (rsdp.load()) |descriptor| {
        zterm.printf("rsdt address: {X}h\n", .{descriptor.rsdt});
        alloc.identity_map(@as(u64, descriptor.rsdt));
        const header = @intToPtr(*align(1) ACPI_SDT_Header, descriptor.rsdt);
        log_signature(header);
        const tables = @intToPtr([*]align(1) u32, @ptrToInt(header) + @sizeOf(ACPI_SDT_Header))[0 .. (header.length - @sizeOf(ACPI_SDT_Header)) / 4];
        for (tables) |addr| {
            log_signature(@intToPtr(*align(1) ACPI_SDT_Header, addr));
        }
    }
}
