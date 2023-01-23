    .intel_syntax noprefix
    .section .loader, "awx"
    .code16

    
    .global  _loader_start


    .extern  map_directory
    .extern  read_sector
    .extern  root_cluster_number
    .extern  file_closure_offset
    .extern  file_closure_segment
    .extern  compare_file
    .extern  file_attribute
    .extern  file_name
    .extern  bytes_per_sector


_loader_start:/*
    mov   sp,    0x7C00
    mov   byte ptr [file_attribute], 0x20
    mov   word ptr [file_name], offset target

    mov   ebx,   dword ptr [root_cluster_number]
    call  map_directory
    jc    fserror
    
    mov   esi,   edi
    mov   edi,   0xA000
    call  read_file
    jc    rferror

    mov   si,    0xA000
    call  print_str

    jmp   hang*/

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


test_closure:
    pushad
    mov   si,    bx
    call  print_str
    popad
    ret


/*
 * find_file
 *     - ebx: parent directory cluster
 *     - si: 
 */
find_file:


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

    mov   dword ptr [file_closure_offset], offset read_file_closure
    shl   word ptr [file_closure_segment], 12

    movzx ebx,   word ptr [esi + 20]
    shl   ebx,   16
    mov   bx,    word ptr [esi + 26]

    mov   si,    offset read_file_closure$size
    mov   cx,    4
    call  print_hex
    mov   si,    offset read_file_closure$destination
    mov   cx,    4
    call  print_hex

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


fserror_str: .asciz "fs error"
rferror_str: .asciz "rf error"
target: .ascii "CONFIG     "
