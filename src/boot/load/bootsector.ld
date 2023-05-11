ENTRY(_boot_start)

SECTIONS
{
    . = 0x7C00;
    .bootsector : {
        KEEP(*(.bootsector))
    }
}