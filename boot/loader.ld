ENTRY(_loader_start)

SECTIONS
{
    .boot (0x7C00) (NOLOAD) : {
        *(.boot)
    }

    .loader (0x7E00) : {
        KEEP(*(.loader))
    }
}