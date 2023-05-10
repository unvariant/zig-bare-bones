ENTRY(_loader_start)

SECTIONS
{
    .bootsector(0x7C00) : {
        *(.bootsector)
    }

    .loader (0x7E00) : {
        KEEP(*(.loader))
    }
}