ENTRY(_entry)

SECTIONS {
    . = 0x7C00;

    __parameters = .;
    __jmp = .;
    . = . + 3;
    __oem = .;
    . = . + 8;
    __bytes_per_sector = .;
    . = . + 2;
    __sectors_per_cluster = .;
    . = . + 1;
    __reserved_sectors = .;
    . = . + 2;
    __fats = .;
    . = . + 1;
    __root_entries = .;
    . = . + 2;
    __sectors_count = .;
    . = . + 2;
    __type = .;
    . = . + 1;
    __sectors_per_fat = .;
    . = . + 2;
    __sectors_per_track = .;
    . = . + 2;
    __heads = .;
    . = . + 2;
    __hidden_sectors = .;
    . = . + 4;
    __large_sector_count = .;
    . = . + 4;

    __extended_parameters = .;
    . = 0x7C00 + 90;

    .bootsector : { KEEP(*(.bootsector)) }

    .text   : { KEEP(*(.text.*)) }
    .rodata : { KEEP(*(.rodata.*)) }
    .data   : { KEEP(*(.data.*)) }
    .bss    : { KEEP(*(.bss.*)) }

    . = 0x7C00 + 510;
    .magic : { SHORT(0xAA55) }
}