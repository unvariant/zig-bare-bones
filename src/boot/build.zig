const std = @import("std");
const builtin = std.builtin;
const fs = std.fs;
const mem = std.mem;

const CrossTarget = std.zig.CrossTarget;
const AssemblyStep = @import("steps/Assembler.zig");
const ArrayList = std.ArrayList;
const Build = std.Build;
const Step = Build.Step;
const CompileStep = Build.CompileStep;

pub fn build(b: *Build) void {
    buildErr(b) catch |err| @panic(@errorName(err));
}

fn buildErr(b: *Build) !void {
    const target16 = .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .code16,
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
        .optimize = .Debug,
    });

    _ = try buildCode16(b);
    _ = try buildCode32(b);
    _ = try buildCode64(b);
}

const BuildOptions = struct {
    name: []const u8,
    path: []const u8,
    target: CrossTarget,
    optimize: builtin.OptimizeMode = .Debug,
};

fn buildBootModule(b: *Build, options: BuildOptions) !void {
    const elf = try buildModule(b, options);
    const dst = try fs.path.join(b.allocator, &.{
        "boot",
        b.fmt("{s}.bin", .{
            options.name,
        }),
    });
    installAt(b, flatBinary(b, elf), dst);
}

fn installAt(b: *Build, bin: anytype, path: []const u8) void {
    b.getInstallStep().dependOn(&b.addInstallFile(bin.getOutputSource(), path).step);
}

fn flatBinary(b: *Build, elf: *CompileStep) *Build.ObjCopyStep {
    return b.addObjCopy(elf.getOutputSource(), .{ .format = .bin });
}

fn buildModule(b: *Build, options: BuildOptions) !*CompileStep {
    const arena = b.allocator;
    const common = try files(arena, "common", .{});
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
        .name = options.name,
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
            elf.addAssemblyFile(path);
        }
    }

    for (common.items) |path| {
        if (isExtention(path, ".zig")) {
            const name = fs.path.stem(path);
            elf.addAnonymousModule(name, .{
                .source_file = .{
                    .path = path,
                },
            });
        }
    }

    return elf;
}

fn isExtention(path: []const u8, extension: []const u8) bool {
    return mem.eql(u8, extension, fs.path.extension(path));
}

fn buildMbrsector(b: *Build) !void {
    const target = CrossTarget{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .code16,
    };
    const optimize = .ReleaseSmall;

    const elf = b.addExecutable(.{
        .name = "mbrsector",
        .root_source_file = .{
            .path = "mbrsector/main.zig",
        },
        .target = target,
        .optimize = optimize,
    });
    elf.omit_frame_pointer = true;
    elf.setLinkerScriptPath(.{
        .path = "mbrsector/linker.ld",
    });
    elf.addAssemblyFile("mbrsector/entry.s");
    elf.addAnonymousModule("partitions", .{
        .source_file = .{
            .path = "common/partitions.zig",
        },
    });
    elf.addAnonymousModule("packet", .{
        .source_file = .{
            .path = "common/packet.zig",
        },
    });

    const bin = b.addObjCopy(elf.getOutputSource(), .{
        .basename = "mbrsector",
        .format = .bin,
    });

    b.getInstallStep().dependOn(&b.addInstallFile(bin.getOutputSource(), "boot/mbrsector.bin").step);
}

fn buildBootsector(b: *Build) !void {
    const target = CrossTarget{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .code16,
    };
    const optimize = .ReleaseSmall;

    const elf = b.addExecutable(.{
        .name = "bootsector",
        .root_source_file = .{
            .path = "bootsector/main.zig",
        },
        .target = target,
        .optimize = optimize,
    });
    elf.omit_frame_pointer = true;
    elf.setLinkerScriptPath(.{
        .path = "bootsector/linker.ld",
    });
    elf.addAssemblyFile("bootsector/entry.s");
    elf.addAnonymousModule("partitions", .{
        .source_file = .{
            .path = "common/partitions.zig",
        },
    });
    elf.addAnonymousModule("packet", .{
        .source_file = .{
            .path = "common/packet.zig",
        },
    });

    const bin = b.addObjCopy(elf.getOutputSource(), .{
        .basename = "bootsector",
        .format = .bin,
    });

    b.getInstallStep().dependOn(&b.addInstallFile(bin.getOutputSource(), "boot/bootsector.bin").step);
}

fn buildExtended(b: *Build) !void {
    _ = b;
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

fn files(arena: anytype, path: []const u8, options: struct {
    recursive: bool = true,
}) !ArrayList([]const u8) {
    var file_list = ArrayList([]const u8).init(arena);

    var directory = try fs.cwd().openIterableDir(path, .{});
    defer directory.close();

    var it = directory.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .File => {
                const file_path = try fs.path.join(arena, &[_][]const u8{
                    path,
                    entry.name,
                });
                try file_list.append(file_path);
            },
            .Directory => {
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
