    .intel_syntax noprefix
    .section .boot, "awx"
    .code16


    .global  _boot_start
    .global  map_directory
    .global  read_sector
    .global  root_cluster_number
    .global  file_closure_offset
    .global  file_closure_segment
    .global  compare_file
    .global  file_attribute
    .global  file_name
    .global  bytes_per_sector


bios_parameter_block:
    .byte        0xEB, 0x5A, 0x90
original_equipment_manufacturer:
    .8byte       0
bytes_per_sector:
    .2byte       0
sectors_per_cluster:
    .byte        0
reserved_sectors:
    .2byte       0
number_of_FATs:
    .byte        0
number_of_root_directories:
    .2byte       0
total_sectors:
    .2byte       0
media_descriptor_type:
    .byte        0
sectors_per_FAT16:
    .2byte       0
sectors_per_track:
    .2byte       0
number_of_heads:
    .2byte       0
number_of_hidden_sectors:
    .4byte       0
large_sector_count:
    .4byte       0
extended_bios_paramter_block:
sectors_per_FAT32:
    .4byte       0
flags:
    .2byte       0
FAT_version_minor:
    .byte        0
FAT_version_major:
    .byte        0
root_cluster_number:
    .4byte       0
FSinfo_sector:
    .2byte       0
backup_boot_sector:
    .2byte       0
reversed:
    .space  12,  0
drive_number:
    .byte        0
windows_NT_flags:
    .byte        0
signature:
    .byte        0
volume_id:
    .4byte       0
volume_label:
    .space  11,  0x20
system_id:
    .space  8,   0x20


    .equ SCRATCH, 0x1000
        .equ PACKET, 0x00
            .equ SIZE,         0x00
            .equ SECTOR_COUNT, 0x02
            .equ DST_OFFSET,   0x04
            .equ DST_SEGMENT,  0x06
            .equ BLOCK_LO,     0x08
            .equ BLOCK_HI,     0x0C

        .equ FIRST_DATA_SECTOR, 0x10
        .equ PARTITION_START_LBA, 0x14
    .equ TMP, 0x2000


_boot_start:
    cli
    xor   ax,    ax
    mov   ds,    ax
    mov   es,    ax
    mov   ss,    ax

    mov   byte ptr [boot_media], dl

    mov   eax,   dword ptr ds:[si + 0x08]
    mov   dword ptr [SCRATCH + PARTITION_START_LBA], eax

    mov   word ptr [SCRATCH + PACKET + SIZE], 0x10

    mov   ah,    0x41
    mov   bx,    0x55AA
    int   0x13
    jnc   int_13h_extensions_supported

    mov   al,    0x37
    jmp   debug

int_13h_extensions_supported:
    # calculate first data sector
    movzx eax,   byte ptr [number_of_FATs]
    mul   dword ptr [sectors_per_FAT32]
    movzx edx,   word ptr [reserved_sectors]
    add   eax,   edx

    mov   dword ptr [SCRATCH + FIRST_DATA_SECTOR], eax

    mov   ebx,   dword ptr [root_cluster_number]
    call  map_directory_abort

    mov   byte ptr [file_attribute], 0x20
    mov   word ptr [file_name], offset loader_file
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
    push  word ptr [edi + 20]
    push  word ptr [edi + 26]
    pop   ebx
    ret


# # map_directory:
# - ebx: cluster number
map_directory:
    pushad

cluster_loop:
    movzx cx,    byte ptr [sectors_per_cluster]
    call  cluster_to_sector
    mov   edi,   TMP

