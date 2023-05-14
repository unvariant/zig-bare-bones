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

        __debug_info_lo = .;
        KEEP(*(.debug_info))
        __debug_info_hi = .;

        __debug_abbrev_lo = .;
        KEEP(*(.debug_abbrev))
        __debug_abbrev_hi = .;

        __debug_str_lo = .;
        KEEP(*(.debug_str))
        __debug_str_hi = .;

        __debug_str_offsets_lo = .;
        KEEP(*(.debug_str_offsets))
        __debug_str_offsets_hi = .;

        __debug_line_lo = .;
        KEEP(*(.debug_line))
        __debug_line_hi = .;

        __debug_line_str_lo = .;
        KEEP(*(.debug_line_str))
        __debug_line_str_hi = .;

        __debug_ranges_lo = .;
        KEEP(*(.debug_ranges))
        __debug_ranges_hi = .;

        __debug_loclists_lo = .;
        KEEP(*(.debug_loclists))
        __debug_loclists_hi = .;

        __debug_rnglists_lo = .;
        KEEP(*(.debug_rnglists))
        __debug_rnglists_hi = .;

        __debug_addr_lo = .;
        KEEP(*(.debug_addr))
        __debug_addr_hi = .;

        __debug_names_lo = .;
        KEEP(*(.debug_names))
        __debug_names_hi = .;

        __debug_frame_lo = .;
        KEEP(*(.debug_frame))
        __debug_frame_hi = .;
    }

    .data : ALIGN(4K) {
        *(.data)
    }

    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss)
    }

    . = ALIGN(4K);
    __end_of_bootloader = .;
    __start_of_heap = .;
}