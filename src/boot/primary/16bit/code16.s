    .intel_syntax noprefix
    .section .boot16, "awx"
	.code16

    .extern  _zig_start16

    .equ TERMINAL_COLOR, 0x0F
    .equ VIDEO_PAGE,     0x00

_code_16:
    cli
    cld
    xor   ax,    ax
    mov   ds,    ax
    mov   es,    ax
    mov   ss,    ax
    mov   fs,    ax
    mov   gs,    ax

    mov   sp,    0x8000

    movzx edx,   dl
    movzx esi,   si
    movzx ecx,   cx
    push  edx
    push  esi
    push  ecx
    call  _zig_start16

    .att_syntax prefix
