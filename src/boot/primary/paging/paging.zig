const std = @import("std");
const mem = std.mem;
const arch = @import("../x86_64.zig");
const term = @import("../zterm.zig");

extern const page_table_unused: usize;
extern const __page_table_memory_end: usize;

pub fn get_frame() anyerror![]u8 {
    const page_table_memory_end = @ptrToInt(&__page_table_memory_end);
    if (page_table_unused != page_table_memory_end) {
        const frame = @intToPtr([*]u8, page_table_unused)[0..0x1000];
        mem.set(u8, frame, 0);
        page_table_unused += 0x1000;
        return frame;
    } else {
        @panic("unable to allocate page frame");
    }
    return mem.Allocator.Error.OutOfMemory;
}

fn create_frame_if_not_present(descriptor: *PageMapDescriptor) void {
    if (!descriptor.present) {
        var frame = @bitCast(PageMapDescriptor, @ptrToInt((get_frame() catch @panic("cannot allocate pdp")).ptr));
        frame.present = true;
        frame.writeable = true;
        descriptor.* = frame;
    }
}

fn create_page_if_not_present(descriptor: *PageDescriptor4KiB, physaddr: u64) void {
    if (!descriptor.present) {
        var page = @bitCast(PageDescriptor4KiB, physaddr);
        page.present = true;
        page.writeable = true;
        page.user_accessible = false;
        page.write_through = false;
        page.global = false;
        page.no_execute = false;
        descriptor.* = page;
    }
}

pub fn identity_map(physaddr: u64) void {
    map(physaddr, physaddr);
}

pub fn map(virtaddr: u64, physaddr: u64) void {
    const pml4 = @intToPtr(*[512]PageMapDescriptor, arch.read_cr3().pml4 << @bitOffsetOf(arch.Cr3, "pml4"));
    const offset = @bitOffsetOf(PageMapDescriptor, "address");
    const mask = (1 << 9) - 1;

    const pml4e = virtaddr >> 39 & mask;
    const pdpe = virtaddr >> 30 & mask;
    const pde = virtaddr >> 21 & mask;
    const pte = virtaddr >> 12 & mask;

    create_frame_if_not_present(&pml4[pml4e]);
    const pdp = @intToPtr(*[512]PageMapDescriptor, pml4[pml4e].address << offset);
    create_frame_if_not_present(&pdp[pdpe]);
    const pd = @intToPtr(*[512]PageMapDescriptor, pdp[pdpe].address << offset);
    create_frame_if_not_present(&pd[pde]);
    const pt = @intToPtr(*[512]PageDescriptor4KiB, pd[pde].address << offset);
    create_page_if_not_present(&pt[pte], physaddr);
}

pub fn physaddr_for_virtaddr(virtaddr: u64) u64 {
    const pml4 = @intToPtr(*[512]PageMapDescriptor, arch.read_cr3().pml4 << @bitOffsetOf(arch.Cr3, "pml4"));
    const offset = @bitOffsetOf(PageMapDescriptor, "address");
    const mask = (1 << 9) - 1;

    const pml4e = virtaddr >> 39 & mask;
    const pdpe = virtaddr >> 30 & mask;
    const pde = virtaddr >> 21 & mask;
    const pte = virtaddr >> 12 & mask;

    if (pml4[pml4e].present) {
        const pdp = @intToPtr(*[512]PageMapDescriptor, pml4[pml4e].address << offset);
        if (pdp[pdpe].present) {
            const pd = @intToPtr(*[512]PageMapDescriptor, pdp[pdpe].address << offset);
            if (pd[pde].present) {
                const pt = @intToPtr(*[512]PageDescriptor4KiB, pd[pde].address << offset);
                if (pt[pte].present) {
                    return pt[pte].address << @bitOffsetOf(PageDescriptor4KiB, "address");
                }
            }
        }
    }

    term.printf("virtual address {X:0>16}h is not mapped\n", .{virtaddr});
    @panic("SEGMENTATION FAULT");
}

pub const PageMapDescriptor = packed struct {
    present: bool,
    writeable: bool,
    user_accessible: bool,
    write_through: bool,
    uncacheable: bool,
    accessed: bool,
    mbz0: u1,
    huge_pages: bool,
    mbz1: u1,
    available_lo: u3,
    address: u40,
    available_hi: u11,
    no_execute: bool,
};

pub const PageDescriptor4KiB = packed struct {
    present: bool,
    writeable: bool,
    user_accessible: bool,
    write_through: bool,
    uncacheable: bool,
    accessed: bool,
    dirty: bool,
    page_attribute: u1,
    global: bool,
    available_lo: u3,
    address: u40,
    available_hi: u7,
    memory_protection_key: u4,
    no_execute: bool,
};

pub fn handle_page_fault(error_code: u32) void {
    _ = error_code;
    @panic("NOT IMPLEMENTED");
}
