pub const Region = packed struct {
    base: u64,
    capacity: u64,
    type: Region.Kind,
    acpi: u32,

    pub const Kind = enum(u32) {
        Undefined,
        Usable,
        Reserved,
        UsableACPI,
        ReservedACPI,
        Corrupt,
    };
};

pub const memory_map = struct {
    var regions: [*]volatile Region = undefined;
    var len: usize = undefined;

    pub const Iter = struct {
        offset: usize,

        pub fn next(self: *Iter) ?Region {
            if (self.offset >= memory_map.len) {
                return null;
            } else {
                const region = memory_map.regions[self.offset];
                self.offset += 1;
                return region;
            }
        }
    };

    pub fn init(e820_memory_map: [*]volatile Region, e820_memory_map_len: usize) void {
        regions = e820_memory_map;
        len = e820_memory_map_len;
    }

    pub fn iter() Iter {
        return Iter{
            .offset = 0,
        };
    }

    pub fn remove(index: u64) void {
        if (index >= len) {
            @panic("e820.zig:memory_map.remove\nindex out of bounds");
        }

        var shift = index;

        while (shift < len) {
            regions[shift] = regions[shift + 1];
            shift += 1;
        }

        len -= 1;
    }
};
