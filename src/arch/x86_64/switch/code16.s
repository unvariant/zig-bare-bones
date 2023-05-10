    .intel_syntax noprefix
    .section .boot16, "awx"
	.code16

    .global _code_16
    .global print_hex
    .global print_str
    .global e820_memory_map_len
    .global gdt32_desc
    .global gdt32_offset_code
    .global gdt32_offset_data


    .extern read_file
    .extern find_file
    .extern print_str
    .extern print_hex

    .extern _code_32

    .equ TERMINAL_COLOR, 0x0F
    .equ VIDEO_PAGE,     0x00

.macro ret2 arg
    .att_syntax prefix
    retw \arg
    .intel_syntax noprefix
.endm

.macro call2 arg
    .att_syntax prefix
    callw \arg
    .intel_syntax noprefix
.endm


_code_16:
    cli
    cld
    xor   ax,    ax             # zero all the registers
    mov   ds,    ax
    mov   es,    ax
    mov   ss,    ax
    mov   fs,    ax
    mov   gs,    ax

    mov   sp,    0x7C00         # set stack top to the start of the bootloader, stack grows down

check_A20:                 # fast A20 enable, may not work on all chipsets
    in    al,    0x92
    test  al,    0b00000010
    jnz   A20_set
    or    al,    0b00000010
    and   al,    0b11111110
    out   0x92,  al
A20_set:

    mov   di,    offset __e820_memory_map
    call2 do_e820
	jnc   e820_success

    mov   si,    offset _e820_fail
    call2 print_str
0:  jmp   0b

e820_success:
	mov   word ptr [e820_memory_map_len], bp

	# load vga font bitmap into memory so error messages can be displayed
	# after switching to vesa graphics mode
	# this is only needed during boot process, kernel can define custom font bitmap
	# bh=6, returns pointer to font bitmap in es:bp
	push  ds
	mov   ax,    0x1130
	mov   bh,    6
	int   0x10

	push  es
	pop   ds
	mov   si,    bp
	xor   di,    di
	mov   es,    di
	mov   di,    offset __font_map
	mov   cx,    256*16/4           # 256 characters, 16 bytes per char, divide by four
                                    # because moving data in blocks of four bytes
	rep   movsd                     # store vga 8x16 font bitmap at 0x6000
	pop   ds

    call2 vesa

    lgdt  [gdt32_desc]
    mov   eax,   cr0
    or    al,    1
    mov   cr0,   eax

    push  offset gdt32_offset_code
    mov   eax,   offset _code_32
    push  eax
    retf


print_str:
    pushad
    lodsb
    test  al,    al
    jz    0f
    mov   bx,    0x000F
    mov   ah,    0x0E
1:
    int   0x10
    lodsb
    test  al,    al
    jnz   1b
0:
    mov   al,    '\r'
    int   0x10
    mov   al,    '\n'
    int   0x10
    popad
    ret


print_hex:
    pushad
    mov   bp,    sp

    test  cx,    cx
    jz    0f
1:
    lodsb
    mov   ah,    al
    shr   ah,    4
    and   al,    0x0F
    call  hex
    xchg  ah,    al
    call  hex
    push  ax
    dec   cx
    jnz   1b
0:
    mov   si,    sp
    call  print_str

    mov   sp,    bp
    popad
    ret


hex:
    add   al,    '0'
    cmp   al,    '9'
    jle   1f
    add   al,     'A' - '0' - 10
1:
    ret


# uses eax = 0xe820, int 15h to get memory map
# returns number of entries in bp
# places memory map at es:di
do_e820:
	xor   ebx,   ebx		           # ebx must be 0 to start
	xor   bp,    bp		               # keep an entry count in bp
	mov   edx,   0x0534D4150	       # Place "SMAP" into edx
	mov   eax,   0xe820
	mov   dword ptr es:[di + 20], 1    # force a valid ACPI 3.X entry
	mov   ecx, 24		               # ask for 24 bytes
	int   0x15
	jc    short .failed	               # carry set on first call means "unsupported function"
	mov   edx, 0x0534D4150	           # Some BIOSes apparently trash this register?
	cmp   eax, edx		               # on success, eax must have been reset to "SMAP"
	jne   short .failed
	test  ebx, ebx		               # ebx = 0 implies list is only 1 entry long (worthless)
	je    short .failed
	jmp   short .jmpin
.e820lp:
	mov   eax,    0xe820		       # eax, ecx get trashed on every int 0x15 call
	mov   dword ptr es:[di + 20], 1    # force a valid ACPI 3.X entry
	mov   ecx,    24		           # ask for 24 bytes again
	int   0x15
	jc    short .e820f		           # carry set means "end of list already reached"
	mov   edx,   0x0534D4150	       # repair potentially trashed register
.jmpin:
	jcxz  .skipent		               # skip any 0 length entries
	cmp   cl, 20		               # got a 24 byte ACPI 3.X response?
	jbe   short .notext
	test  byte ptr es:[di + 20], 1     # if so: is the "ignore this data" bit clear?
	je    short .skipent
.notext:
	mov   ecx,   es:[di + 8]	       # get lower uint32_t of memory region length
	or    ecx,   es:[di + 12]	       # "or" it with upper uint32_t to test for zero
	jz    .skipent		               # if length uint64_t is 0, skip entry
	inc   bp			               # got a good entry: ++count, move to next storage spot
	add   di,   24
.skipent:
	test  ebx, ebx		               # if ebx resets to 0, list is complete
	jne   short .e820lp
.e820f:
	clc			                       # there is "jc" on end of list to this point, so the carry must be cleared
	ret2                               # returns the number of entries in bp
.failed:
	stc			                       # "function unsupported" error exit
    ret2


debugging: .asciz "here! Ldfajsldfkajsdlfkjasdflakjsdflka"

e820_memory_map_len: .8byte 0
_e820_fail: .asciz "e820 unsupported."

# https://web.archive.org/web/20190424213806/http://www.osdever.net/tutorials/view/the-world-of-protected-mode
gdt32:
# 0 byte offset
gdt32_null:
    .8byte 0             # null segment

# 8 byte offset
gdt32_code:
    .2byte 0xffff        # segment limit
    .2byte 0             # base limit
    .byte  0             # base limit continued...
    .byte  0b10011010    # access flags
    .byte  0b11001111
    .byte  0

# 16 byte offset
gdt32_data:
    .2byte 0xffff        # segment limit
    .2byte 0             # base limit
	.byte  0             # base limit continued...
	.byte  0b10010010    # access flags
	.byte  0b11001111
    .byte  0
gdt32_end:

gdt32_desc:                      # gdt descriptor
	.2byte gdt32_end - gdt32 - 1 # size of gdt
	.4byte gdt32                 # address of gdt

    .equ gdt32_offset_code, gdt32_code - gdt32
    .equ gdt32_offset_data, gdt32_data - gdt32


    .att_syntax prefix
