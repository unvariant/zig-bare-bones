const partitions = @import("partitions");
const term = @import("term.zig");

const Packet = @import("packet");

const Fs = @This();

drive: u8,
partition_lba: u32,

cluster_bits: u8,
cluster_width: u8,

fat_size: u32,
first_fat_sector: u32,
first_data_sector: u32,
first_root_cluster: u32,
sectors_per_cluster: u8,
bytes_per_sector: u16,
total_sectors: u32,
reserved_sectors: u32,
total_clusters: u32,
root_dir_sectors: u32,

var root_directory = File{
    .name = "/       ",
    .extension = "   ",
    .cluster_hi = undefined,
    .cluster_lo = undefined,
    .size = undefined,
};

const Kind = enum {
    fat12,
    fat16,
    fat32,

    const Self = @This();

    fn cluster_bits(self: *const Self) u8 {
        return switch (self.*) {
            .fat12 => 12,
            .fat16 => 16,
            .fat32 => 28,
        };
    }

    fn cluster_width(self: *const Self) u8 {
        return switch (self.*) {
            .fat12 => 12,
            .fat16 => 16,
            .fat32 => 32,
        };
    }
};

const Time = packed struct {
    created_second: u5 = 0,
    created_minute: u6 = 0,
    created_hour: u5 = 0,
};

const Date = packed struct {
    created_day: u5 = 0,
    created_month: u4 = 0,
    created_year: u7 = 0,
};

const File = extern struct {
    name: [8]u8 align(1),
    extension: [3]u8 align(1),
    attributes: u8 align(1),
    reserved_for_windowsNT: u8 align(1) = 0,
    deciseconds: u8 align(1) = 0,
    created_time: Time align(1) = .{},
    created_date: Date align(1) = .{},
    accessed_date: Date align(1) = .{},
    cluster_hi: u16 align(1),
    modified_time: Time align(1) = .{},
    modified_date: Date align(1) = .{},
    cluster_lo: u16 align(1),
    size: u32 align(1),
};

const Metadata = struct {
    name: [256]u8,
    attributes: u8,
};

pub const Parameters = extern struct {
    stub: [3]u8 align(1),
    oem_name: [8]u8 align(1),
    bytes_per_sector: u16 align(1),
    sectors_per_cluster: u8 align(1),
    reserved_sectors: u16 align(1),
    fat_count: u8 align(1),
    root_entry_count: u16 align(1),
    total_sectors16: u16 align(1),
    media_type: u8 align(1),
    table_size16: u16 align(1),
    sectors_per_track: u16 align(1),
    head_side_count: u16 align(1),
    hidden_sector_count: u32 align(1),
    total_sectors32: u32 align(1),
    extended: [54]u8 align(1),

    const Self = @This();

    fn extended32(self: *const Self) *align(1) const Extended32 {
        return @ptrCast(*align(1) const Extended32, &self.extended);
    }
};

const Extended32 = extern struct {
    table_size32: u32 align(1),
    flags: u16 align(1),
    version: u16 align(1),
    root_cluster: u32 align(1),
    info: u16 align(1),
    backup_bootsector_sector: u16 align(1),
    reserved_0: [12]u8 align(1),
    drive: u8 align(1),
    reserved_1: u8 align(1),
    boot_signature: u8 align(1),
    volume_id: u32 align(1),
    volume_label: [11]u8 align(1),
    fat_type_label: [8]u8 align(1),
};

pub fn from(drive: u8, partition: *partitions.Partition, parameters: *Parameters) Fs {
    var total_sectors = @as(u32, parameters.total_sectors16);
    if (total_sectors == 0) {
        total_sectors = parameters.total_sectors32;
    }

    var fat_size = @as(u32, parameters.table_size16);
    if (fat_size == 0) {
        fat_size = parameters.extended32().table_size32;
    }

    const root_dir_sectors = (parameters.root_entry_count * 32 + parameters.bytes_per_sector - 1) / parameters.bytes_per_sector;
    const first_data_sector = parameters.reserved_sectors + (parameters.fat_count * fat_size) + root_dir_sectors;
    const first_fat_sector = parameters.reserved_sectors;
    const data_sectors = total_sectors - (parameters.reserved_sectors + parameters.fat_count * fat_size + root_dir_sectors);
    const total_clusters = data_sectors / parameters.sectors_per_cluster;

    var fat_kind: Kind = undefined;
    var root_cluster: u32 = 2;
    if (total_clusters < 4085) {
        fat_kind = .fat12;
    } else if (total_clusters < 65525) {
        fat_kind = .fat16;
    } else {
        fat_kind = .fat32;
        root_cluster = parameters.extended32().root_cluster;
    }

    return .{
        .drive = drive,
        .partition_lba = partition.start_lba,

        .cluster_bits = fat_kind.cluster_bits(),
        .cluster_width = fat_kind.cluster_width(),

        .fat_size = fat_size,
        .first_fat_sector = first_fat_sector,
        .first_data_sector = first_data_sector,
        .first_root_cluster = root_cluster,
        .sectors_per_cluster = parameters.sectors_per_cluster,
        .bytes_per_sector = parameters.bytes_per_sector,
        .total_sectors = total_sectors,
        .reserved_sectors = parameters.reserved_sectors,
        .total_clusters = total_clusters,
        .root_dir_sectors = root_dir_sectors,
    };
}

pub const Status = error{
    //// break and return failure
    failure,
    //// continue processing
    proceed,
};

