    [BITS 16]
    section .boot progbits alloc exec write

    global  _boot_start
    global  map_directory
    global  read_sector
    global  root_cluster_number
    global  file_closure_pointer
    global  compare_file
    global  file_attribute
    global  file_name
    global  bytes_per_sector


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


    SCRATCH    equ 0x1000
        PACKET equ 0x00
            SIZE         equ 0x00
            SECTOR_COUNT equ 0x02
            DST_OFFSET   equ 0x04
            DST_SEGMENT  equ 0x06
            BLOCK_LO     equ 0x08
            BLOCK_HI     equ 0x0C

        FIRST_DATA_SECTOR   equ 0x10
        PARTITION_START_LBA equ 0x14
    TMP        equ 0x2000


_boot_start:
    cli
    xor   ax,    ax
    mov   ds,    ax
    mov   es,    ax
    mov   ss,    ax

    mov   byte [boot_media], dl

    mov   eax,   dword ds:[si + 0x08]
    mov   dword [SCRATCH + PARTITION_START_LBA], eax

    mov   word [SCRATCH + PACKET + SIZE], 0x10

    mov   ah,    0x41
    mov   bx,    0x55AA
    int   0x13
    jnc   int_13h_extensions_supported

    mov   al,    0x37
    jmp   debug

int_13h_extensions_supported:
    ; calculate first data sector
    movzx eax,   byte [number_of_FATs]
    mul   dword [sectors_per_FAT32]
    movzx edx,   word [reserved_sectors]
    add   eax,   edx

    mov   dword [SCRATCH + FIRST_DATA_SECTOR], eax

    mov   ebx,   dword [root_cluster_number]
    call  map_directory_abort

    mov   byte [file_attribute], 0x20
    mov   word [file_name], loader_file
    call  map_directory_abort

    call  cluster_to_sector
    mov   edi,   0x7E00
    call  read_sector
    jnc   switch_to_loader

    mov   al,    0x39
    jmp   debug

switch_to_loader:
    jmp   0x7E00


map_directory_abort:
    mov   al,    0x38
    call  map_directory
    jc    debug
bpoint:
    push  word [esi + 20]
    push  word [esi + 26]
    pop   ebx
    ret


;;; map_directory:
; - ebx: cluster number
map_directory:
    pushad

cluster_loop:
    movzx cx,    byte [sectors_per_cluster]
    call  cluster_to_sector
    mov   edi,   TMP

sector_loop:
    call  read_sector
    jc    directory_done

    ; .inline_start
    pushad
    mov   ebx,   edi
    call  word [file_closure_pointer]
    jnc   directory_found
    popad
    jnz   directory_not_found
    ; .inline_end

    add   eax,   1
    adc   edx,   0
    loop  sector_loop

    mov   eax,   ebx
    shl   eax,   2
    movzx ecx,   word [bytes_per_sector]
    xor   edx,   edx
    div   ecx
    mov   cx,    word [reserved_sectors]
    add   eax,   ecx

    mov   ebx,   edx
    xor   edx,   edx
    mov   edi,   TMP
    call  read_sector
    jc    directory_done

    mov   ebx,   dword [TMP + bx]

    and   ebx,   0x0FFFFFFF
    cmp   ebx,   0x0FFFFFF8
    jl    cluster_loop

directory_not_found:
    stc
    jmp   directory_done

directory_found:
    ; clean up stack from inlined function
    add   sp,    32
    mov   bp,    sp
    mov   dword [bp + 4], ebx
    ; not required b/c `add sp, 32` should not overflow, and clears the carry flag
    clc
directory_done:
    popad
    ret


compare_file:
    mov   dx,    word [bytes_per_sector]
    shr   dx,    5

.loop:
    cmp   byte [bx], 0
    jz    .not_found

    mov   al,    byte [file_attribute]
    test  al,    byte [bx + 11]
    jz    .continue

    mov   si,    word [file_name]
    mov   di,    bx
    mov   cx,    11
    repz  cmpsb

    ; `test cl, cl` clears carry flag
    test  cl,    cl
    jz    .done

.continue:
    add   bx,    32
    dec   dx
    jnz   .loop

.not_found:
    test  dx,    dx
    stc
.done:
    ret


cluster_to_sector:
    lea   eax,   [ebx - 2]
    movzx edx,   byte [sectors_per_cluster]
    mul   edx
    add   eax,   dword [SCRATCH + FIRST_DATA_SECTOR]
    adc   edx,   0
    ret


;;; read sectors: load sectors from the disk into memory
; - edi: address to load sector into
; - edx/eax: relative lba number
read_sector:
    pushad

    add   eax,   dword [SCRATCH + PARTITION_START_LBA]
    mov   dword [SCRATCH + PACKET + BLOCK_LO], eax
    mov   dword [SCRATCH + PACKET + BLOCK_HI], edx
    mov   dword [SCRATCH + PACKET + DST_OFFSET], edi
    shl   word [SCRATCH + PACKET + DST_SEGMENT], 12
    mov   word [SCRATCH + PACKET + SECTOR_COUNT], 1

    mov   ah,    0x42
    xor   si,    si
    mov   ds,    si
    mov   si,    SCRATCH + PACKET
    mov   dl,    byte [boot_media]
    int   0x13

    popad
    ret


;;; deubg
; - clobber: none
; - return: does not return
debug:
    mov   bx,    0x000F
    mov   ah,    0x0E
    int   0x10
hang:
    jmp   hang


boot_media: db 0
file_attribute: db 0x10
file_name: dw boot_directory

file_closure_pointer: dw compare_file

boot_directory: db "BOOT       "
loader_file:    db "LOADER  BIN"


    times 510 - ($ - $$) db 0
    dw  0xAA55
