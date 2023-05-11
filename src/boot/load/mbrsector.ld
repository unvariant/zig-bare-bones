ENTRY(_mbr_relocate)

SECTIONS
{
    . = 0x600;
    .mbrsector : {
        KEEP(*(.mbrsector))
    }

    . = 0x7C00;
    .bootsector : {
        KEEP(*(.bootsector))
    }
}