pub const Cluster = struct {
    cluster: u32,

    const Self = @This();

    fn sector(self: *const Self, fs: Fs) u32 {
        return (self.cluster - 2) * fs.sectors_per_cluster + fs.first_data_sector;
    }

    fn next(self: *const Self, fs: Fs) !Self {
        const scratch = [_]u8{0} ** 512;
        const cluster = self.cluster;

        var fat_offset: u32 = undefined;
        switch (fs.kind()) {
            Kind.fat12 => {
                fat_offset = cluster + (cluster / 2);
            },
            Kind.fat16 => {
                fat_offset = cluster * 2;
            },
            Kind.fat32 => {
                fat_offset = cluster * 4;
            },
        }

        const next_sector = fs.first_fat_sector + (fat_offset / fs.bytes_per_sector);
        const absolute_offset = fat_offset % fs.bytes_per_sector;

        try fs.load(.{
            .sector_count = 1,
            .buffer = &scratch,
            .sector = next_sector,
        });

        switch (self.kind()) {
            Kind.fat12 => {
                const buffer = @ptrCast([*]align(1) u16, &scratch);
                if (cluster % 2 == 1) {
                    cluster = @as(u32, buffer[offset] >> 4);
                } else {
                    cluster = @as(u32, buffer[offset] & 0xFFF);
                }
            },
            Kind.fat16 => {
                const buffer = @ptrCast([*]align(1) u16, &scratch);
                cluster = buffer[offset];
            },
            Kind.fat32 => {
                cluster = @ptrCast([*]align(1) u32, &scratch)[offset];
            },
        }
    }
};

fn cluster_chain(self: *Fs, start_cluster: u32, closure: *const fn ([]u8) Status!*anyopaque) !*anyopaque {
    var scratch = [_]u8{0} ** 512;
    var mask = (@as(u32, 1) << @truncate(u5, self.cluster_bits)) - 1;
    var high = 0xFFFFFFF8 & mask;

    var cluster = start_cluster;
    while (cluster & mask < high) {
        var sector = self.cluster_to_sector(cluster);
        var leftover = self.bytes_per_sector * self.sectors_per_cluster;
        for (0..self.sectors_per_cluster) |_| {
            var sectors = self.bytes_per_sector / 512 + @boolToInt(self.bytes_per_sector % 512 != 0);
            for (0..sectors) |_| {
                try self.load(.{
                    .sector_count = 1,
                    .buffer = &scratch,
                    .sector = sector,
                });

                if (closure(scratch[0..@min(512, leftover)])) |something| {
                    return something;
                } else |err| {
                    if (err == Status.failure) {
                        return Error.Failure;
                    }
                }
                sector += 1;
                leftover -= 512;
            }
        }

        var fat_offset: u32 = undefined;
        switch (self.kind()) {
            Kind.fat12 => {
                fat_offset = cluster + (cluster / 2);
            },
            Kind.fat16 => {
                fat_offset = cluster * 2;
            },
            Kind.fat32 => {
                fat_offset = cluster * 4;
            },
        }

        const next_sector = self.first_fat_sector + (fat_offset / self.bytes_per_sector);
        const offset = fat_offset % self.bytes_per_sector;

        try self.load(.{
            .sector_count = 1,
            .buffer = &scratch,
            .sector = next_sector,
        });

        switch (self.kind()) {
            Kind.fat12 => {
                const buffer = @ptrCast([*]align(1) u16, &scratch);
                if (cluster % 2 == 1) {
                    cluster = @as(u32, buffer[offset] >> 4);
                } else {
                    cluster = @as(u32, buffer[offset] & 0xFFF);
                }
            },
            Kind.fat16 => {
                const buffer = @ptrCast([*]align(1) u16, &scratch);
                cluster = buffer[offset];
            },
            Kind.fat32 => {
                cluster = @ptrCast([*]align(1) u32, &scratch)[offset];
            },
        }
    }

    return Error.NotFound;
}

const Error = error{
    // cluster chain errors
    Failure,
    NotFound,

    // disk operations errors
    BadSectorCount,
    InvalidParameter,
    AddressMarkNotFound,
    WriteProtected,
    SectorNotFound,
    ResetFailed,
    UnknownOrUnimplemented,
};

fn load(self: *Fs, options: struct {
    sector_count: u16,
    buffer: []const u8,
    sector: u48,
}) !void {
    const packet = Packet.new(.{
        .drive = self.drive,
        .sector_count = options.sector_count,
        .offset = @truncate(u16, @ptrToInt(options.buffer.ptr)),
        .segment = @truncate(u16, @ptrToInt(options.buffer.ptr) >> 4 & 0xF000),
        .lba = self.partition_lba + options.sector,
    });

    var success: bool = true;
    var error_code: u8 = 0;
    asm volatile (
        \\mov   $0x42, %ah
        \\int   $0x13
        \\setnc %al
        : [success] "={al}" (success),
          [error_code] "={ah}" (error_code),
        : [packet] "{si}" (&packet),
          [drive] "{dl}" (self.drive),
    );

    if (!success) {
        if (options.sector_count != packet.sector_count) {
            return Error.BadSectorCount;
        }

        term.print("disk read error: {X:>02}", .{error_code});

        return switch (error_code) {
            0x01 => Error.InvalidParameter,
            0x02 => Error.AddressMarkNotFound,
            0x03 => Error.WriteProtected,
            0x04 => Error.SectorNotFound,
            0x05 => Error.ResetFailed,
            else => Error.UnknownOrUnimplemented,
        };
    }
}

fn cluster_to_sector(self: *Fs, cluster: u32) u32 {
    return (cluster - 2) * self.sectors_per_cluster + self.first_data_sector;
}

pub fn kind(self: *Fs) Kind {
    return switch (self.cluster_width) {
        12 => .fat12,
        16 => .fat16,
        32 => .fat32,
        else => @panic("invalid cluster_width"),
    };
}
