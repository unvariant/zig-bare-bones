# link 32 and 64 bit code

This might seem a bit useless, but this has a genuine use case in my kernel bootloader. When the bootloader switches
out of real mode into protected mode, there has to be some code to perform the switch from protected mode to long mode.