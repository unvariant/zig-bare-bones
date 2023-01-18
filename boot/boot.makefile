define newline


endef

TARGET_DIR = $(shell pwd)
FILES = $(foreach file, $(wildcard $(TARGET_DIR)/*.s), $(file))
STRIPPED = $(basename $(FILES))

build:
	$(foreach path, $(STRIPPED),\
		x86_64-elf-as $(path).s -o $(path).o $(newline)\
		x86_64-elf-ld $(path).o -o $(path).elf -T $(path).ld --no-warn-rwx-segments $(newline)\
		llvm-objcopy -I elf64-x86-64 -O binary $(path).elf $(path).bin $(newline)\
	)
