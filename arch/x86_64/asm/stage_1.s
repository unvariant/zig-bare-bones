    .intel_syntax noprefix
    .section .bootsect, "awx"
	.code16

    .global _boot_start
    .global error
    .global gdt32_desc
    .global gdt32_offset_code
    .global gdt32_offset_data
    .global packet_buffer_offset
    .global packet_buffer_segment

    .equ TERMINAL_COLOR, 0x0f
    .equ VIDEO_PAGE,     0x00

_boot_start:
    cli
    xor ax, ax             # zero all the registers
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov sp, 0x7c00         # set stack top to the start of the bootloader, stack grows down

    mov byte ptr [boot_media], dl

    mov al, 0x03           # 80x25 text mode, 16 colors
    int 0x10               # setting mode also clears screen

    mov ah, 0x02           # move cursor to top left
    xor dx, dx
    int 0x10

    cld                    # clear direction flag, lodsb/stosb increment si/di

    push offset _int13h_ext_nsupported
    jmp error

check_A20:                 # fast A20 enable, may not work on all chipsets
    in al, 0x92
    test al, 0b00000010
    jnz A20_set
    or al,   0b00000010
    and al,  0b11111110
    out 0x92, al
A20_set:

    mov ah, 0x41           # ah=0x41, bx=0xaa55 check for int 13h extensions
    mov bx, 0xaa55
    mov dl, byte ptr [boot_media]
    int 0x13
    jnc load_rest_of_bootloader      # carry bit set if not supported

    mov si, offset _int13h_ext_nsupported
    jmp error

load_rest_of_bootloader:
    mov ebx, 0xFFFF
	# dl: 80h=drive 0, 81h=drive 1, dl=0 for floppy
1:
    mov ecx, 127
    cmp bx, cx
    cmovb cx, bx
    mov word ptr [packet_sector_count], cx       # set number of sectors to read, overwritten with number of actual sectors read after interrupt

    push bx
    push offset _sectors_not_equal
    push cx                                      # save number of requested sectors
    push offset _disk_lba_read_error

    xor si, si
    mov ds, si
    mov si, offset packet                        # ds:si points to packet struct
    mov ah, 0x42
    mov dl, byte ptr [boot_media]
    clc
    int 0x13                                     # read data from disk to 0:0x7e00

    jc load_finished
    # jc error_code                                # carry bit set on error
    pop ax
    pop cx                                       # restore number of requested sectors
    cmp cx, [packet_sector_count]                # make sure number of sectors read equals number of requested sectors
    jnz error
    pop ax
    pop bx

    add dword ptr [packet_block_low], ecx
    adc word ptr [packet_block_high], 0

    sub bx, cx

    shl cx, 9
    add word ptr [packet_buffer_offset], cx
    jnc same_segment

    add word ptr [packet_buffer_segment], 0x1000

same_segment:
    cmp bx, 0
    jnz 1b

load_finished:
    mov eax, offset stage_2
    jmp eax


# expects error context on stack
# expects error code in ah
error_code:
    pop si
    call bios_print_string
    mov si, offset _error_code
	call bios_print_string
	movzx dx, ah
	call print_hex16                      # print out the error code in ah
	jmp hang16


# address of string in si
# video page in bh, only matters in text modes
# clobbers ax, si
# returns nothing
bios_print_string:
    push ax
    push bx
    mov ah, 0x0e                        # int 0x10, print character and move cursor
    mov bx, VIDEO_PAGE << 8 | TERMINAL_COLOR
1:  lodsb
    int 0x10
    cmp byte ptr [si], 0
    jne 1b
    pop bx
    pop ax
    ret


# number in dx
# clobbers dx
# returns nothing
print_hex16:
    push cx
    mov cl, 4
1:  mov al, dh
    and al, 0xf0
    shr al, 4

hexchar:
    cmp al, 10
    jb hexchar_digit
    add al, 0x37
    jmp hexchar_end
hexchar_digit:
    add al, 0x30
hexchar_end:

    call bios_print_char
    shl dx, 4
    dec cl
    jnz 1b
    mov al, 'h'
    call bios_print_char
    pop cx
    ret


# character in al
# clobbers bx
# returns nothing
# outputs character to screen using bios int 0x10,ah=0x0e
bios_print_char:
    mov ah, 0x0e
    mov bx, VIDEO_PAGE << 8 | TERMINAL_COLOR
    int 0x10
    ret


# expects error string on the top of the stack
error:
    pop si
    call bios_print_string


hang16:
    jmp hang16


boot_media: .byte  0

    .align 4
# https://wiki.osdev.org/Disk_access_using_the_bios_(INT_13h)
packet:
packet_size:            .byte  16        # size of packet
                        .byte  0         # must be zero
packet_sector_count:    .2byte 0         # of sectors to read/write
packet_buffer_offset:   .2byte 0x7E00    # segment offset
packet_buffer_segment:  .2byte 0x0000    # segment
packet_block_low:       .4byte 1         # lower 32 bits of lba number
packet_block_high:      .2byte 0         # upper 16 bits of lba number
                        .2byte 0         # padding

_int13h_ext_nsupported: .asciz "int 13h extensions not supported:"
_sectors_not_equal:     .asciz "# of sectors read don't match the number of sector requested:"
_error_code:            .asciz "error code:"
_disk_lba_read_error:   .asciz "int 13h read:"

    .org 510
    .word 0xaa55

    .att_syntax prefix
