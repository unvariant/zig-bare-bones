    .intel_syntax noprefix
    .section .bootsect, "awx"
	.code16

    .global _boot_start
    .global error
    .global gdt32_desc
    .global gdt32_offset_code
    .global gdt32_offset_data
    .global packet_buffer_offset
    .global packet_buffer_segment

    .equ TERMINAL_COLOR, 0x0F
    .equ VIDEO_PAGE,     0x00

_boot_start:
    cli
    cld
    xor ax, ax             # zero all the registers
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov sp, 0x7C00         # set stack top to the start of the bootloader, stack grows down

check_A20:                 # fast A20 enable, may not work on all chipsets
    in al, 0x92
    test al, 0b00000010
    jnz A20_set
    or al,   0b00000010
    and al,  0b11111110
    out 0x92, al
A20_set:

    mov   si,    offset bootsect_str
    jmp   hang

bootsect_str: .asciz "bootsect end\r\n"

    .include "util.s"


    .att_syntax prefix
