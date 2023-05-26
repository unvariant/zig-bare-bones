    .intel_syntax noprefix
    .section .vesa, "awx"
    .code16


    .global vesa
    .global vesa_framebuffer
    .global vesa_width
    .global vesa_height
    .global vesa_pitch
    .global vesa_bits_per_pixel
    .global vesa_off_screen_offset
    .global vesa_off_screen_size


    .extern print_str
    .extern print_hex


vesa:
    push  es
    push  ds
    pushad

    xor   si,    si
    mov   ds,    si
    mov   si,    offset vesa$init_str
    call  print_str

    mov   ax,    0x4F00
    mov   di,    offset vbe_info
    call  vesa$call

    cmp   dword ptr [vbe_info], 'V' | ('E' << 8) | ('S' << 16) | ('A' << 24)
    jnz   vesa$error

    mov   di,    offset vbe_info$oem
    call  vesa$print_str
    mov   di,    offset vbe_info$vendor
    call  vesa$print_str
    mov   di,    offset vbe_info$name
    call  vesa$print_str
    mov   di,    offset vbe_info$product_revision
    call  vesa$print_str
    
    lds   si,    [vbe_info$modes]
vesa$iterate:
    mov   cx,    2
    call  print_hex

    lodsw
    cmp   ax,    0xFFFF
    jz    vesa$error

    mov   cx,    ax
    mov   ax,    0x4F01
    mov   di,    offset vbe_mode
    call  vesa$call

    cmp   word ptr [vbe_mode$width], 700
    jl    vesa$iterate

    cmp   word ptr [vbe_mode$height], 400
    jl    vesa$iterate

    cmp   byte ptr [vbe_mode$bpp], 32
    jnz   vesa$iterate

    xor   si,    si
    mov   ds,    si
    mov   si,    offset vesa$mode_found
    call  print_str

    mov   bx,    cx
    or    bx,    1 << 14
    mov   ax,    0x4F02
    mov   di,    0
    call  vesa$call

    xor   si,    si
    mov   ds,    si
    mov   si,    offset vesa$fini_str
    call  print_str

    popad
    pop   ds
    pop   es
    ret 

vesa$call:
    push  es
    int   0x10
    pop   es
    cmp   ax,    0x004F
    jnz   vesa$error
    ret 

vesa$error:
    xor   si,    si
    mov   ds,    si
    mov   si,    offset vesa$error_str
    call  print_str
0:  jmp   0b


vesa$print_str:
    push  ds
    lds   si,    [di]
    call  print_str
    pop   ds
    ret 


vesa$init_str: .asciz "beginning vesa scan"
vesa$fini_str: .asicz "finished vesa scan"
vesa$error_str: .asciz "vesa error occurred"
vesa$mode_found: .asciz "vesa mode found"

vbe_info:
vbe_info$signature:                .ascii "VBE2"
vbe_info$version:                  .2byte 0
vbe_info$oem:
vbe_info$oem$offset:               .2byte 0
vbe_info$oem$segment:              .2byte 0
vbe_info$capabilities:             .4byte 0
vbe_info$modes:
vbe_info$modes$offset:             .2byte 0
vbe_info$modes$segment:            .2byte 0
vbe_info$memory:                   .2byte 0
vbe_info$software_revision:        .2byte 0
vbe_info$vendor:
vbe_info$vendor$offset:            .2byte 0
vbe_info$vendor$segment:           .2byte 0
vbe_info$name:
vbe_info$name$offset:              .2byte 0
vbe_info$name$segment:             .2byte 0
vbe_info$product_revision:
vbe_info$product_revision$offset:  .2byte 0
vbe_info$product_revision$segment: .2byte 0
                     /* reserved */.space 222
vbe_info$oem_data:                 .space 256


vbe_mode:
vbe_mode$attributes:               .2byte 0
vbe_mode$window_a:                 .byte  0
vbe_mode$window_b:                 .byte  0
vbe_mode$granularity:              .2byte 0
vbe_mode$window_size:              .2byte 0
vbe_mode$segment_a:                .2byte 0
vbe_mode$segment_b:                .2byte 0
vbe_mode$window_switch_fn_ptr:     .4byte 0
vesa_pitch:
vbe_mode$pitch:                    .2byte 0
vesa_width:
vbe_mode$width:                    .2byte 0
vesa_height:
vbe_mode$height:                   .2byte 0
vbe_mode$w_char:                   .byte  0
vbe_mode$y_char:                   .byte  0
vbe_mode$planes:                   .byte  0
vesa_bits_per_pixel:
vbe_mode$bpp:                      .byte  0
vbe_mode$banks:                    .byte  0
vbe_mode$memory_model:             .byte  0
vbe_mode$bank_size:                .byte  0
vbe_mode$image_pages:              .byte  0
                    /* reserved */ .byte  0
vbe_mode$red_mask:                 .byte  0
vbe_mode$red_position:             .byte  0
vbe_mode$green_mask:               .byte  0
vbe_mode$green_position:           .byte  0
vbe_mode$blue_mask:                .byte  0
vbe_mode$blue_position:            .byte  0
vbe_mode$reversed_mask:            .byte  0
vbe_mode$reserved_position:        .byte  0
vbe_mode$direct_color_attributes:  .byte  0
vesa_framebuffer:
vbe_mode$framebuffer:              .4byte 0
vesa_off_screen_offset:
vbe_mode$off_screen_memory$offset: .4byte 0
vesa_off_screen_size:
vbe_mode$off_screen_memory$size:   .2byte 0
                    /* reserved */ .space 206


    .att_syntax prefix
