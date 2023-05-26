const std = @import("std");
const mem = std.mem;
const math = std.math;
const e820 = @import("e820.zig");
const arch = @import("x86_64.zig");
const term = @import("zterm.zig");

const Allocator = mem.Allocator;

var vtable = Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .free = free,
};
var heap_top: usize = undefined;

extern const __start_of_heap: usize;

pub fn init() void {
    for (e820.regions) |region| {
        if (region.type == .Usable) {
            identity_map(region.base);
            const new = @intToPtr(*LinkedList, region.base);
            new.physaddr = region.base;
            new.capacity = region.capacity;
            new.next = free_pages;
            free_pages = new;
        }
    }
    heap_top = mem.alignForward(&__start_of_heap, arch.PAGE_SIZE);
}

pub fn allocator() Allocator {
    return Allocator{
        .ptr = undefined,
        .vtable = &vtable,
    };
}

const ALIGNMENT = @sizeOf(usize);

const LinkedList = packed struct {
    physaddr: usize,
    // total size of the section
    capacity: usize,
    // pointer to next free section of memory
    next: ?*LinkedList,
};

var free_pages: ?*LinkedList = null;

const Chunk = packed struct {
    // total size of the section
    capacity: usize,
    // offset from base of memory
    offset: usize,
};

const Error = error{
    Overflow,
} || mem.Allocator.Error;

fn alloc(ctx: *anyopaque, minimum_len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = ret_addr;

    term.printf("allocation start\n", .{});

    const lo = mem.alignForward(heap_top + @sizeOf(Chunk), ptr_align);
    const hi = mem.alignForward(lo + minimum_len, arch.PAGE_SIZE);
    const len = hi - lo;
    const offset = lo - heap_top;

    term.printf("creating chunk\n", .{});

    const chunk = @intToPtr(*align(1) Chunk, heap_top + offset - @sizeOf(Chunk));
    chunk.capacity = len;
    chunk.offset = offset;
    const buf = @intToPtr([*]u8, lo);
    heap_top = hi;

    term.printf("allocation done\n", .{});

    return buf;
}

fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
    _ = ctx;
    _ = buf;
    _ = buf_align;
    _ = ret_addr;
}

fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
    _ = ctx;
    _ = buf;
    _ = buf_align;
    _ = new_len;
    _ = ret_addr;
    return false;
}

// [ PAGING ALLOCATION / HANDLING ]

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
