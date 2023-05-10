const std = @import("std");
const builtin = std.builtin;
const Build = std.build;
const Builder = Build.Builder;
const FileSource = Build.FileSource;
const Target = std.Target;
const Feature = Target.Cpu.Feature;
const CrossTarget = std.zig.CrossTarget;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const File = std.fs.File;
const InstallDir = std.Build.InstallDir;
const Step = std.Build.Step;

const io = std.io;
const sort = std.sort;
const features = Target.x86.Feature;
const fs = std.fs;
const debug = std.debug;
const mem = std.mem;

const run_cmd_str = [_][]const u8{ "qemu-system-x86_64", "-no-reboot", "-no-shutdown", "-vga", "virtio", "-D", "qemu.log", "-d", "trace:ide_sector_read,trace:pic_interrupt,int,in_asm", "-drive", "format=raw,file=boot.dmg,if=ide" };
const create_fat32_disk_str = [_][]const u8{ "hdiutil", "create", "-fs", "FAT32", "-ov", "-size", "48m", "-volname", "ZIG", "-format", "UDRW", "-srcfolder", "disk", "boot" };
const copy_bootsector_str = [_][]const u8{ "dd", "if=zig-out/bin/bootloader.bin", "of=boot.dmg", "conv=notrunc", "bs=446", "count=1" };
const copy_boot_signature_str = [_][]const u8{ "dd", "if=zig-out/bin/bootloader.bin", "of=boot.dmg", "conv=notrunc", "bs=1", "count=2", "skip=510", "seek=510" };
const create_bootable_partition_str = [_][]const u8{ "python3", "create_bootable_partition.py" };

var b: *Builder = undefined;

pub fn build(builder: *Builder) void {
    b = builder;

    const boot = bootloader() catch |e| @panic(@errorName(e));
    _ = boot;
}

const BuildError = error{
    FileNotFound,
};

fn bootloader() !*Build.Step {
    const step = b.step("boot", "build the bootloader");

    const boot = b.addExecutable(.{
        .name = "switch.bin",
        .root_source_file = .{
            .path = "src/main.zig",
        },
        .target = bootloader_target(),
    });

    const boot_files = try files("src/arch");
    defer boot_files.deinit();
    for (boot_files.items) |path| {
        if (mem.eql(u8, ".s", fs.path.extension(path))) {
            boot.addAssemblyFile(path);
        }
    }

    boot.setLinkerScriptPath(.{
        .path = "src/linker.ld",
    });
    b.installArtifact(boot);

    const symbols = b.addStaticLibrary(.{
        .name = "symbols",
        .target = bootloader_target(),
        .optimize = .ReleaseFast,
    });

    const loader_files = try files("src/boot");
    defer loader_files.deinit();
    for (loader_files.items) |path| {
        if (mem.eql(u8, ".s", fs.path.extension(path))) {
            const loader_file = try assemble(path);
            symbols.step.dependOn(&loader_file.step);
            symbols.addObjectFile(loader_file.output_path);

            const stem = fs.path.stem(path);
            const elf = b.addExecutable(.{
                .name = b.fmt("{s}.elf", .{stem}),
                .target = bootloader_target(),
                .optimize = .ReleaseSmall,
            });
            elf.linker_script = loader_file.linker_script;
            elf.addObjectFile(loader_file.output_path);
            elf.linkLibrary(symbols);

            const bin = b.addObjCopy(elf.getOutputSource(), .{
                .basename = stem,
                .format = .bin,
                .only_section = b.fmt(".{s}", .{stem}),
            });
            const output_path = b.fmt("{s}{s}{s}", .{
                "bin",
                fs.path.sep_str,
                b.fmt("{s}.bin", .{stem}),
            });
            _ = b.addInstallFile(bin.getOutputSource(), output_path);
        }
    }

    step.dependOn(b.getInstallStep());
    return step;
}

fn assemble(path: []const u8) !*AssemblyStep {
    const arena = b.allocator;
    const dirname = fs.path.dirname(path).?;
    const stem = fs.path.stem(path);
    const linker_script = try fs.path.join(arena, &[_][]const u8{ dirname, b.fmt("{s}.ld", .{stem}) });

    const step = AssemblyStep.create(b, .{
        .source_file = .{
            .path = path,
        },
        .target = bootloader_target(),
    });

    if (exists(linker_script)) {
        step.linker_script = .{
            .path = linker_script,
        };
    }

    return step;
}

