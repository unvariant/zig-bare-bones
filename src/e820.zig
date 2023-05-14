const term = @import("zterm.zig");

pub const Region = packed struct {
    base: u64,
    capacity: u64,
    type: Region.Type,
    acpi: u32,

    pub const Type = enum(u32) {
        Undefined,
        Usable,
        Reserved,
        UsableACPI,
        ReservedACPI,
        Corrupt,
    };
};

extern const __e820_memory_map: usize;
extern const e820_memory_map_len: usize;

var len: usize = undefined;
pub var regions: []Region = undefined;

pub fn init() void {
    len = e820_memory_map_len;
    regions = @ptrCast([*]Region, &__e820_memory_map)[0..len];
}

pub fn dump() void {
    for (regions) |region| {
        term.printf("base: {X:0>16}h | capacity: {X:0>16}h | type: {s}\n", .{ region.base, region.capacity, @tagName(region.type) });
    }
}
