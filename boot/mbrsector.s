    .intel_syntax noprefix
    .section .mbr, "awx"
    .code16

    .global  _mbr_relocate
    .equ     BASE, 0x600

_mbr_relocate:
    cli
    cld
    xor   ax,   ax
    mov   ds,   ax
    mov   es,   ax
    mov   ss,   ax

    mov   sp,   0x7C00

    mov   di,   BASE
    mov   si,   0x7C00
    mov   cx,   256
    rep   movsw

    jmp   0:_mbr_start

_mbr_start:
    mov   byte ptr [boot_media], dl

	mov   al,    0x03
	int   0x10

	mov   ah,    0x02
	xor   dx,    dx
	int   0x10

check_for_int_13h_extensions:
	mov   ah,    0x41
	mov   bx,    0x55AA
	mov   dl,    byte ptr [boot_media]
	int   0x13

	jc    int_13h_handler

    mov   si,    offset int_13h_extensions_supported
    call  print_str

    call  load_active_partition

    mov   si,    offset no_active_partitions
    call  print_str
    jmp   hang


load_active_partition:
    mov   bx,    BASE + 0x1BE
    mov   cx,    4

search_partitions:
    test  byte ptr [bx], 0x80
    jz    continue_search

    mov   eax,   dword ptr [bx + 0x0C]
    test  eax,   eax
    jz    continue_search

    mov   word ptr [partition_offset], bx
    mov   eax,   dword ptr [bx + 0x08]

    mov   dword ptr [pblock_lo], eax
    mov   ah,    0x42
    mov   dl,    byte ptr [boot_media]
    mov   si,    offset packet
    int   0x13

    jc    int_13h_handler

    mov   dl,    byte ptr [boot_media]
    mov   si,    word ptr [partition_offset]
    mov   sp,    0x7C00

    jmp   0x7C00

continue_search:
    add   bx,    0x10
    loop  search_partitions
    ret


int_13h_handler:
    mov   si,    offset int_13h_error
    call  print_str
    movzx ax,    ah
    push  ax
    mov   cx,    1
    mov   si,    sp
    call  print_hex
    jmp   hang


print_str:
    pusha
    mov    ah,    0x0e                        # ah=0x0E, int 0x10, print character and move cursor
    mov    bx,    0 << 8 | 0x0F
1:
    lodsb
    int    0x10
    cmp    byte ptr [si], 0
    jne    1b
    popa
    ret


# # print_nhex: displays hex number on screen
# - si: pointer to number
# - cx: length of number in bytes
#     - assumes that cx is not zero
# - clobbers: none
# - returns: none
print_hex:
    push   ax
    push   cx
    push   si
    push   bp
    mov    bp,    sp

    push   0

1:
    lodsb
    mov    ah,    al
    shr    ah,    4
    and    al,    0x0F
    call   hex
    xchg   al,    ah
    call   hex
    push   ax
    loop   1b

    mov    si,    sp
    call   print_str

    mov    sp,    bp
    pop    bp
    pop    si
    pop    cx
    pop    ax
    ret


hex:
    add    al,    0x30
    cmp    al,    0x39
    jle    0f
    add    al,    'A' - 0x30 - 0x0A
0:
    ret


hang:
    jmp    hang


    .align     4
packet:
psize:         .byte  0x10
               .byte  0
psector_count: .2byte 1
poffset:       .2byte 0x7C00
psegment:      .2byte 0
pblock_lo:     .4byte 0
pblock_hi:     .4byte 0

boot_media: .byte 0
partition_offset: .2byte 0
no_active_partitions: .asciz "no active partitions\r\n"
int_13h_error: .asciz "int 13h error: "
int_13h_extensions_supported: .asciz "int 13h extensions found\r\n"

    .org   446

    .org   510
    .2byte 0xAA55
