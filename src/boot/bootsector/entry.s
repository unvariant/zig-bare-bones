    .intel_syntax noprefix
    .section .bootsector, "awx"
    .code16

    .extern  _zig_entry

    .global  _entry

_entry:
    xor   ax,    ax
    mov   ds,    ax
    mov   es,    ax
    mov   ss,    ax
    mov   fs,    ax
    mov   gs,    ax
    mov   sp,    0x7C00

    push  edx
    push  edi
    push  ecx

    call  _zig_entry