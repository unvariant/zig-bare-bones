const std = @import("std");
const mem = std.mem;
const pathutil = std.fs.path;
const term = @import("term.zig");
const disk = @import("disk.zig");

pub const Fs = @This();
const Partition = @import("partition.zig");

cluster_bit_used: u8,
cluster_bit_width: u8,
fat_size: u32,

first_data_sector: u32,
first_fat_sector: u32,
first_root_cluster: u32,

sectors_per_cluster: u8,
bytes_per_sector: u16,

total_sectors: u32,
data_sectors: u32,
reserved_sectors: u32,
root_dir_sectors: u32,
total_clusters: u32,

kind: Kind,
partition: *Partition,

const Kind = enum {
    fat12,
    fat16,
    fat32,

    const Self = @This();

    fn cluster_bit_used(self: *const Self) u8 {
        return switch (self.*) {
            .fat12 => 12,
            .fat16 => 16,
            .fat32 => 28,
        };
    }

    fn cluster_bit_width(self: *const Self) u8 {
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

const RawFile = extern struct {
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

    comptime {
        if (@sizeOf(@This()) != 0x20) {
            @compileError("RawFile is improperly sized");
        }
    }
};

const File = struct {
    raw: RawFile,
    offset: usize,
    fs: *Fs,

    const Self = @This();
    const Error = error{
        NotFound,
        InvalidPath,
    } || Cluster.Error;

    const Reader = std.io.Reader(*Self, Error, read);
    const Seeker = std.io.SeekableStream(*Self, Error, Error, seekTo, seekBy, getPos, getEndPos);

    pub usingnamespace Reader;
    pub usingnamespace Seeker;

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }

    pub fn seeker(self: *Self) Seeker {
        return .{ .context = self };
    }

    fn seekTo(self: *Self, offset: u64) Error!void {
        self.offset = offset;
    }

    fn seekBy(self: *Self, offset: i64) Error!void {
        self.offset += offset;
    }

    fn getPos(self: *Self) Error!u64 {
        return self.offset;
    }

    fn getEndPos(self: *Self) Error!u64 {
        return self.raw.size;
    }

    pub fn open(self: *const Self, path: []const u8) Error!Self {
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
        mem.copy(u8, &name, stem);
        mem.copy(u8, &extension, ext);

        var files = [_]RawFile{undefined} ** 16;

        var clusters = try self.cluster(self.fs);

        while (true) {
            const sector = clusters.sector(self.fs);
            self.fs.partition.load(.{
                .sector_start = sector,
                .sector_count = 1,
                .buffer = @ptrCast(&files),
            });

            for (files) |file| {
                if (file.name[0] == 0) {
                    return Error.NotFound;
                }

                if (file.name[0] == 0xE5) {
                    continue;
                }

                if (mem.eql(u8, &name, &file.name) and mem.eql(u8, &extension, &file.extension)) {
                    return .{
                        .raw = file,
                        .fs = self.fs,
                        .offset = 0,
                    };
                }
            }

            clusters = try clusters.next(self.fs);
        }

        return Error.NotFound;
    }

    fn read(self: *Self, buffer: []u8) Error!usize {
        var scratch = [_]u8{0} ** 512;
        var clusters = try self.cluster(self.fs);
        var offset_start = self.offset;
        while (self.offset < self.raw.size) {
            // term.print("offset: {}, size: {}\r\n", .{ self.offset, self.raw.size });
            self.fs.partition.load(.{
                .sector_start = clusters.sector(self.fs),
                .sector_count = 1,
                .buffer = @as([*]u8, @ptrCast(&scratch)),
            });

            @memcpy(buffer[self.offset .. self.offset + 512], &scratch);
            self.offset += 512;

            clusters = clusters.next(self.fs) catch |err| {
                if (err == Cluster.Error.EndOfChain) {
                    return self.offset - offset_start;
                }
                return err;
            };
        }

        unreachable;
    }

    pub fn cluster(self: Self, fs: *Fs) Error!Cluster {
        return try Cluster.new(fs, (@as(u32, self.raw.cluster_hi) << 16) | @as(u32, self.raw.cluster_lo));
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
        return @as(*align(1) const Extended32, @ptrCast(&self.extended));
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

pub fn from(partition: *Partition, parameters_addr: usize) Fs {
    const parameters = @as(*Parameters, @ptrFromInt(parameters_addr));

    var total_sectors = @as(u32, parameters.total_sectors16);
    if (total_sectors == 0) {
        total_sectors = parameters.total_sectors32;
    }

    var fat_size = @as(u32, parameters.table_size16);
    if (fat_size == 0) {
        fat_size = parameters.extended32().table_size32;
    }

    var root_dir_sectors = (parameters.root_entry_count * 32 + parameters.bytes_per_sector - 1) / parameters.bytes_per_sector;
    var first_data_sector = parameters.reserved_sectors + (parameters.fat_count * fat_size) + root_dir_sectors;
    var first_fat_sector = parameters.reserved_sectors;
    var data_sectors = total_sectors - (parameters.reserved_sectors + parameters.fat_count * fat_size + root_dir_sectors);
    var total_clusters = data_sectors / parameters.sectors_per_cluster;

    var first_root_cluster: u32 = 2;
    var kind: Kind = undefined;
    if (total_clusters < 4085) {
        kind = .fat12;
    } else if (total_clusters < 65525) {
        kind = .fat16;
    } else {
        kind = .fat32;
        first_root_cluster = parameters.extended32().root_cluster;
    }

    return .{
        .kind = kind,
        .fat_size = fat_size,
        .cluster_bit_used = kind.cluster_bit_used(),
        .cluster_bit_width = kind.cluster_bit_width(),
        .first_data_sector = first_data_sector,
        .first_fat_sector = first_fat_sector,
        .sectors_per_cluster = parameters.sectors_per_cluster,
        .bytes_per_sector = parameters.bytes_per_sector,
        .total_sectors = total_sectors,
        .data_sectors = data_sectors,
        .reserved_sectors = parameters.reserved_sectors,
        .total_clusters = total_clusters,
        .partition = partition,
        .first_root_cluster = first_root_cluster,
        .root_dir_sectors = root_dir_sectors,
    };
}

pub fn root(self: *Fs) File {
    return .{
        .raw = .{
            .name = .{ '/', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
            .attributes = 0x10,
            .extension = .{ ' ', ' ', ' ' },
            .cluster_hi = @as(u16, @truncate(self.first_root_cluster >> 16)),
            .cluster_lo = @as(u16, @truncate(self.first_root_cluster)),
            .size = self.root_dir_sectors * self.bytes_per_sector,
        },
        .fs = self,
        .offset = 0,
    };
}

fn cluster_mask(self: *const Fs) u32 {
    return (@as(u32, 1) << @as(u5, @truncate(self.cluster_bit_used))) - 1;
}

pub const Cluster = struct {
    cluster: u32,

    const Self = @This();
    pub const Error = error{
        EndOfChain,
    };

    fn new(fs: *const Fs, cluster: u32) Error!Self {
        if (cluster >= 0xFFFFFFF8 & fs.cluster_mask()) {
            return Error.EndOfChain;
        }

        return .{ .cluster = cluster & ((@as(u32, 1) << @as(u5, @truncate(fs.cluster_bit_used))) - 1) };
    }

    pub fn sector(self: *const Self, fs: *const Fs) u32 {
        return (self.cluster - 2) * fs.sectors_per_cluster + fs.first_data_sector;
    }

    pub fn next(self: *const Self, fs: *const Fs) Error!Self {
        var scratch = [_]u8{0} ** 512;
        var cluster = self.cluster;

        var fat_offset: u32 = undefined;
        switch (fs.kind) {
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
        const offset = fat_offset % fs.bytes_per_sector;

        fs.partition.load(.{
            .sector_start = next_sector,
            .sector_count = 1,
            .buffer = @as([*]u8, @ptrCast(&scratch)),
        });

        const raw = @as([*]u8, @ptrCast(&scratch)) + offset;

        switch (fs.kind) {
            Kind.fat12 => {
                const val = @as(*align(1) u16, @ptrCast(raw)).*;
                if (cluster % 2 == 1) {
                    cluster = @as(u32, val >> 4);
                } else {
                    cluster = @as(u32, val & 0xFFF);
                }
            },
            Kind.fat16 => {
                cluster = @as(*align(1) u16, @ptrCast(raw)).*;
            },
            Kind.fat32 => {
                cluster = @as(*align(1) u32, @ptrCast(raw)).*;
            },
        }

        return try Self.new(fs, cluster);
    }
};
