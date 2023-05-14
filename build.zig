const std = @import("std");
const builtin = @import("builtin");
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

var b: *Builder = undefined;

pub fn build(builder: *Builder) void {
    b = builder;

    var boot = bootloader() catch |e| @panic(@errorName(e));
    var disk = bootdisk(boot) catch |e| @panic(@errorName(e));
    var run = b.step("run", "run the os/bootloader/whatever the hell this is");
    // add "-d", "trace:ide_sector_read,trace:pic_interrupt,int,in_asm", for stupid amount of logging
    // add "-singlestep" for logs of every instruction executed, will slow down emulation
    var run_cmd = b.addSystemCommand(&.{ "qemu-system-x86_64", "-no-reboot", "-no-shutdown", "-vga", "virtio", "-D", "qemu.log", "-d", "in_asm", "-drive", "format=raw,file=disk.img,if=ide", "-singlestep" });
    run_cmd.step.dependOn(disk);
    run.dependOn(&run_cmd.step);
}

const BuildError = error{
    FileNotFound,
};

fn bootdisk(boot: *Step) !*Step {
    const step = b.step("disk", "build fat32 disk");

    const disk_create = b.addSystemCommand(&.{
        "dd",    "if=/dev/zero", "of=disk.img",
        "bs=1M", "count=32",
    });
    const disk_format = b.addSystemCommand(&.{
        "fdisk",
        "disk.img",
    });
    disk_format.stdin = "n\np\n1\n\n\nt\n0c\na\nw\n";
    disk_format.stdio = .{
        .check = ArrayList(Step.Run.StdIo.Check).init(b.allocator),
    };
    disk_format.has_side_effects = true;
    const configure_mtools = b.addSystemCommand(&.{
        "sh", "-c", "cp mtools.conf ~/.mtoolsrc",
    });
    const disk_fat32 = b.addSystemCommand(&.{ "mformat", "-F", "-B", "zig-out/load/bootsector.bin", "C:" });
    const make_boot = b.addSystemCommand(&.{
        "mmd", "C:BOOT",
    });
    const copy_loader = b.addSystemCommand(&.{
        "mcopy", "zig-out/boot/loader.bin", "C:/BOOT/LOADER.BIN",
    });
    const copy_switch = b.addSystemCommand(&.{
        "mcopy", "zig-out/boot/switch.bin", "C:/BOOT/SWITCH.BIN",
    });
    const copy_mbr_body = b.addSystemCommand(&.{
        "dd", "if=zig-out/load/mbrsector.bin", "of=disk.img", "conv=notrunc", "bs=446", "count=1",
    });
    const copy_mbr_signature = b.addSystemCommand(&.{
        "dd", "if=zig-out/load/mbrsector.bin", "of=disk.img", "conv=notrunc", "bs=2", "count=1", "seek=510",
    });

    disk_format.step.dependOn(&disk_create.step);

    disk_fat32.step.dependOn(&configure_mtools.step);
    disk_fat32.step.dependOn(&disk_format.step);
    disk_fat32.step.dependOn(boot);
    make_boot.step.dependOn(&disk_fat32.step);
    copy_loader.step.dependOn(&make_boot.step);
    copy_switch.step.dependOn(&copy_loader.step);

    copy_mbr_body.step.dependOn(&copy_switch.step);
    copy_mbr_signature.step.dependOn(&copy_mbr_body.step);
    step.dependOn(&copy_mbr_signature.step);

    return step;
}

