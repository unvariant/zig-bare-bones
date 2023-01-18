# zig-os
(Currently it is only a bootloader)
- [bootloader](#bootloader)
- [master bootsector](#master-bootsector)
- [filesystem](#filesystem)
- [project structure](#project-structure)

## Bootloader
### What works:
- long mode
- reading e820 memory map
- enabling a20 line
- interrupts
	- pic irqs remapped
		- primary irqs: ```0x20 .. 0x28```
		- secondary irqs: ```0x28 .. 0x30```
- atapio disk reading
- locating rsdt
- paging
### Unimplemented:
- vesa framebuffer
- parsing FAT32 filesystem

## Master Bootsector
- first sector on disk
### Behavior:
- searches partitions 1-4 for an active partition
	- if an active partition is found, the first sector is loaded and executed
	- otherwise do nothing and hang
### TODO:
- allow user to select partition to boot from if no active partitions are found

## Filesystem
- currently only supports FAT32
### Partition Bootsector
- expects to be loaded by master bootsector
#### Behavior:
- searches FAT32 filesystem for `/BOOT/LOADER.BIN` second stage loader
	- if found, the first sector of that file is loaded and executed
	- otherwise a single digit error code is displayed

## Project Structure
The project structure is all over the place right now, I am in the process of documenting my code and cleaning up the structure.
- `disk/`
	- `boot/`
		- `loader.bin`
			- loads and executes main bootloader
	- `config.txt`
		- boot configuration options should go here
- `arch/`
	- architecture specific code
	- `x86_64/`
		- x86_64 specific code
		- `asm/`
			- bootloader that sets up long mode and passes control to zig bootloader
		- `fat32`
			- should be removed
- `boot/`
	- contains disk bootloaders
	- `mbrsector.asm`
		- generic master bootsector for booting from disk
		- written using NASM syntax, compiles to `boot/mbrsector.bin`
	- `bootsector.asm`
		- FAT32 specific partition sector, searches FAT32 partition for `/BOOT/LOADER.BIN` and executes it at address `0x7E00`
		- written using NASM syntax, compiles to `boot/bootsector.bin`
- `src/`
	- main bootloader code
	- the name of the file describes what aspect of the bootloader the file handles
	- `paging/`
		- code to handle paging
		- only supports identity mapping physical memory
		- can only allocate up to 32 page map tables (pml4, pdp, pde, pt, etc)
- `build.zig`
	- compiles assembly and zig parts of the main bootloader together
	- creates a unified binary in `zig-out/bin/bootloader.bin` that contains the main bootloader
	- `zig build run` should build an run the project in qemu (current not working, implementing filesystem bootloader)
- `Makefile`
	- `make image`
		- note: uses hdiutil, which is only available on macos
		- creates `boot.dmg`, a 48 MiB disk image with a single FAT32 partition
	- `make run`
		- copies `boot/mbrsector.bin` (master bootsector) into `boot.dmg`
		- locates an copies `boot/bootsector.bin` (partition bootsector) into the first active partition
		- runs the project in qemu
- `create_bootable_partition.py`
	- quick and dirty script that parses `boot.dmg`, marks the first partition it finds with non-zero length as active and copies `boot/bootsector.bin` into the first sector of that partition
- `kernel.elf`
	- test kernel to load by main bootloader
- `linker.ld`
	- describes memory layout of main bootloader