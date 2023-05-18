    .intel_syntax noprefix

    .section .boot64, "awx"
    .code64

    .extern _start
    .extern gdt64_offset_data
    .extern e820_memory_map
    .extern e820_memory_map_len

    .global _code_64
    .global info
    .global __stub_interrupt
    .global __stub_interrupt_with_code
    .global delay

_code_64:
    cli
    mov ax, offset gdt64_offset_data
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, 0x200000

    call _start

    .att_syntax prefix
    