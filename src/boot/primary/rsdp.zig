const mem = @import("std").mem;
const zterm = @import("zterm.zig");
const ebda = @import("ebda.zig");

const rsdp_signature: []const u8 = "RSD PTR ";

pub fn search(buffer: []u8) ?*RSDPDescriptorV1 {
    if (mem.alignInBytes(buffer, 16)) |aligned| {
        var idx: usize = 0;
        while (idx < aligned.len) {
            if (mem.alignInBytes(aligned[idx..aligned.len], 16)) |bytes| {
                const descriptor = @ptrCast(*RSDPDescriptorV1, bytes.ptr);
                if (sanity_check(descriptor)) {
                    return descriptor;
                }
            }
            idx += 16;
        }
    }
    return null;
}

const RSDPDescriptorV1 = extern struct {
    signature: [8]u8,
    checksum: u8,
    oemid: [6]u8,
    revision: u8,
    rsdt: u32,
};

fn calculate_checksum(descriptor: *RSDPDescriptorV1) u8 {
    const buffer = @ptrCast([*]u8, descriptor)[0..@sizeOf(RSDPDescriptorV1)];
    var sum: usize = 0;
    for (buffer) |b| {
        sum += b;
    }
    return @intCast(u8, sum & 0xFF);
}

fn sanity_check(descriptor: *RSDPDescriptorV1) bool {
    return mem.eql(u8, rsdp_signature, &descriptor.signature) and calculate_checksum(descriptor) == 0;
}

pub fn load() ?*RSDPDescriptorV1 {
    if (search(ebda.memory())) |descriptor| {
        return descriptor;
    }

    if (search(@as([]u8, @intToPtr([*]u8, 0xE0000)[0..0x20000]))) |descriptor| {
        return descriptor;
    }

    return null;
}
