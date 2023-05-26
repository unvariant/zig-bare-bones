ENTRY(_extended_entry)

SECTIONS {
    /* bootstrap start */
    __font_map = 0x1000;
    __e820_memory_map = 0x2000;
    __vesa_height = 0x3000;
    __vesa_width  = 0x3004;
    __vesa_pitch  = 0x3008;
    __vesa_framebuffer = 0x300C;
    __e820_memory_map_len = 0x3010;
    /* bootstrap end */

    . = 0x7E00;
    .entry : { KEEP(*(.entry.*)) }

    .text   : { KEEP(*(.text)) }
    .rodata : { KEEP(*(.rodata)) }
    .data   : { KEEP(*(.data)) }
    .bss    : { KEEP(*(.bss)) }

    .boot16 : { KEEP(*(.boot16)) }
    .vesa   : { KEEP(*(.vesa)) }
}