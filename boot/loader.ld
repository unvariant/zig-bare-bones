ENTRY(_loader_start)

SECTIONS
{
    . = 0x7E00;
    .loader : {
        KEEP(*(.loader))
    }
}