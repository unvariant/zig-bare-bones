    .intel_syntax noprefix

    .section .boot, "awx"
    .code16


    .global  _boot_start


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


    .equ scratch, 0x500
        .equ packet, 0x00
            .equ _size,         0x00
            .equ _sector_count, 0x02
            .equ _offset,       0x04
            .equ _segment,      0x06
            .equ _block_lo,     0x08
            .equ _block_hi,     0x0C

        .equ _first_data_sector, 0x10
        .equ _partition_start_lba, 0x14


_boot_start:
    cli
    xor   ax,    ax
    mov   ds,    ax
    mov   es,    ax
    mov   ss,    ax

    mov   byte ptr [boot_media], dl

    mov   eax,   dword ptr ds:[si + 0x08]
    mov   dword ptr [scratch + _partition_start_lba], eax

    mov   word ptr [scratch + packet + _size], 0x10

    mov   ah,    0x41
    mov   bx,    0x55AA
    int   0x13
    jnc   int_13h_extensions_supported

    mov   al,    0x39
    jmp   abort

int_13h_extensions_supported:
    # calculate first data sector
    xor   eax,   eax
    mov   al,    byte ptr [number_of_FATs]
    mul   dword ptr [sectors_per_FAT32]
    movzx edx,   word ptr [reserved_sectors]
    add   eax,   edx

    mov   dword ptr [scratch + _first_data_sector], eax

    mov   ebx,   dword ptr [root_cluster_number]
    call  search_directory_abort

    mov   byte ptr [file_attribute], 0x20
    mov   word ptr [file_name], offset loader_file
    call  search_directory_abort

    call  cluster_to_sector
    mov   di,    0x7E00
    call  read_sector

    jmp   0x7E00


search_directory_abort:
    call  search_directory
    jnc   1f
    ret
1:
    mov   al,    0x38
    jmp   abort


# # search_directory:
# - dl: file attribute
# - si: file name
# - ebx: cluster number
search_directory:
    pushad
    mov   bp,    sp

cluster_loop:
    movzx cx,    byte ptr [sectors_per_cluster]
    call  cluster_to_sector
    mov   di,    0x1000

sector_loop:
    call  read_sector_abort

entry_loop:
    call  iterate_entries

    jc    directory_found
    add   eax,   1
    adc   edx,   0
    loop  sector_loop

next_cluster:
    xor   ecx,   ecx
    mov   eax,   ebx
    shl   eax,   2
    mov   cx,    word ptr [bytes_per_sector]
    xor   edx,   edx
    div   ecx
    mov   cx,    word ptr [reserved_sectors]
    add   eax,   ecx

    mov   ebx,   edx
    xor   edx,   edx
    mov   di,    0x1000
    call  read_sector_abort

    mov   ebx,   dword ptr [0x1000 + bx]
    and   ebx,   0x0FFFFFFF
    cmp   ebx,   0x0FFFFFF8
    jl    cluster_loop

directory_not_found:
    clc
    jmp   0f

directory_found:
    mov   dx,    word ptr [di + 20]
    mov   ax,    word ptr [di + 26]
    mov   word ptr [bp + 16], ax
    mov   word ptr [bp + 18], dx
    stc
0:
    popad
    ret


# # iterate_entries
# - return:
#     - carry flag set if found
#     - di: pointer to entry
iterate_entries:
    pushad
    mov   bp,    sp

    mov   dx,    word ptr [bytes_per_sector]
    shr   dx,    5
    mov   bx,    0x1000
    movzx ax,    byte ptr [file_attribute]

iterate_entries_loop:
    cmp   byte ptr [bx], 0
    jz    iterate_entries_done

    test  byte ptr [bx + 11], al
    jz    next_entry

    mov   si,    word ptr [file_name]
    mov   di,    bx
    mov   cx,    11
    repz  cmpsb

    test  cl,    cl
    setz  ah
    jz    iterate_entries_done

next_entry:
    add   bx,    32
    dec   dx
    jnz   iterate_entries_loop

iterate_entries_done:
    sahf
    mov   word ptr [bp], bx
    popad
    ret


cluster_to_sector:
    mov   eax,   ebx
    sub   eax,   2
    movzx edx,   byte ptr [sectors_per_cluster]
    mul   edx
    add   eax,   dword ptr [scratch + _first_data_sector]
    adc   edx,   0
    ret


read_sector_abort:
    call  read_sector
    jnc   1f
    ret
1:
    mov   al,    0x37
    jmp   abort


# # read sectors: load sectors from the disk into memory
# - edi: address to load sector into
# - edx/eax: relative lba number
read_sector:
    pushad

    add   eax,   dword ptr [scratch + _partition_start_lba]
    mov   dword ptr [scratch + packet + _block_lo], eax
    mov   dword ptr [scratch + packet + _block_hi], edx
    mov   dword ptr[scratch + packet + _offset], edi
    shl   word ptr [scratch + packet + _segment], 12

    mov   word ptr [scratch + packet + _sector_count], 1
    mov   ah,    0x42
    mov   si,    scratch + packet
    mov   dl,    byte ptr [boot_media]
    int   0x13
    jc    read_sector_error
    test  ah,    ah
    jnz   read_sector_error
    cmp   word ptr [scratch + packet + _sector_count], 1
    jnz   read_sector_error

    stc

0:
    popad
    ret

read_sector_error:
    clc
    jmp   0b


# # abort: displays null terminated string in si, then hangs
# - clobber: none
# - return: does not return
abort:
    mov   bx,    0x000F
    mov   ah,    0x0E
    int   0x10
1:
    jmp   1b


boot_media: .byte 0
file_attribute: .byte 0x10
file_name: .2byte offset boot_directory

boot_directory: .ascii "BOOT       "
loader_file:    .ascii "LOADER  BIN"


    .org    510
    .2byte  0xAA55

    .att_syntax prefix
