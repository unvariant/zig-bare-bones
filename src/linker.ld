ENTRY(_code_16)

SECTIONS
{    
    __font_map = 0x1000;
    __e820_memory_map = 0x2000;

    .boot (0x7C00) (NOLOAD) : {
        *(.boot)
    }

    .loader (0x7E00) (NOLOAD) : {
        *(.loader)
    }

    .boot16 (0x8000) : {
        KEEP(*(.boot16))
    }
    .vesa : {
        KEEP(*(.vesa))
    }
    .boot32 : {
        KEEP(*(.boot32))
    }
    .boot64 : {
        KEEP(*(.boot64))
    }

    . = ALIGN(4K);
    __page_table_memory_start = .;
    . = . + 64 * 0x1000;
    __page_table_memory_end = .;

    .text : ALIGN(4K) {
        KEEP(*(.text))
    }

    .rodata : ALIGN(4K) {
        KEEP(*(.rodata))
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
}