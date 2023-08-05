const std = @import("std");
const builtin = std.builtin;
const fs = std.fs;
const mem = std.mem;
const feature = std.Target.x86.Feature;

const CrossTarget = std.zig.CrossTarget;
const AssemblyStep = @import("steps/Assembler.zig");
const ExtendedStep = @import("steps/ExtendedBootloader.zig");
const ArrayList = std.ArrayList;
const Build = std.Build;
const Step = Build.Step;
const CompileStep = Build.CompileStep;
const FeatureSet = std.Target.Cpu.Feature.Set;

pub fn build(b: *Build) void {
    buildErr(b) catch |err| @panic(@errorName(err));
}

fn buildErr(b: *Build) !void {
    const target64 = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = add,
        .cpu_features_sub = sub,
    };

    try buildBootModule(b, .{
        .name = "mbrsector",
        .path = "mbrsector",
        .target = target16,
        .optimize = .ReleaseSmall,
    });
    try buildBootModule(b, .{
        .name = "bootsector",
        .path = "bootsector",
        .target = target16,
        .optimize = .ReleaseSmall,
    });
    try buildBootModule(b, .{
        .name = "extended",
        .path = "extended",
        .target = target16,
        .optimize = .ReleaseSmall,
    });

    // _ = try buildCode16(b);
    // _ = try buildCode32(b);
    // _ = try buildCode64(b);

    try buildBootstrap(b, .{
        .mbrsector = &.{
            "boot",
            "mbrsector.bin",
        },
        .bootsector = &.{
            "boot",
            "bootsector.bin",
        },
        .extended = &.{
            "boot",
            "extended.bin",
        },
    });

    const primary = b.addExecutable(.{
        .name = "primary",
        .root_source_file = .{
            .path = "primary/main.zig",
        },
        .target = target64,
        .optimize = .ReleaseSmall,
    });
    primary.addAssemblyFile("primary/32bit/code32.s");
    primary.addAssemblyFile("primary/64bit/code64.s");
    primary.addAssemblyFile("primary/64bit/interrupt.s");
    primary.setLinkerScriptPath(.{
        .path = "primary/linker.ld",
    });
    primary.install();

    installAt(b, flatBinary(b, primary), "boot/next.bin");
}

fn buildBootstrap(b: *Build, options: struct {
    mbrsector: []const []const u8,
    bootsector: []const []const u8,
    extended: []const []const u8,
}) !void {
    const arena = b.allocator;
    //// negligible memory leak here
    const mbrsector = b.getInstallPath(.prefix, try fs.path.join(arena, options.mbrsector));
    const bootsector = b.getInstallPath(.prefix, try fs.path.join(arena, options.bootsector));
    const extended = b.getInstallPath(.prefix, try fs.path.join(arena, options.extended));

    const create_disk = b.addSystemCommand(&.{
        "dd", "if=/dev/zero", "of=disk.img", "bs=1M", "count=64",
    });
    const create_partition_table = b.addSystemCommand(&.{
        "mpartition", "-I", "-B", mbrsector, "A:",
    });
    const create_partition = b.addSystemCommand(&.{
        "mpartition", "-c", "-a", "A:",
    });
    const format_partition = b.addSystemCommand(&.{
        "mformat", "-F", "-R", "64", "-B", bootsector, "A:",
    });
    const add_extended_bootloader = ExtendedStep.create(b, .{
        .disk_image = .{
            .path = "disk.img",
        },
        .extended_bootloader = .{
            .path = extended,
        },
    });
    const add_file = b.addSystemCommand(&.{ "mcopy", "zig-out/boot/next.bin", "A:" });

    const emulate = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-no-reboot",
        "-no-shutdown",
        "-drive",
        "format=raw,file=disk.img,if=ide",
        "-D",
        "qemu.log",
        "-singlestep",
        "-d",
        "in_asm,trace:ide_sector_read",
    });

    const step = b.step("bootstrap", "build bootstrap disk for testing");
    create_partition_table.step.dependOn(&create_disk.step);
    create_partition_table.step.dependOn(b.getInstallStep());
    create_partition.step.dependOn(&create_partition_table.step);
    format_partition.step.dependOn(&create_partition.step);
    add_extended_bootloader.step.dependOn(&format_partition.step);

    add_file.step.dependOn(&add_extended_bootloader.step);

    emulate.step.dependOn(&add_file.step);
    step.dependOn(&emulate.step);
}

fn buildCode16(b: *Build) !*CompileStep {
    const target = CrossTarget{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .code16,
    };
    const optimize = .ReleaseSmall;

    const code16 = b.addObject(.{
        .name = "code16",
        .root_source_file = .{
            .path = "primary/16bit/main.zig",
        },
        .target = target,
        .optimize = optimize,
    });
    code16.setLinkerScriptPath(.{
        .path = "primary/16bit/linker.ld",
    });
    code16.addAssemblyFile("primary/16bit/code16.s");

    return code16;
}

fn buildCode32(b: *Build) !*CompileStep {
    const target = CrossTarget{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
    };
    const optimize = .ReleaseSmall;

    const code32 = b.addObject(.{
        .name = "code32",
        .root_source_file = .{
            .path = "primary/32bit/main.zig",
        },
        .target = target,
        .optimize = optimize,
    });

    return code32;
}

fn buildCode64(b: *Build) !*CompileStep {
    const target = CrossTarget{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };
    const optimize = .ReleaseSmall;

    const code64 = b.addObject(.{
        .name = "code64",
        .root_source_file = .{
            .path = "primary/64bit/main.zig",
        },
        .target = target,
        .optimize = optimize,
    });

    return code64;
}
