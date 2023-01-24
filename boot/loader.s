    .intel_syntax noprefix
    .section .loader, "awx"
    .code16

    
    .global  _loader_start


    .extern  map_directory
    .extern  read_sector
    .extern  root_cluster_number
    .extern  file_closure_pointer
    .extern  compare_file
    .extern  file_attribute
    .extern  file_name
    .extern  bytes_per_sector


_loader_start:
    mov   sp,    0x7C00
    call  root_file

    mov   bx,    offset target
    mov   dl,    0x20
    call  find_file
    jc    fserror

    mov   cx,    32
    call  print_hex

    mov   edi,   0xA000
    call  read_file
    jc    rferror

    mov   esi,   offset target
    call  print_str

    jmp   hang

fserror:
    mov   si,    offset fserror_str
    call  print_str
    jmp   hang

rferror:
    mov   si,    offset rferror_str
    call  print_str
    jmp   hang

hang:
    jmp   hang


root_file:
    push ax
    mov   esi,   offset root_entry
    mov   ax,    word ptr [root_cluster_number]
    mov   word ptr [esi + 26], ax
    mov   ax,    word ptr [root_cluster_number + 2]
    mov   word ptr [esi + 20], ax
    pop ax
    ret


/*
 * find_file
 *     - esi: directory entry to search
 *     - bx: filename
 *     - dl: file attribute
 * return:
 *     - carry flag set on error
 *     - otherwise esi holds file entry
 */
find_file:
    push  edx
    push  ebx

    mov   byte ptr [file_attribute], dl
    mov   word ptr [file_name], bx

    mov   dword ptr [file_closure_pointer], offset compare_file
    shl   word ptr [file_closure_pointer + 2], 12

    mov   bx,    word ptr [esi + 20]
    shl   ebx,   16
    mov   bx,    word ptr [esi + 26]

    call  map_directory

    pop   ebx
    pop   edx
    ret

/*
 * read_file
 *     - edi: destination offset
 *     - esi: file entry
 * return:
 *     - carry flag set on error
 */
read_file:
    pushad

    mov   eax,   dword ptr [esi + 28]
    mov   dword ptr [read_file_closure$size], eax
    mov   dword ptr [read_file_closure$destination], edi

    mov   dword ptr [file_closure_pointer], offset read_file_closure
    shl   word ptr [file_closure_pointer + 2], 12

    mov   bx,    word ptr [esi + 20]
    shl   ebx,   16
    mov   bx,    word ptr [esi + 26]

    call  map_directory

    popad
    ret


read_file_closure:
    pushad

    movzx eax,   word ptr [bytes_per_sector]

    movzx esi,   bx
    mov   edi,   dword ptr [read_file_closure$destination]
    mov   ecx,   eax
    cmp   ecx,   dword ptr [read_file_closure$size]
    cmovg ecx,   dword ptr [read_file_closure$size]
    .byte 0x66
    rep   movsb

    add   dword ptr [read_file_closure$destination], eax
    sub   dword ptr [read_file_closure$size], eax
    lahf
    xor   ah,    1
    sahf

    popad
    ret

read_file_closure$size: .4byte 0
read_file_closure$destination: .4byte 0


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


root_entry: .space 32
fserror_str: .asciz "fs error"
rferror_str: .asciz "rf error"
target: .ascii "CONFIG     "
