const std = @import("std");
const builtin = std.builtin;
const Build = std.build;
const Builder = Build.Builder;
const FileSource = Build.FileSource;
const Target = std.Target;
const Feature = Target.Cpu.Feature;
const CrossTarget = std.zig.CrossTarget;
const FeatureSet = Feature.Set;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const File = std.fs.File;
const InstallDir = std.Build.InstallDir;
const Step = std.Build.Step;
const Compile = Step.Compile;
const InstallFile = Step.InstallFile;
const InstallArtifact = Step.InstallArtifact;
const ObjCopy = Step.ObjCopy;
const ExtendedBootloader = @import("src/boot/steps/ExtendedBootloader.zig");

const io = std.io;
const sort = std.sort;
const features = Target.x86.Feature;
const fs = std.fs;
const debug = std.debug;
const mem = std.mem;
const feature = Target.x86.Feature;

pub fn build(b: *Builder) void {
    buildWillPossiblyError(b) catch |err| {
        debug.print("error: {s}\n", .{@errorName(err)});
    };
}

fn buildWillPossiblyError(b: *Builder) !void {
    var add = FeatureSet.empty;
    var sub = FeatureSet.empty;
    add.addFeature(@intFromEnum(feature.soft_float));
    sub.addFeature(@intFromEnum(feature.mmx));
    sub.addFeature(@intFromEnum(feature.sse));
    sub.addFeature(@intFromEnum(feature.sse2));
    sub.addFeature(@intFromEnum(feature.avx));
    sub.addFeature(@intFromEnum(feature.avx2));

    const target16 = .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .code16,
        .cpu_features_add = add,
        .cpu_features_sub = sub,
    };
    const mbrsector = try buildBootModule(b, .{
        .path = "src/boot/mbrsector",
        .target = target16,
        .optimize = .ReleaseSmall,
    });
    const fatbootsector = try buildBootModule(b, .{
        .path = "src/boot/fatbootsector",
        .target = target16,
        .optimize = .ReleaseSmall,
    });
    const extended = try buildBootModule(b, .{
        .path = "src/boot/extended",
        .target = target16,
        .optimize = .ReleaseSafe,
    });

    const create_disk = b.addSystemCommand(&.{ "dd", "if=/dev/zero", "of=disk.img", "bs=1M", "count=64" });
    const create_partition_table = b.addSystemCommand(&.{ "mpartition", "-I", "-B" });
    create_partition_table.addFileArg(mbrsector.getOutput());
    create_partition_table.addArg("A:");
    const create_partition = b.addSystemCommand(&.{ "mpartition", "-c", "-a", "A:" });
    const format_partition = b.addSystemCommand(&.{ "mformat", "-F", "-R", "64", "-B" });
    format_partition.addFileArg(fatbootsector.getOutput());
    format_partition.addArg("A:");
    const add_extended_bootloader = ExtendedBootloader.create(b, .{
        .disk_image = .{ .path = "disk.img" },
        .extended_bootloader = extended.getOutput(),
    });
    const add_loader = b.addSystemCommand(&.{ "mcopy", "zig-out/boot/next.bin", "A:" });

    create_partition_table.step.dependOn(&mbrsector.step);
    create_partition_table.step.dependOn(&create_disk.step);
    create_partition.step.dependOn(&create_partition_table.step);
    format_partition.step.dependOn(&fatbootsector.step);
    format_partition.step.dependOn(&create_partition.step);
    add_extended_bootloader.step.dependOn(&extended.step);
    add_extended_bootloader.step.dependOn(&format_partition.step);
    add_loader.step.dependOn(&add_extended_bootloader.step);

    const make = b.step("make", "build bootloader and kernel");
    make.dependOn(&add_loader.step);
    make.dependOn(&installAt(b, extended, "boot/extended.bin").step);
    make.dependOn(b.getInstallStep());
}

const BuildOptions = struct {
    path: []const u8,
    target: CrossTarget,
    optimize: builtin.OptimizeMode = .Debug,

    const Self = @This();

    pub fn name(self: Self) []const u8 {
        return fs.path.stem(self.path);
    }
};

fn buildBootModule(b: *Build, options: BuildOptions) !*ObjCopy {
    const elf = try buildModule(b, options);
    const bin = flatBinary(b, elf);
    return bin;
}

fn installAt(b: *Build, bin: anytype, path: []const u8) *InstallFile {
    return b.addInstallFile(bin.getOutput(), path);
}

fn flatBinary(b: *Build, elf: *Compile) *ObjCopy {
    return b.addObjCopy(elf.getEmittedBin(), .{ .format = .bin });
}

fn isExtention(path: []const u8, extension: []const u8) bool {
    return mem.eql(u8, extension, fs.path.extension(path));
}

fn buildModule(b: *Build, options: BuildOptions) !*Compile {
    const arena = b.allocator;
    const common = try files(arena, "src/boot/common", .{});
    const assembly = try files(arena, options.path, .{});

    const main = try fs.path.join(arena, &.{
        options.path,
        "main.zig",
    });
    const linker_script = try fs.path.join(arena, &.{
        options.path,
        "linker.ld",
    });

    const elf = b.addExecutable(.{
        .name = options.name(),
        .root_source_file = .{
            .path = main,
        },
        .target = options.target,
        .optimize = options.optimize,
    });
    elf.setLinkerScriptPath(.{
        .path = linker_script,
    });

    for (assembly.items) |path| {
        if (isExtention(path, ".s")) {
            elf.addAssemblyFile(.{ .path = path });
        }
    }

    for (common.items) |path| {
        elf.addAnonymousModule(path, .{
            .source_file = .{ .path = path },
        });
    }

    b.getInstallStep().dependOn(&b.addInstallArtifact(elf, .{}).step);

    return elf;
}

const FilesOptions = struct {
    recursive: bool = true,
};

fn files(arena: anytype, path: []const u8, options: FilesOptions) !ArrayList([]const u8) {
    var file_list = ArrayList([]const u8).init(arena);

    var directory = try fs.cwd().openIterableDir(path, .{});
    defer directory.close();

    var it = directory.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const file_path = try fs.path.join(arena, &[_][]const u8{
                    path,
                    entry.name,
                });
                try file_list.append(file_path);
            },
            .directory => {
                const directory_path = try fs.path.join(arena, &[_][]const u8{
                    path,
                    entry.name,
                });
                const recursive = try files(arena, directory_path, options);
                try file_list.appendSlice(recursive.items);
                recursive.deinit();
                arena.free(directory_path);
            },
            else => {},
        }
    }

    return file_list;
}
