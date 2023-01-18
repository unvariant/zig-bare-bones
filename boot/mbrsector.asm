    BITS     16
    BASE equ 0x500
    ORG      BASE

    global   _mbr_start

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
    mov   byte [boot_media], dl

	mov   al,    0x03
	int   0x10

	mov   ah,    0x02
	xor   dx,    dx
	int   0x10

check_for_int_13h_extensions:
	mov   ah,    0x41
	mov   bx,    0x55AA
	mov   dl,    byte [boot_media]
	int   0x13

	jc    int_13h_handler

    mov   si,    int_13h_extensions_supported
    call  print_string

    call  load_active_partition

    call  manually_load_partition
    jmp   hang


load_active_partition:
    mov   bx,    BASE + 0x1BE
    mov   cx,    4

.loop:
    test  byte ds:[bx], 0x80
    jz    .continue

    mov   eax,   dword [bx + 0x0C]
    test  eax,   eax
    jz    .continue

    mov   word [partition_offset], bx
    mov   eax,   dword [bx + 0x08]

    mov   dword  [packet.block_lo], eax
    mov   ah,    0x42
    mov   dl,    byte [boot_media]
    mov   si,    packet
    int   0x13

    jc    int_13h_handler

    mov   dl,    byte [boot_media]
    mov   si,    word [partition_offset]
    mov   sp,    0x7C00

    jmp   0x7C00

.continue:
    add   bx,    0x10
    loop  .loop
    ret


dump_partitions:

manually_load_partition:

int_13h_handler:
    mov   si,    int_13h_error
    call  print_string
    mov   byte [tmp], ah
    mov   cx,    1
    mov   si,    tmp
    call  print_hex
    jmp   hang


print_string:
    pusha
    mov    ah,    0x0e                        ; ah=0x0E, int 0x10, print character and move cursor
    mov    bx,    0 << 8 | 0x0F
.loop:
    lodsb
    int    0x10
    cmp    byte [si], 0
    jne    .loop
    popa
    ret


; # print_nhex: displays hex number on screen
; - si: pointer to number
; - cx: length of number in bytes
;     - assumes that cx is not zero
; - clobbers: none
; - returns: none
print_hex:
    push   ax
    push   cx
    push   si
    push   bp
    mov    bp,    sp

    push   0

.loop:
    lodsb
    mov    ah,    al
    shr    ah,    4
    and    al,    0x0F
    call   hex
    xchg   al,    ah
    call   hex
    push   ax
    loop   .loop

    mov    si,    sp
    call   print_string

    mov    sp,    bp
    pop    bp
    pop    si
    pop    cx
    pop    ax
    ret


hex:
    add    al,    0x30
    cmp    al,    0x39
    jle    .done
    add    al,    `A` - 0x30 - 0x0A
.done:
    ret


hang:
    jmp    hang


tmp: dw 0

    align     4
packet:
.size         db 0x10
              db 0
.sector_count dw 1
.offset       dw 0x7C00
.segment      dw 0
.block_lo     dd 0
.block_hi     dd 0

boot_media: db 0
partition_offset: dw 0
no_active_partitions: db `no active partitions`, 0
int_13h_error: db `int 13h error: `, 0
int_13h_extensions_supported: db `int 13h extensions found\r\n`, 0

    times   446 - ($ - $$) db 0

