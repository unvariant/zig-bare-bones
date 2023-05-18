ENTRY(_extended_entry)

SECTIONS {
    . = 0x7E00;
    .entry : { KEEP(*(.entry)) }
    
    .text   : { KEEP(*(.text.*)) }
    .rodata : { KEEP(*(.rodata.*)) }
    .data   : { KEEP(*(.data.*)) }
    .bss    : { KEEP(*(.bss.*)) }
}