define newline


endef

TARGET_DIR = $(shell pwd)
FILES = $(foreach file, $(wildcard $(TARGET_DIR)/*.s), $(file))
STRIPPED = $(basename $(FILES))
OBJECTS = $(foreach file, $(STRIPPED), $(file).o)

build:
	$(foreach path, $(STRIPPED),\
		x86_64-elf-as $(path).s -o $(path).o $(newline)\
	)
	llvm-ar --format=gnu -rcs libsymbols.a $(OBJECTS)
	$(foreach path, $(STRIPPED),\
		x86_64-elf-ld $(path).o -o $(path).elf -no-pie -T $(path).ld -L. -lsymbols --no-warn-rwx-segments $(newline)\
		llvm-objcopy -I elf64-x86-64 -O binary $(path).elf $(path).bin $(newline)\
	)