fn files(path: []const u8) !ArrayList([]u8) {
    if (exists(path)) {
        const arena = b.allocator;
        var file_list = ArrayList([]u8).init(arena);

        var directory = try fs.cwd().openIterableDir(path, .{});
        defer directory.close();

        var it = directory.iterate();
        while (try it.next()) |entry| {
            const file_path = try fs.path.join(arena, &[_][]const u8{
                path,
                entry.name,
            });
            switch (entry.kind) {
                .File => {
                    try file_list.append(file_path);
                },
                .Directory => {
                    var sub_files = try files(file_path);
                    try file_list.appendSlice(sub_files.items);
                    sub_files.deinit();
                },
                else => arena.free(file_path),
            }
        }

        return file_list;
    }
    return BuildError.FileNotFound;
}

fn exists(path: []const u8) bool {
    if (fs.cwd().statFile(path)) |_| {
        return true;
    } else |_| {
        return false;
    }
}

fn bootloader_target() CrossTarget {
    var disabled_features = Feature.Set.empty;
    var enabled_features = Feature.Set.empty;

    disabled_features.addFeature(@enumToInt(features.mmx));
    disabled_features.addFeature(@enumToInt(features.sse));
    disabled_features.addFeature(@enumToInt(features.sse2));
    disabled_features.addFeature(@enumToInt(features.avx));
    disabled_features.addFeature(@enumToInt(features.avx2));
    enabled_features.addFeature(@enumToInt(features.soft_float));

    return CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
        .cpu_model = .{ .explicit = &Target.x86.cpu.x86_64 },
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };
}

const AssemblyOptions = struct {
    source_file: FileSource,
    linker_script: ?FileSource = null,
    basename: ?[]const u8 = null,
    target: CrossTarget,
};

const AssemblyStep = struct {
    step: Step,
    source_file: FileSource,
    linker_script: ?FileSource,
    target: CrossTarget,
    output_path: []const u8,
    output_name: []const u8,

    const Self = @This();
    pub const base_id: Step.Id = .custom;

    pub fn create(owner: *Builder, options: AssemblyOptions) *Self {
        const self = owner.allocator.create(Self) catch @panic("OOM");
        const stem = fs.path.stem(options.source_file.getDisplayName());
        const output_name = owner.fmt("{s}.o", .{stem});
        const output_path = fs.path.join(owner.allocator, &.{
            owner.getInstallPath(.prefix, "arch"),
            output_name,
        }) catch @panic("OOM");

        self.* = Self{
            .step = Step.init(.{
                .id = base_id,
                .name = owner.fmt("assemble {s}", .{options.source_file.path}),
                .owner = owner,
                .makeFn = makeFn(options.target),
            }),
            .source_file = options.source_file,
            .linker_script = options.linker_script,
            .target = options.target,
            .output_path = output_path,
            .output_name = output_name,
        };
        return self;
    }

    fn makeFn(target: CrossTarget) (*const fn (*Step, *std.Progress.Node) anyerror!void) {
        switch (target.cpu_arch.?) {
            .x86, .x86_64 => return makeX86,
            else => @panic("unsupported cpu arch"),
        }
    }

    fn makeX86(step: *Step, progress: *std.Progress.Node) !void {
        _ = progress;

        const builder = step.owner;
        const self = @fieldParentPtr(Self, "step", step);

        var man = builder.cache.obtain();
        defer man.deinit();

        man.hash.add(@as(u32, 0xfadefade));

        const full_src_path = self.source_file.getPath(builder);
        _ = try man.addFile(full_src_path, null);
        if (self.linker_script) |source_file| {
            const full_linker_script_path = source_file.getPath(builder);
            _ = try man.addFile(full_linker_script_path, null);
        }

        _ = try step.cacheHit(&man);

        const digest = man.final();
        const full_dest_path = builder.cache_root.join(builder.allocator, &.{
            "o", &digest, self.output_name,
        }) catch unreachable;
        const cache_path = "o" ++ fs.path.sep_str ++ &digest;
        builder.cache_root.handle.makePath(cache_path) catch |err| {
            return step.fail("unable to make path {s}: {s}", .{ cache_path, @errorName(err) });
        };

        const argv = [_][]const u8{
            "x86_64-as",
            "-o",
            full_dest_path,
            full_src_path,
        };

        try Step.evalChildProcess(step, &argv);

        const cwd = fs.cwd();
        _ = fs.Dir.updateFile(cwd, full_dest_path, cwd, self.output_path, .{}) catch |err| {
            return step.fail("unable to update file from '{s}' to '{s}': {s}", .{
                full_dest_path, self.output_path, @errorName(err),
            });
        };
    }
};
