TOOLCHAIN_PREFIX = riscv64-unknown-elf-
CC = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy

CFLAGS = -march=rv32i -mabi=ilp32 -O2 -nostdlib

all: ../naive/sim/inst_rom.data

../naive/sim/inst_rom.data: vector_mul.bin
	@echo "Generating hex file..."
	hexdump -v -e '1/4 "%08x" "\n"' vector_mul.bin > ../naive/sim/inst_rom.data
	@echo "Done. Output written to ../naive/sim/inst_rom.data"

vector_mul.bin: vector_mul.elf
	$(OBJCOPY) -O binary vector_mul.elf vector_mul.bin

vector_mul.elf: start.S src/vector_mul.c link.ld
	$(CC) $(CFLAGS) -T link.ld start.S src/vector_mul.c -o vector_mul.elf

clean:
	rm -f *.elf *.bin ../naive/sim/inst_rom.data

help:
	@echo "Usage:"
	@echo "  make        - Compile C code and generate inst_rom.data"
	@echo "  make clean  - Remove generated files"
