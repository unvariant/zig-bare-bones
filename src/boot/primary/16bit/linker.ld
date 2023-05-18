ENTRY(_code_16)

SECTIONS {
    . = 0x7E00;

    .boot16 : { KEEP(*(.boot16)) }

    .text   : { KEEP(*(.text.*)) }
    .rodata : { KEEP(*(.rodata.*)) }
    .data   : { KEEP(*(.data.*)) }
    .bss    : { KEEP(*(.bss.*)) }
}