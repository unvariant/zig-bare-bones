const std = @import("std");
const mem = std.mem;
const pathutil = std.fs.path;
const partitions = @import("partitions");
const term = @import("term.zig");
const disk = @import("disk.zig");

pub const Fs = @This();

var partition_lba: u32 = undefined;

var cluster_bits: u8 = undefined;
var cluster_width: u8 = undefined;

var fat_size: u32 = undefined;

var first_fat_sector: u32 = undefined;
var first_data_sector: u32 = undefined;
var first_root_cluster: u32 = undefined;

var sectors_per_cluster: u8 = undefined;
var bytes_per_sector: u16 = undefined;

var total_sectors: u32 = undefined;
var data_sectors: u32 = undefined;
var reserved_sectors: u32 = undefined;
var root_dir_sectors: u32 = undefined;
var total_clusters: u32 = undefined;

var kind: Kind = undefined;
var root_directory = File{
    .name = .{ '/', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
    .attributes = 0x10,
    .extension = .{ ' ', ' ', ' ' },
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

    const Self = @This();

    pub fn cluster(self: Self) Cluster {
        return Cluster.new((@as(u32, self.cluster_hi) << 16) | @as(u32, self.cluster_lo));
    }
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

pub fn init(drive_number: u8, partition: *partitions.Partition, parameters_addr: usize) void {
    disk.init(drive_number);

    const parameters = @intToPtr(*Parameters, parameters_addr);

    total_sectors = @as(u32, parameters.total_sectors16);
    if (total_sectors == 0) {
        total_sectors = parameters.total_sectors32;
    }

    fat_size = @as(u32, parameters.table_size16);
    if (fat_size == 0) {
        fat_size = parameters.extended32().table_size32;
    }

    root_dir_sectors = (parameters.root_entry_count * 32 + parameters.bytes_per_sector - 1) / parameters.bytes_per_sector;
    first_data_sector = parameters.reserved_sectors + (parameters.fat_count * fat_size) + root_dir_sectors;
    first_fat_sector = parameters.reserved_sectors;
    data_sectors = total_sectors - (parameters.reserved_sectors + parameters.fat_count * fat_size + root_dir_sectors);
    total_clusters = data_sectors / parameters.sectors_per_cluster;

    first_root_cluster = 2;
    if (total_clusters < 4085) {
        kind = .fat12;
    } else if (total_clusters < 65525) {
        kind = .fat16;
    } else {
        kind = .fat32;
        first_root_cluster = parameters.extended32().root_cluster;
    }

    partition_lba = partition.start_lba;

    cluster_bits = kind.cluster_bits();
    cluster_width = kind.cluster_width();

    sectors_per_cluster = parameters.sectors_per_cluster;
    bytes_per_sector = parameters.bytes_per_sector;
    reserved_sectors = parameters.reserved_sectors;

    root_directory.cluster_hi = @truncate(u16, first_root_cluster >> 16);
    root_directory.cluster_lo = @truncate(u16, first_root_cluster);
}

pub fn root() File {
    return root_directory;
}

const FsError = error{
    NotFound,
    InvalidPath,
};

pub fn open(dir: File, path: []const u8) !File {
    const stem = pathutil.stem(path);
    if (stem.len > 8) {
        @panic("path name too long");
    }

    const ext = pathutil.extension(path)[1..];
    if (ext.len > 3) {
        @panic("extension too long");
    }

    var name = [_]u8{0x20} ** 8;
    var extension = [_]u8{0x20} ** 3;
    @memcpy(@ptrCast([*]u8, &name), @ptrCast([*]const u8, stem), stem.len);
    @memcpy(@ptrCast([*]u8, &extension), @ptrCast([*]const u8, ext), ext.len);

    var files = [_]File{undefined} ** 16;

    var cluster = dir.cluster();

    while (true) {
        const sector = cluster.sector() + partition_lba;

        disk.load(.{
            .sector_count = 1,
            .buffer = @ptrCast([*]u8, &files),
            .sector = sector,
        });

        for (files) |file| {
            if (file.name[0] == 0) {
                return FsError.NotFound;
            }

            if (file.name[0] == 0xE5) {
                continue;
            }

            if (mem.eql(u8, &name, &file.name) and mem.eql(u8, &extension, &file.extension)) {
                return .{
                    .name = file.name,
                    .extension = file.extension,
                    .attributes = file.attributes,
                    .reserved_for_windowsNT = file.reserved_for_windowsNT,
                    .deciseconds = file.deciseconds,
                    .created_time = file.created_time,
                    .created_date = file.created_date,
                    .accessed_date = file.accessed_date,
                    .cluster_hi = file.cluster_hi,
                    .modified_time = file.modified_time,
                    .modified_date = file.modified_date,
                    .cluster_lo = file.cluster_lo,
                    .size = file.size,
                };
            }
        }

        cluster = try cluster.next();
    }

    return FsError.NotFound;
}

// pub fn read(file: File, buffer: []u8, seek: u32) !void {
//     var offset: u32 = 0;
//     var scratch = [_]u8{0} ** 512;
//     var cluster = file.cluster();
//     while (seek > 0) {
//         cluster = cluster.next();
//         seek -= 512;
//     }

//     while (offset < @min(buffer.len, file.size)) {
//         var sector = cluster.sector() + partition_lba;

//         disk.load(.{
//             .sector_count = 1,
//             .buffer = @ptrCast([*]u8, &scratch),
//             .sector = sector,
//         });

//         @memcpy(buffer.ptr + offset, @ptrCast([*]u8, &scratch), buffer.len - offset);

//         cluster = cluster.next();
//         offset += 512;
//     }
// }

pub const Cluster = struct {
    cluster: u32,

    const Self = @This();
    pub const Error = error{
        EndOfChain,
    };

    fn new(cluster: u32) Self {
        return .{
            .cluster = cluster & ((@as(u32, 1) << @truncate(u5, cluster_bits)) - 1),
        };
    }

    pub fn sector(self: *const Self) u32 {
        return (self.cluster - 2) * sectors_per_cluster + first_data_sector;
    }

    pub fn next(self: *const Self) !Self {
        var scratch = [_]u8{0} ** 512;
        var cluster = self.cluster;

        var fat_offset: u32 = undefined;
        switch (kind) {
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

        const next_sector = first_fat_sector + (fat_offset / bytes_per_sector) + partition_lba;
        const offset = fat_offset % bytes_per_sector;

        disk.load(.{
            .sector_count = 1,
            .buffer = @ptrCast([*]u8, &scratch),
            .sector = next_sector,
        });

        const raw = @ptrCast([*]u8, &scratch) + offset;

        switch (kind) {
            Kind.fat12 => {
                const val = @ptrCast(*align(1) u16, raw).*;
                if (cluster % 2 == 1) {
                    cluster = @as(u32, val >> 4);
                } else {
                    cluster = @as(u32, val & 0xFFF);
                }
            },
            Kind.fat16 => {
                cluster = @ptrCast(*align(1) u16, raw).*;
            },
            Kind.fat32 => {
                cluster = @ptrCast(*align(1) u32, raw).*;
            },
        }

        if (cluster >= 0xFFFFFFF8 & ((@as(u32, 1) << @truncate(u5, cluster_bits)) - 1)) {
            return Error.EndOfChain;
        }

        return .{
            .cluster = cluster,
        };
    }
};

// fn cluster_chain(self: *Fs, start_cluster: u32, closure: *const fn ([]u8) Status!*anyopaque) !*anyopaque {
//     var scratch = [_]u8{0} ** 512;
//     var mask = (@as(u32, 1) << @truncate(u5, self.cluster_bits)) - 1;
//     var high = 0xFFFFFFF8 & mask;

//     var cluster = start_cluster;
//     while (cluster & mask < high) {
//         var sector = self.cluster_to_sector(cluster);
//         var leftover = self.bytes_per_sector * self.sectors_per_cluster;
//         for (0..self.sectors_per_cluster) |_| {
//             var sectors = self.bytes_per_sector / 512 + @boolToInt(self.bytes_per_sector % 512 != 0);
//             for (0..sectors) |_| {
//                 try self.load(.{
//                     .sector_count = 1,
//                     .buffer = &scratch,
//                     .sector = sector,
//                 });

//                 if (closure(scratch[0..@min(512, leftover)])) |something| {
//                     return something;
//                 } else |err| {
//                     if (err == Status.failure) {
//                         return Error.Failure;
//                     }
//                 }
//                 sector += 1;
//                 leftover -= 512;
//             }
//         }

//         var fat_offset: u32 = undefined;
//         switch (self.kind()) {
//             Kind.fat12 => {
//                 fat_offset = cluster + (cluster / 2);
//             },
//             Kind.fat16 => {
//                 fat_offset = cluster * 2;
//             },
//             Kind.fat32 => {
//                 fat_offset = cluster * 4;
//             },
//         }

//         const next_sector = self.first_fat_sector + (fat_offset / self.bytes_per_sector);
//         const offset = fat_offset % self.bytes_per_sector;

//         try self.load(.{
//             .sector_count = 1,
//             .buffer = &scratch,
//             .sector = next_sector,
//         });

//         switch (self.kind()) {
//             Kind.fat12 => {
//                 const buffer = @ptrCast([*]align(1) u16, &scratch);
//                 if (cluster % 2 == 1) {
//                     cluster = @as(u32, buffer[offset] >> 4);
//                 } else {
//                     cluster = @as(u32, buffer[offset] & 0xFFF);
//                 }
//             },
//             Kind.fat16 => {
//                 const buffer = @ptrCast([*]align(1) u16, &scratch);
//                 cluster = buffer[offset];
//             },
//             Kind.fat32 => {
//                 cluster = @ptrCast([*]align(1) u32, &scratch)[offset];
//             },
//         }
//     }

//     return Error.NotFound;
// }
