QEMU = qemu-system-x86_64\
		-no-reboot -no-shutdown\
		-vga virtio\
		-D qemu.log -d trace:ide_sector_read,trace:pic_interrupt,int,in_asm,unimp\
		-drive file=boot.dmg,format=raw

DEBUGGER_FLAGS = -s -S

build:
	@set -e
	make -C boot --file=boot.makefile build
	# zig build
	cp boot/loader.bin disk/boot/loader.bin
	cp zig-out/bin/bootloader.bin disk/boot/switch.bin
	
run:
	$(QEMU)

debug:
	$(QEMU) $(DEBUGGER_FLAGS)
		
image:
	hdiutil create -ov -size 48m -volname ZIG_OS -fs FAT32 -layout MBRSPUD -format UDRW -srcfolder disk boot
	python3 create_bootable_partition.py
	dd if=boot/mbrsector.bin of=boot.dmg conv=notrunc bs=446 count=1
	dd if=boot/mbrsector.bin of=boot.dmg conv=notrunc bs=1 count=2 skip=510 seek=510