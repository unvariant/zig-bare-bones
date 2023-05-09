const std = @import("std");
const builtin = std.builtin;
const Build = std.build;
const Builder = Build.Builder;
const FileSource = std.build.FileSource;
const Target = std.Target;
const Feature = Target.Cpu.Feature;
const CrossTarget = std.zig.CrossTarget;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});
const ArrayList = std.ArrayList;

const features = Target.x86.Feature;
const fs = std.fs;
const debug = std.debug;
const mem = std.mem;

const build_dir_str = [_][]const u8{ "mkdir", "-p", "zig-out/bin" };
const strip_cmd_str = [_][]const u8{ "llvm-objcopy", "--strip-debug", "-I", "elf64-x86-64", "-O", "binary", "--binary-architecture=i386:x86-64", "kernel.elf", "zig-out/bin/kernel.bin" };
const wrap_cmd_str = [_][]const u8{ "llvm-objcopy", "-I", "binary", "-O", "elf64-x86-64", "zig-out/bin/kernel.bin", "zig-out/bin/kernel.bin" };
const rename_cmd_str = [_][]const u8{ "llvm-objcopy", "--redefine-sym", "_binary_zig_out_bin_kernel_bin_start=__kernel_start", "--redefine-sym", "_binary_zig_out_bin_kernel_bin_end=__kernel_end", "--redefine-sym", "_binary_zig_out_bin_kernel_bin_size=__kernel_size", "--rename-section", ".data=.kernel", "zig-out/bin/kernel.bin", "zig-out/bin/kernel.o" };
const strip_bootloader_cmd_str = [_][]const u8{ "llvm-objcopy", "-I", "elf64-x86-64", "-O", "binary", "zig-out/bin/zig-bare-bones", "zig-out/bin/bootloader.bin" };
const run_cmd_str = [_][]const u8{ "qemu-system-x86_64", "-no-reboot", "-no-shutdown", "-vga", "virtio", "-D", "qemu.log", "-d", "trace:ide_sector_read,trace:pic_interrupt,int,in_asm", "-drive", "format=raw,file=boot.dmg,if=ide" };
const create_fat32_disk_str = [_][]const u8{ "hdiutil", "create", "-fs", "FAT32", "-ov", "-size", "48m", "-volname", "ZIG", "-format", "UDRW", "-srcfolder", "disk", "boot" };
const copy_bootsector_str = [_][]const u8{ "dd", "if=zig-out/bin/bootloader.bin", "of=boot.dmg", "conv=notrunc", "bs=446", "count=1" };
const copy_boot_signature_str = [_][]const u8{ "dd", "if=zig-out/bin/bootloader.bin", "of=boot.dmg", "conv=notrunc", "bs=1", "count=2", "skip=510", "seek=510" };
const create_bootable_partition_str = [_][]const u8{ "python3", "create_bootable_partition.py" };

var b: *Builder = undefined;
var src: fs.Dir = undefined;

pub fn build(builder: *Builder) void {
    b = builder;
    src = fs.cwd().openDir("src", .{
        .access_sub_paths = true,
    }) catch |e| @panic(@errorName(e));

    const run = b.step("run", "meh");
    const boot = bootloader() catch |e| @panic(@errorName(e));

    run.dependOn(&boot.step);
    run.dependOn(b.getInstallStep());
}

const BuildError = error{
    FileNotFound,
};

fn bootloader() !*Build.LibExeObjStep {
    const arena = b.allocator;
    _ = arena;

    const boot = b.addExecutable(.{
        .name = "boot",
        .root_source_file = .{
            .path = "src/main.zig",
        },
        .target = bootloader_target(),
    });

    const loader_files = try files("boot");
    for (loader_files.items) |path| {
        if (mem.eql(u8, fs.path.extension(path), ".s")) {
            const loader_file = try assemble(path);
            boot.step.dependOn(&loader_file.step);
        }
    }

    return boot;
}

fn assemble(path: []const u8) !*Build.LibExeObjStep {
    const arena = b.allocator;
    const dirname = fs.path.dirname(path).?;
    const stem = fs.path.stem(path);
    const linker_script = try fs.path.join(arena, &[_][]const u8{ dirname, stem, ".ld" });

    const step = b.addAssembly(.{
        .name = stem,
        .source_file = .{
            .path = path,
        },
        .target = bootloader_target(),
        .optimize = .ReleaseSmall,
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

        var directory = try src.openIterableDir(path, .{});
        defer directory.close();

        var it = directory.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .File) {
                const file_path = try fs.path.join(arena, &[_][]const u8{
                    "src",
                    path,
                    entry.name,
                });
                try file_list.append(file_path);
            }
        }

        return file_list;
    }
    return BuildError.FileNotFound;
}

fn exists(path: []const u8) bool {
    if (src.statFile(path)) |_| {
        return true;
    } else |_| {
        return false;
    }
}

// fn bootloader_setup(b: *Builder) *Build.LibExeObjStep {
//     const loader = b.addExecutable(.{ .name = "boot", .root_source_file = .{
//         .path = "src/main.zig",
//     } });
//     const symbols = b.addStaticLibrary(.{ .name = "symbols", .root_source_file = .{ .path = "boot/bootsector.o" }, .target = loader.target, .optimize = .ReleaseFast });
//     symbols.addObjectFile("boot/loader.o");

//     loader.setLinkerScriptPath(.{ .path = "linker.ld" });

//     loader.linkLibrary(symbols);

//     loader.addAssemblyFileSource(.{ .path = "arch/x86_64/asm/code16.s" });
//     loader.addAssemblyFileSource(.{ .path = "arch/x86_64/asm/vesa.s" });
//     loader.addAssemblyFileSource(.{ .path = "arch/x86_64/asm/code32.s" });
//     loader.addAssemblyFileSource(.{ .path = "arch/x86_64/asm/paging32.s" });
//     loader.addAssemblyFileSource(.{ .path = "arch/x86_64/asm/code64.s" });
//     loader.addAssemblyFileSource(.{ .path = "arch/x86_64/asm/interrupt.s" });

//     const sleep_cmd_str = [_][]const u8{"sleep 5"};
//     const print_cmd_str = [_][]const u8{"echo hey"};

//     var print0 = System.ExecStep.create(b, &print_cmd_str);
//     var sleep0 = System.ExecStep.create(b, &sleep_cmd_str);
//     var print1 = System.ExecStep.create(b, &print_cmd_str);

//     loader.dependOn(&print0.step);
//     loader.dependOn(&sleep0.step);
//     loader.dependOn(&print1.step);

//     loader.optimize = b.standardOptimizeOption(.{});

//     return loader;
// }

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
