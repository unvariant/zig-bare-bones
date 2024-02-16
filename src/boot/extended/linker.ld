ENTRY(_extended_entry)

SECTIONS {
    /* bootstrap start */
    __alloc_start = 0x1000;

    . = 0x7E00;
    .entry : { KEEP(*(.entry.*)) }

    .text   : { KEEP(*(.text)) }
    .rodata : { KEEP(*(.rodata)) }
    .data   : { KEEP(*(.data)) }
    .bss    : { KEEP(*(.bss)) }

    .boot16 : { KEEP(*(.boot16)) }
    .vesa   : { KEEP(*(.vesa)) }
}