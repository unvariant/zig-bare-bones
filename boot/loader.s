    .intel_syntax noprefix

    .section .loader, "awx"
    .code16

    
    .global  _loader_start


_loader_start:
    mov   bx,    0x000F
    mov   ax,    0x0E42
1:
    int   0x10
    jmp   1b


    .att_syntax prefix