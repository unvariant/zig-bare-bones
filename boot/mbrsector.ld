ENTRY(_mbr_relocate)

SECTIONS
{
    . = 0x600;
    .mbr : {
        KEEP(*(.mbr))
    }
}