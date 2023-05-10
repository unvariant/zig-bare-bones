    [BITS 16]
    section .loader progbits alloc exec write


    global  _loader_start
    global  print_str
    global  print_hex
    global  hang


    extern  map_directory
    extern  read_sector
    extern  root_cluster_number
    extern  file_closure_pointer
    extern  compare_file
    extern  file_attribute
    extern  file_name
    extern  bytes_per_sector


_loader_start:
    cli
    mov   sp,    0x7C00

    ;;; populate the root entry so find_file can search for it properly
    mov   esi,   root_entry
    mov   bx,    word [root_cluster_number]
    mov   word [esi + 26], bx
    mov   bx,    word [root_cluster_number + 2]
    mov   word [esi + 20], bx

    mov   bx,    boot_directory
    mov   dl,    0x10
    call  find_file
    jc    fserror

    mov   bx,    switch_binary
    mov   dl,    0x20
    call  find_file
    jc    fserror

    mov   edi,   0x8000
    call  read_file
    jc    rferror

    jmp   0x8000

;;; file system error
fserror:
    mov   si,    fserror_str
    call  print_str
.hang:
    jmp   .hang

;;; read file error
rferror:
    mov   si,    rferror_str
    call  print_str
.hang:
    jmp   .hang


;;
 ; find_file
 ;     - esi: directory entry to search
 ;     - bx: filename
 ;     - dl: file attribute
 ; return:
 ;     - carry flag set on error
 ;     - otherwise esi holds file entry
 ;;
find_file:
    push  edx
    push  ebx

    mov   byte [file_attribute], dl
    mov   word [file_name], bx

    mov   word [file_closure_pointer], compare_file

    mov   bx,    word [esi + 20]
    shl   ebx,   16
    mov   bx,    word [esi + 26]

    call  map_directory

    pop   ebx
    pop   edx
    ret

;;
 ; read_file
 ;     - edi: destination offset
 ;     - esi: file entry
 ; return:
 ;     - carry flag set on error
 ;;
read_file:
    pushad

    mov   eax,   dword [esi + 28]
    mov   dword [read_file_closure.size], eax
    mov   dword [read_file_closure.destination], edi

    mov   word [file_closure_pointer], read_file_closure

    mov   bx,    word [esi + 20]
    shl   ebx,   16
    mov   bx,    word [esi + 26]

    call  map_directory

    popad
    ret


read_file_closure:
    pushad

    movzx eax,   word [bytes_per_sector]

    movzx esi,   bx
    mov   edi,   dword [read_file_closure.destination]
    mov   ecx,   eax
    cmp   ecx,   dword [read_file_closure.size]
    cmovg ecx,   dword [read_file_closure.size]
    db 0x67
    rep   movsb

    add   dword [read_file_closure.destination], eax
    sub   dword [read_file_closure.size], eax
    jle   .ok
    mov   ah,    0xFF
    sahf
.done:
    popad
    ret

.ok:
    clc
    jmp   .done

.size: dd 0
.destination: dd 0


print_str:
    pushad
    lodsb
    test  al,    al
    jz    .newline
    mov   bx,    0x000F
    mov   ah,    0x0E
.loop:
    int   0x10
    lodsb
    test  al,    al
    jnz   .loop
.newline:
    mov   al,    `\r`
    int   0x10
    mov   al,    `\n`
    int   0x10
    popad
    ret


print_hex:
    pushad
    mov   bp,    sp

    test  cx,    cx
    jz    .break
.loop:
    lodsb
    mov   ah,    al
    shr   ah,    4
    and   al,    0x0F
    call  hex
    xchg  ah,    al
    call  hex
    push  ax
    dec   cx
    jnz   .loop
.break:
    mov   si,    sp
    call  print_str

    mov   sp,    bp
    popad
    ret


hex:
    add   al,    `0`
    cmp   al,    `9`
    jle   .digit
    add   al,     `A` - `0` - 10
.digit:
    ret


root_entry: times 32 db 0
fserror_str: db "fs error"
rferror_str: db "rf error"
boot_directory: db "BOOT       "
switch_binary:  db "SWITCH  BIN"

    times 512 - ($ - $$) db 0