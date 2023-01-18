    BITS     16
    ORG      0x7C00

bios_parameter_block:
    db       0xEB, 0x5A, 0x90
original_equipment_manufacturer:
    dq       0
bytes_per_sector:
    dw       0
sectors_per_cluster:
    db       0
reserved_sectors:
    dw       0
number_of_FATs:
    db       0
number_of_root_directories:
    dw       0
total_sectors:
    dw       0
media_descriptor_type:
    db       0
sectors_per_FAT16:
    dw       0
sectors_per_track:
    dw       0
number_of_heads:
    dw       0
number_of_hidden_sectors:
    dd       0
large_sector_count:
    dd       0
extended_bios_paramter_block:
sectors_per_FAT32:
    dd       0
flags:
    dw       0
FAT_version_minor:
    db       0
FAT_version_major:
    db       0
root_cluster_number:
    dd       0
FSinfo_sector:
    dw       0
backup_boot_sector:
    dw       0
reversed:
    times 12 db 0
drive_number:
    db       0
windows_NT_flags:
    db       0
signature:
    db       0
volume_id:
    dd       0
volume_label:
    times 11 db 0x20
system_id:
    times 8  db 0x20


    scratch equ 0x500
        packet equ 0x00
            _size         equ 0x00
            _sector_count equ 0x02
            _offset       equ 0x04
            _segment      equ 0x06
            _block_lo     equ 0x08
            _block_hi     equ 0x0C

        _first_data_sector equ 0x10
        _partition_start_lba equ 0x14


_boot_start:
    cli
    xor   ax,    ax
    mov   ds,    ax
    mov   es,    ax
    mov   ss,    ax

    mov   byte [boot_media], dl

    mov   eax,   dword ds:[si + 0x08]
    mov   dword [scratch + _partition_start_lba], eax

    mov   word [scratch + packet + _size], 0x10

    mov   ah,    0x41
    mov   bx,    0x55AA
    int   0x13
    jnc   int_13h_extensions_supported

    mov   al,    0x33
    jmp   abort

int_13h_extensions_supported:
    ; calculate first data sector
    xor   eax,   eax
    mov   al,    byte [number_of_FATs]
    mul   dword [sectors_per_FAT32]
    movzx edx,   word [reserved_sectors]
    add   eax,   edx

    mov   dword [scratch + _first_data_sector], eax

    mov   ebx,   dword [root_cluster_number]
    call  search_directory

    mov   byte [file_attribute], 0x20
    mov   word [file_name], loader_file
    call  search_directory

    call  cluster_to_sector
    mov   di,    0x7E00
    call  read_sector

    jmp   0x7E00


; # search_directory:
; - dl: file attribute
; - si: file name
; - ebx: cluster number
search_directory:
    pushad
    mov   bp,    sp

.cluster_loop:
    movzx cx,    byte [sectors_per_cluster]
    call  cluster_to_sector
    mov   di,    0x1000

.sector_loop:
    call  read_sector

.entry_loop:
    call  iterate_entries

    jc    .found
    add   eax,   1
    adc   edx,   0
    loop  .sector_loop

.next_cluster:
    xor   ecx,   ecx
    mov   eax,   ebx
    shl   eax,   2
    mov   cx,    word [bytes_per_sector]
    xor   edx,   edx
    div   ecx
    mov   cx,     word [reserved_sectors]
    add   eax,    ecx

    mov   ebx,    edx
    xor   edx,    edx
    mov   di,     0x1000
    call  read_sector

    mov   ebx,    dword [0x1000 + bx]
    and   ebx,    0x0FFFFFFF
    cmp   ebx,    0x0FFFFFF8
    jl    .cluster_loop

.not_found:
    mov   al,    0x35
    jmp   abort

.found:
    mov   dx,    [di + 20]
    mov   ax,    [di + 26]
    mov   word [bp + 16], ax
    mov   word [bp + 18], dx
    popad
    ret


; # iterate_entries
; - return:
;     - carry flag set if found
;     - di: pointer to entry
iterate_entries:
    pushad
    mov   bp,    sp

    mov   dx,    word [bytes_per_sector]
    shr   dx,    5
    mov   bx,    0x1000
    movzx ax,    byte [file_attribute]

.loop:
    cmp   byte [bx], 0
    jz    .done

    test  byte [bx + 11], al
    jz    .continue

    mov   si,    word [file_name]
    mov   di,    bx
    mov   cx,    11
    repz  cmpsb

    test  cl,    cl
    setz  ah
    jz    .done

.continue:
    add   bx,    32
    dec   dx
    jnz   .loop

.done:
    sahf
    mov   word [bp], bx
    popad
    ret


cluster_to_sector:
    push  ecx
    mov   eax,   ebx
    sub   eax,   2
    movzx ecx,   byte [sectors_per_cluster]
    mul   ecx
    add   eax,   dword [scratch + _first_data_sector]
    adc   edx,   0
    pop   ecx
    ret


; # read sectors: load sectors from the disk into memory
; - edi: address to load sector into
; - edx/eax: relative lba number
read_sector:
    pushad

    add   eax,   dword [scratch + _partition_start_lba]
    mov   dword  [scratch + packet + _block_lo], eax
    mov   dword  [scratch + packet + _block_hi], edx
    mov   dword  [scratch + packet + _offset], edi
    shl   word   [scratch + packet + _segment], 12

    mov   word   [scratch + packet + _sector_count], 1
    mov   ah,    0x42
    mov   si,    scratch + packet
    mov   dl,    byte [boot_media]
    int   0x13
    jc    .error
    test  ah,    ah
    jnz   .error
    cmp   word [scratch + packet + _sector_count], 1
    jnz   .error

    popad
    ret

.error:
    mov   al,    0x30
    jmp   abort


; # abort: displays null terminated string in si, then hangs
; - clobber: none
; - return: does not return
abort:
    mov   bx,    0x000F
    mov   ah,    0x0E
    int   0x10
hang:
    jmp   hang


; ; # print_nhex: displays hex number on screen
; ; - si: pointer to number
; ; - cx: length of number in bytes
; ;     - assumes that cx is not zero
; ; - clobber: none
; ; - return: none
; print_hex:
;     pushad
;     mov    bp,    sp

;     mov    ax,    0
;     push   0
;     push   `\r\n`

; .loop:
;     lodsb
;     mov    ah,    al
;     shr    ah,    4
;     and    al,    0x0F
;     call   hex
;     xchg   al,    ah
;     call   hex
;     push   ax
;     loop   .loop

;     mov    si,    sp
;     mov    ah,    0x0E
;     mov    bx,    0x0F
; .print:
;     lodsb
;     test   al,    al
;     jz     .done
;     int    0x10
;     jmp    .print

; .done:
;     mov    sp,    bp
;     popad
;     ret


; ; # hex: converts zero extended 4 bit number in al into hex character
; ; - clobber: al
; ; - return: al
; hex:
;     add    al,    0x30
;     cmp    al,    0x39
;     jle    .done
;     add    al,    `A` - 0x30 - 0x0A
; .done:
;     ret


boot_media: db 0
file_attribute: db 0x10
file_name: dw boot_directory

boot_directory: db "BOOT       "
loader_file:    db "LOADER  BIN"


    times   510 - ($ - $$) db 0
    dw      0xaa55