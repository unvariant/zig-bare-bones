ENTRY(_mbr_relocate)

SECTIONS
{
    . = 0x500;
    .mbr : {
        KEEP(*(.mbr))
    }
}