fn bootloader() !*Step {
    const step = b.step("boot", "build the bootloader");

    const final = b.addExecutable(.{
        .name = "switch.bin",
        .root_source_file = .{
            .path = "src/main.zig",
        },
        .target = bootloader_target(),
        .optimize = .Debug,
    });
    final.disable_stack_probing = true;

    const final_files = try files("src/arch", .{});
    defer final_files.deinit();
    for (final_files.items) |path| {
        if (mem.eql(u8, ".s", fs.path.extension(path))) {
            final.addAssemblyFile(path);
        }
    }

    final.setLinkerScriptPath(.{
        .path = "src/linker.ld",
    });

    const debug_info = OutputStep.create(b, .{
        .argv = &.{ OutputStep.Str{
            .str = "objcopy",
        }, OutputStep.Str{
            .str = "--only-keep-debug",
        }, OutputStep.Str{
            .source = final.getOutputSource(),
        }, .output },
        .output_name = "switch.debug",
    });
    const strip_final = b.addObjCopy(debug_info.getOutputSource(), .{
        .basename = "switch",
        .format = .bin,
    });
    step.dependOn(&b.addInstallFile(strip_final.getOutputSource(), "boot/switch.bin").step);

    const symbols = b.addStaticLibrary(.{
        .name = "symbols",
        .target = bootloader_target(),
        .optimize = .Debug,
    });

    const boot_files = try files("src/boot", .{
        .ignore_directories = &.{
            "load",
        },
    });
    defer boot_files.deinit();
    for (boot_files.items) |path| {
        if (mem.eql(u8, ".s", fs.path.extension(path))) {
            const obj = try assemble(path);
            symbols.step.dependOn(&obj.step);
            symbols.addObjectFile(obj.output_path);

            const stem = fs.path.stem(path);
            const elf = b.addExecutable(.{
                .name = b.fmt("{s}.elf", .{stem}),
                .target = bootloader_target(),
                .optimize = .ReleaseSmall,
            });
            elf.linker_script = obj.linker_script;
            elf.addObjectFile(obj.output_path);
            elf.linkLibrary(symbols);

            const bin = b.addObjCopy(elf.getOutputSource(), .{
                .basename = stem,
                .format = .bin,
                .only_section = b.fmt(".{s}", .{stem}),
            });

            const output_path = try fs.path.join(b.allocator, &.{
                "boot",
                b.fmt("{s}.bin", .{stem}),
            });
            step.dependOn(&b.addInstallFile(bin.getOutputSource(), output_path).step);
            b.allocator.free(output_path);
        }
    }

    const load_files = try files("src/boot/load", .{});
    defer load_files.deinit();
    for (load_files.items) |path| {
        if (mem.eql(u8, ".s", fs.path.extension(path))) {
            const obj = try assemble(path);
            symbols.step.dependOn(&obj.step);
            symbols.addObjectFile(obj.output_path);

            const stem = fs.path.stem(path);
            const elf = b.addExecutable(.{
                .name = b.fmt("{s}.elf", .{stem}),
                .target = bootloader_target(),
                .optimize = .ReleaseSmall,
            });
            elf.linker_script = obj.linker_script;
            elf.addObjectFile(obj.output_path);
            elf.linkLibrary(symbols);

            const bin = b.addObjCopy(elf.getOutputSource(), .{
                .basename = stem,
                .format = .bin,
                .only_section = b.fmt(".{s}", .{stem}),
            });

            const output_path = try fs.path.join(b.allocator, &.{
                "load",
                b.fmt("{s}.bin", .{stem}),
            });
            step.dependOn(&b.addInstallFile(bin.getOutputSource(), output_path).step);
            b.allocator.free(output_path);
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

fn files(path: []const u8, options: struct {
    recursive: bool = true,
    ignore_directories: []const []const u8 = &.{},
}) !ArrayList([]u8) {
    if (exists(path)) {
        const arena = b.allocator;
        var file_list = ArrayList([]u8).init(arena);

        var directory = try fs.cwd().openIterableDir(path, .{});
        defer directory.close();

        var it = directory.iterate();
        outer: while (try it.next()) |entry| {
            const file_path = try fs.path.join(arena, &[_][]const u8{
                path,
                entry.name,
            });
            switch (entry.kind) {
                .File => {
                    try file_list.append(file_path);
                },
                .Directory => {
                    if (options.recursive) {
                        for (options.ignore_directories) |name| {
                            if (mem.eql(u8, name, entry.name)) continue :outer;
                        }
                        var sub_files = try files(file_path, options);
                        try file_list.appendSlice(sub_files.items);
                        sub_files.deinit();
                    }
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

const OutputStep = struct {
    const Tag = enum {
        str,
        source,
        output,
    };

    const Str = union(Tag) {
        str: []const u8,
        source: FileSource,
        output: void,
    };

    const Options = struct {
        argv: []const Str,
        output_name: []const u8,
    };

    step: Step,
    argv: []const Str,
    output_name: []const u8,
    output_file: std.Build.GeneratedFile,

    const Self = @This();
    pub const base_id: Step.Id = .custom;

    pub fn create(owner: *Builder, options: Options) *Self {
        const self = owner.allocator.create(Self) catch @panic("OOM");

        var display: []u8 = "";
        for (options.argv) |str| {
            switch (str) {
                .str => |s| {
                    display = owner.fmt("{s} {s}", .{ display, s });
                },
                .source => |s| {
                    switch (s) {
                        .path => |path| {
                            display = owner.fmt("{s} {s}", .{ display, path });
                        },
                        .generated => |f| {
                            display = owner.fmt("{s} [{s}]", .{ display, f.step.name });
                        },
                    }
                },
                else => {},
            }
        }

        var step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("run {s}", .{display}),
            .owner = owner,
            .makeFn = make,
        });

        for (options.argv) |str| {
            switch (str) {
                .source => |s| {
                    switch (s) {
                        .generated => |f| {
                            step.dependOn(f.step);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        self.* = Self{
            .step = step,
            .argv = options.argv,
            .output_name = options.output_name,
            .output_file = std.Build.GeneratedFile{
                .step = &step,
            },
        };
        return self;
    }

    pub fn getOutputSource(self: *Self) FileSource {
        return .{
            .generated = &self.output_file,
        };
    }

    fn make(step: *Step, progress: *std.Progress.Node) !void {
        _ = progress;

        const builder = step.owner;
        const arena = builder.allocator;
        const self = @fieldParentPtr(Self, "step", step);

        var man = builder.cache.obtain();
        defer man.deinit();

        man.hash.add(@as(u32, 0xfadefade));

        for (self.argv) |str| {
            switch (str) {
                .source => |f| {
                    const path = f.getPath(builder);
                    _ = try man.addFile(path, null);
                },
                else => {},
            }
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
        self.output_file.path = full_dest_path;

        var argv = ArrayList([]const u8).init(arena);
        for (self.argv) |str| {
            switch (str) {
                .str => |s| {
                    try argv.append(s);
                },
                .source => |s| {
                    try argv.append(s.getPath(builder));
                },
                .output => {
                    try argv.append(full_dest_path);
                },
            }
        }

        try Step.evalChildProcess(step, argv.items);
    }
};
