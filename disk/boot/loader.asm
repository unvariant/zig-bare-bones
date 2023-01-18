    [BITS 16]
    [ORG 0x7E00]

_loader_start:
    mov   bx,    0x000F
    mov   ax,    0x0E61
    int   0x10
    jmp   _loader_start