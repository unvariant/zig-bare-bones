const builtin = std.builtin;
const std = @import("std");
const Build = std.build;
const Builder = Build.Builder;
const FileSource = std.build.FileSource;
const Target = std.Target;
const Feature = Target.Cpu.Feature;
const CrossTarget = std.zig.CrossTarget;
const features = Target.x86.Feature;
const fs = std.fs;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});

const build_dir_str = [_][]const u8
    { "mkdir"
    , "-p", "zig-out/bin" };
const strip_cmd_str = [_][]const u8
    { "llvm-objcopy"
    , "--strip-debug"
    , "-I", "elf64-x86-64", "-O", "binary"
    , "--binary-architecture=i386:x86-64"
    , "kernel.elf", "zig-out/bin/kernel.bin" };
const wrap_cmd_str = [_][]const u8
    { "llvm-objcopy"
    , "-I", "binary", "-O", "elf64-x86-64"
    , "zig-out/bin/kernel.bin", "zig-out/bin/kernel.bin" };
const rename_cmd_str = [_][]const u8
    { "llvm-objcopy"
    , "--redefine-sym", "_binary_zig_out_bin_kernel_bin_start=__kernel_start"
    , "--redefine-sym", "_binary_zig_out_bin_kernel_bin_end=__kernel_end"
    , "--redefine-sym", "_binary_zig_out_bin_kernel_bin_size=__kernel_size"
    , "--rename-section", ".data=.kernel"
    , "zig-out/bin/kernel.bin", "zig-out/bin/kernel.o" };
const strip_bootloader_cmd_str = [_][]const u8
    { "llvm-objcopy"
    , "-I", "elf64-x86-64", "-O", "binary"
    , "zig-out/bin/zig-bare-bones"
    , "zig-out/bin/bootloader.bin" };
const run_cmd_str = [_][]const u8
    { "qemu-system-x86_64"
    , "-no-reboot", "-no-shutdown"
    , "-vga", "virtio"
    , "-D", "qemu.log", "-d", "trace:ide_sector_read,trace:pic_interrupt,int,in_asm"
    , "-drive", "format=raw,file=boot.dmg,if=ide" };
const create_fat32_disk_str = [_][]const u8
    { "hdiutil", "create"
    , "-fs", "FAT32", "-ov", "-size", "48m"
    , "-volname", "ZIG", "-format", "UDRW", "-srcfolder", "disk"
    , "boot"
    };
const copy_bootsector_str = [_][]const u8
    { "dd"
    , "if=zig-out/bin/bootloader.bin"
    , "of=boot.dmg"
    , "conv=notrunc", "bs=446", "count=1"
    };
const copy_boot_signature_str = [_][]const u8
    { "dd"
    , "if=zig-out/bin/bootloader.bin"
    , "of=boot.dmg"
    , "conv=notrunc", "bs=1", "count=2", "skip=510", "seek=510"
    };
const create_bootable_partition_str = [_][]const u8
    { "python3"
    , "create_bootable_partition.py"
    };


pub fn build(b: *Builder) void {
    const kernel_step = b.step("kernel", "prepare the kernel");

    const kernel = b.addStaticLibrary("kernel", "zig-out/bin/kernel.o");
    
    const loader_step = b.step("bootloader", "build the bootloader");

    const run_step = b.step("run", "run the bootloader");

    const fat32_disk_step = b.step("fat32", "create a bootable fat32 disk");

    kernel_setup(b, kernel_step);

    const loader = bootloader_setup(b);
    loader.step.dependOn(kernel_step);
    loader.setTarget(bootloader_target());
    loader.linkLibrary(kernel);
    loader.setBuildMode(b.standardReleaseOptions());
    loader.install();
    loader_step.dependOn(&loader.step);

    const strip_bootloader_cmd = b.addSystemCommand(&strip_bootloader_cmd_str);
    strip_bootloader_cmd.step.dependOn(b.getInstallStep());

    const create_fat32_disk = b.addSystemCommand(&create_fat32_disk_str);
    const copy_bootsector = b.addSystemCommand(&copy_bootsector_str);
    const copy_boot_signature = b.addSystemCommand(&copy_boot_signature_str);
    const create_bootable_partition = b.addSystemCommand(&create_bootable_partition_str);

    fat32_disk_step.dependOn(&strip_bootloader_cmd.step);
    fat32_disk_step.dependOn(&create_fat32_disk.step);
    fat32_disk_step.dependOn(&copy_bootsector.step);
    fat32_disk_step.dependOn(&copy_boot_signature.step);
    fat32_disk_step.dependOn(&create_bootable_partition.step);

    const run_cmd = b.addSystemCommand(&run_cmd_str);
    run_step.dependOn(kernel_step);
    run_step.dependOn(fat32_disk_step);
    run_step.dependOn(&run_cmd.step);
}

fn kernel_setup(b: *Builder, kernel_step: *Build.Step) void {
    const build_dir = b.addSystemCommand(&build_dir_str);
    const strip_cmd = b.addSystemCommand(&strip_cmd_str);
    const wrap_once = b.addSystemCommand(&wrap_cmd_str);
    const wrap_twice = b.addSystemCommand(&wrap_cmd_str);
    const rename_cmd = b.addSystemCommand(&rename_cmd_str);

    kernel_step.dependOn(&build_dir.step);
    kernel_step.dependOn(&strip_cmd.step);
    kernel_step.dependOn(&wrap_once.step);
    kernel_step.dependOn(&wrap_twice.step);
    kernel_step.dependOn(&rename_cmd.step);
}

fn load_assembly (loader: *Build.LibExeObjStep, directory: *fs.IterableDir) void {
    _ = loader;
    _ = directory;
}

fn bootloader_setup(b: *Builder) *Build.LibExeObjStep {
    const loader = b.addExecutable("zig-bare-bones", "src/main.zig");

    loader.setLinkerScriptPath(FileSource {
        .path = "linker.ld"
    });

    loader.addAssemblyFileSource(.{
        .path = "arch/x86_64/fat32/bootsector.s",
    });

    // loader.addAssemblyFileSource(FileSource {
    //     .path = "arch/x86_64/asm/stage_1.s"
    // });
    // loader.addAssemblyFileSource(FileSource {
    //     .path = "arch/x86_64/asm/stage_2.s"
    // });
    // loader.addAssemblyFileSource(FileSource {
    //     .path = "arch/x86_64/asm/stage_3.s"
    // });
    // loader.addAssemblyFileSource(FileSource {
    //     .path = "arch/x86_64/asm/stage_4.s"
    // });
    // loader.addAssemblyFileSource(FileSource {
    //     .path = "arch/x86_64/asm/vesa.s"
    // });
    // loader.addAssemblyFileSource(FileSource {
    //     .path = "arch/x86_64/asm/interrupt.s"
    // });

    return loader;
}

fn bootloader_target () CrossTarget {
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