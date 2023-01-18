const zterm = @import("../zterm.zig");
const sys = @import("../x86_64.zig");
const FrameAllocator = @import("alloc.zig");

extern const mapped_memory: usize;

fn create_frame_if_not_present (descriptor: *PageMapDescriptor) void {
    if (!descriptor.present) {
        var frame = @bitCast(PageMapDescriptor, @ptrToInt((FrameAllocator.get_frame() catch @panic("cannot allocate pdp")).ptr));
        frame.present = true;
        frame.writeable = true;
        descriptor.* = frame;
    }
}

fn create_page_if_not_present (descriptor: *PageDescriptor4KiB, physaddr: u64) void {
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

pub fn identity_map (physaddr: u64) void {
    const pml4 = @intToPtr(*[512]PageMapDescriptor, sys.read_cr3().pml4 << @bitOffsetOf(sys.Cr3, "pml4"));
    const mask = (1 << 9) - 1;
    const offset = @bitOffsetOf(PageMapDescriptor, "address");

    var pml4e = physaddr >> 39 & mask;
    var pdpe = physaddr >> 30 & mask;
    var pde = physaddr >> 21 & mask;
    var pte = physaddr >> 12 & mask;

    create_frame_if_not_present(&pml4[pml4e]);
    const pdp =  @intToPtr(*[512]PageMapDescriptor, pml4[pml4e].address << offset);
    create_frame_if_not_present(&pdp[pdpe]);
    const pd =   @intToPtr(*[512]PageMapDescriptor, pdp[pdpe].address << offset);
    create_frame_if_not_present(&pd[pde]);
    const pt =   @intToPtr(*[512]PageDescriptor4KiB, pd[pde].address << offset);
    create_page_if_not_present(&pt[pte], physaddr);
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

pub const HugePageDescriptor = packed struct {
    present: bool,
    writeable: bool,
    user_accessible: bool,
    write_through: bool,
    uncacheable: bool,
    accessed: bool,
    dirty: bool,
    must_be_one: u1,
    global: bool,
    available_lo: u3,
    page_attribute: u1,
    address: u39,
    available_hi: u7,
    memory_protection_key: u4,
    no_execute: bool,
};