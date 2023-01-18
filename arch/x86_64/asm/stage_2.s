    .intel_syntax noprefix

    .section .boot, "awx"
    .code16

    .extern error
    .extern stage_3

    .global stage_2
    .global e820_memory_map_len
	.global gdt32_offset_data

stage_2:
	push _e820_fail
    xor di, di
    mov es, di
    mov di, offset e820_memory_map  # place memory map after page table
    call do_e820
	jc error
	pop ax
	mov word ptr [e820_memory_map_len], bp
    

	# load vga font bitmap into memory so error messages can be displayed
	# after switching to vesa graphics mode
	# this is only needed during boot process, kernel can define custom font bitmap
	# bh=6, returns pointer to font bitmap in es:bp
	push ds
	mov ax, 0x1130
	mov bh, 6
	int 0x10

	push es
	pop ds
	mov si, bp
	xor di, di
	mov es, di
	mov di, 0x6000
	mov cx, 256*16/4                # 256 characters, 16 bytes per char, divide by four
                                    # because moving data in blocks of four bytes
	rep movsd                       # store vga 8x16 font bitmap at 0x6000
	pop ds

    cli
    lgdt [gdt32_desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax

    push offset gdt32_offset_code
    mov eax, offset stage_3
    push eax
    retf

# uses eax = 0xe820, int 15h to get memory map
# returns number of entries in bp
# places memory map at es:di
do_e820:
	xor ebx, ebx		           # ebx must be 0 to start
	xor bp, bp		               # keep an entry count in bp
	mov edx, 0x0534D4150	       # Place "SMAP" into edx
	mov eax, 0xe820
	mov dword ptr es:[di + 20], 1  # force a valid ACPI 3.X entry
	mov ecx, 24		               # ask for 24 bytes
	int 0x15
	jc short .failed	           # carry set on first call means "unsupported function"
	mov edx, 0x0534D4150	       # Some BIOSes apparently trash this register?
	cmp eax, edx		           # on success, eax must have been reset to "SMAP"
	jne short .failed
	test ebx, ebx		           # ebx = 0 implies list is only 1 entry long (worthless)
	je short .failed
	jmp short .jmpin
.e820lp:
	mov eax, 0xe820		           # eax, ecx get trashed on every int 0x15 call
	mov dword ptr es:[di + 20], 1  # force a valid ACPI 3.X entry
	mov ecx, 24		               # ask for 24 bytes again
	int 0x15
	jc short .e820f		           # carry set means "end of list already reached"
	mov edx, 0x0534D4150	       # repair potentially trashed register
.jmpin:
	jcxz .skipent		           # skip any 0 length entries
	cmp cl, 20		               # got a 24 byte ACPI 3.X response?
	jbe short .notext
	test byte ptr es:[di + 20], 1  # if so: is the "ignore this data" bit clear?
	je short .skipent
.notext:
	mov ecx, es:[di + 8]	       # get lower uint32_t of memory region length
	or ecx, es:[di + 12]	       # "or" it with upper uint32_t to test for zero
	jz .skipent		               # if length uint64_t is 0, skip entry
	inc bp			               # got a good entry: ++count, move to next storage spot
	add di, 24
.skipent:
	test ebx, ebx		           # if ebx resets to 0, list is complete
	jne short .e820lp
.e820f:
	clc			                   # there is "jc" on end of list to this point, so the carry must be cleared
	ret                            # returns the number of entries in bp
.failed:
	stc			                   # "function unsupported" error exit
	ret

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
