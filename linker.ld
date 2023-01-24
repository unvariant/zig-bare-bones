ENTRY(_boot_start)

SECTIONS
{    
    font_map = 0x1000;
    e820_memory_map = 0x7000;

    .boot (0x7C00) (NOLOAD) : {
        *(.boot)
    }

    .loader (0x7E00) (NOLOAD) : {
        *(.loader)
    }

    . = 0x8000;
    __boot_start = .;
    .bootsect : {
        KEEP(*(.bootsect))
    }

    . = ALIGN(4K);
    __page_table_memory_start = .;
    . = . + 64 * 0x1000;
    __page_table_memory_end = .;

    .text : ALIGN(4K) {
        *(.text)
    }

    .rodata : ALIGN(4K) {
        *(.rodata)
        __debug_info_start = .;
        KEEP(*(.debug_info))
        __debug_info_end = .;
        __debug_abbrev_start = .;
        KEEP(*(.debug_abbrev))
        __debug_abbrev_end = .;
        __debug_str_start = .;
        KEEP(*(.debug_str))
        __debug_str_end = .;
        __debug_line_start = .;
        KEEP(*(.debug_line))
        __debug_line_end = .;
        __debug_ranges_start = .;
        KEEP(*(.debug_ranges))
        __debug_ranges_end = .;
    }

    .data : ALIGN(4K) {
        *(.data)
    }

    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss)
    }

    __boot_end = .;
    __boot_sectors = (__boot_end - __boot_start) >> 9;
}