sector_loop:
    call  read_sector
    jc    directory_done

    # .inline_start
    /*pushad
    mov   ebx,   edi
    mov   fs,    word ptr [file_closure_segment]
    call  fs:word ptr [file_closure_offset]
    jnc   directory_found
    popad
    jmp   directory_not_found
    //jnz   directory_not_found*/
    iterate_entries:
        pushad

        mov   dx,    word ptr [bytes_per_sector]
        shr   dx,    5
        mov   ebx,   edi

    iterate_entries_loop:
        cmp   byte ptr [bx], 0
        jz    iterate_entries_not_found

        mov   fs,    word ptr [file_closure_segment]
        call  fs:dword ptr [file_closure_offset]
        jnc   directory_found

    next_entry:
        add   bx,    32
        dec   dx
        jnz   iterate_entries_loop

    iterate_entries_not_found:
        popad
    # .inline_end

    add   eax,   1
    adc   edx,   0
    loop  sector_loop

    mov   eax,   ebx
    shl   eax,   2
    movzx ecx,   word ptr [bytes_per_sector]
    xor   edx,   edx
    div   ecx
    mov   cx,    word ptr [reserved_sectors]
    add   eax,   ecx

    mov   ebx,   edx
    xor   edx,   edx
    mov   edi,   TMP
    call  read_sector
    jc    directory_done

    mov   ebx,   dword ptr [TMP + bx]

    and   ebx,   0x0FFFFFFF
    cmp   ebx,   0x0FFFFFF8
    jl    cluster_loop

directory_not_found:
    stc
    jmp   directory_done

directory_found:
    # clean up stack from inlined function
    add   sp,    32
    mov   bp,    sp
    mov   dword ptr [bp], ebx
    // not required b/c `add sp, 32` should not overflow, and clears the carry flag
    clc
directory_done:
    popad
    ret


/*compare_file:
    mov   dx,    word ptr [bytes_per_sector]
    shr   dx,    5

1:
    cmp   byte ptr [bx], 0
    jz    compare_file$not_found

    mov   al,    byte ptr [file_attribute]
    test  al,    byte ptr [bx + 11]
    jz    compare_file$continue

    mov   si,    word ptr [file_name]
    mov   di,    bx
    mov   cx,    11
    repz  cmpsb

    # `test cl, cl` clears carry flag
    test  cl,    cl
    jz    compare_file$done

compare_file$continue:
    add   bx,    32
    dec   dx
    jnz   1b

compare_file$not_found:
    test  dx,    dx
    stc
compare_file$done:
    ret*/


compare_file:
    mov   al,    byte ptr [file_attribute]
    test  al,    byte ptr [bx + 11]
    jz    compare_file$not_equal

    mov   si,    word ptr [file_name]
    mov   di,    bx
    mov   cx,    11
    repz  cmpsb

    # `test cl, cl` clears carry flag
    test  cl,    cl
    jz    compare_file$equal

compare_file$not_equal:
    stc
compare_file$equal:
    retf


cluster_to_sector:
    lea   eax,   [ebx - 2]
    movzx edx,   byte ptr [sectors_per_cluster]
    mul   edx
    add   eax,   dword ptr [SCRATCH + FIRST_DATA_SECTOR]
    adc   edx,   0
    ret


# # read sectors: load sectors from the disk into memory
# - edi: address to load sector into
# - edx/eax: relative lba number
read_sector:
    pushad

    add   eax,   dword ptr [SCRATCH + PARTITION_START_LBA]
    mov   dword ptr [SCRATCH + PACKET + BLOCK_LO], eax
    mov   dword ptr [SCRATCH + PACKET + BLOCK_HI], edx
    mov   dword ptr [SCRATCH + PACKET + DST_OFFSET], edi
    shl   word ptr [SCRATCH + PACKET + DST_SEGMENT], 12
    mov   word ptr [SCRATCH + PACKET + SECTOR_COUNT], 1

    mov   ah,    0x42
    xor   si,    si
    mov   ds,    si
    mov   si,    SCRATCH + PACKET
    mov   dl,    byte ptr [boot_media]
    int   0x13

    popad
    ret


# # deubg
# - clobber: none
# - return: does not return
debug:
    mov   bx,    0x000F
    mov   ah,    0x0E
    int   0x10
hang:
    jmp   hang


boot_media: .byte 0
file_attribute: .byte 0x10
file_name: .2byte offset boot_directory
file_closure_offset: .2byte offset compare_file
file_closure_segment: .2byte 0

boot_directory: .ascii "BOOT       "
loader_file:    .ascii "LOADER  BIN"


    .org    510
    .2byte  0xAA55
