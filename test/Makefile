TOOLCHAIN_PREFIX = riscv64-unknown-elf-
CC = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy

CFLAGS = -march=rv32i -mabi=ilp32 -O2 -nostdlib

PROG ?= vector_mul

all: ../naive/sim/inst_rom.data

../naive/sim/inst_rom.data: $(PROG).bin
	@echo "Generating hex file from $(PROG).bin..."
	hexdump -v -e '1/4 "%08x" "\n"' $(PROG).bin > ../naive/sim/inst_rom.data
	@echo "Done. Output written to ../naive/sim/inst_rom.data"

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.elf: start.S src/%.c link.ld
	$(CC) $(CFLAGS) -T link.ld start.S src/$*.c -o $@

clean:
	rm -f *.elf *.bin ../naive/sim/inst_rom.data

help:
	@echo "Usage:"
	@echo "  make PROG=fib       - Compile fib.c and generate inst_rom.data"
	@echo "  make PROG=vector_mul - Compile vector_mul.c (default)"
	@echo "  make clean          - Remove generated files"
