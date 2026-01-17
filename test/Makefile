TOOLCHAIN_PREFIX = riscv64-unknown-elf-
CC = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy

# Basic flags
CFLAGS = -march=rv32im -mabi=ilp32 -O0 -nostdlib 
# Library path
# LIBGCC_PATH = /usr/lib/gcc/riscv64-unknown-elf/13.2.0/rv32i/ilp32

PROG ?= vector_mul

all: ../naive/sim/inst_rom.data

../naive/sim/inst_rom.data: $(PROG).bin
	@echo "Generating hex file from $(PROG).bin..."
	hexdump -v -e '1/4 "%08x" "\n"' $(PROG).bin > ../naive/sim/inst_rom.data
	@echo "Done. Output written to ../naive/sim/inst_rom.data"

# New rule for Tomasulo CPU (Standard Verilog Hex)
../tomasulo/sim/inst_rom.hex: $(PROG).elf
	$(OBJCOPY) -O verilog $< $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.elf: start.S src/%.c link.ld
	$(CC) $(CFLAGS) -T link.ld start.S src/$*.c -o $@ -lgcc

clean:
	rm -f *.elf *.bin ../naive/sim/inst_rom.data ../tomasulo/sim/inst_rom.hex

help:
	@echo "Usage:"
	@echo "  make PROG=fib       - Compile fib.c and generate inst_rom.data"
	@echo "  make PROG=vector_mul - Compile vector_mul.c (default)"
	@echo "  make clean          - Remove generated files"

# Simulation Target for Tomasulo M-Ext
sim:
	iverilog -o ../tomasulo/sim/out.vvp -I ../tomasulo/src ../tomasulo/sim/testbench.v ../tomasulo/src/*.v
	vvp ../tomasulo/sim/out.vvp +HEX_FILE=../tomasulo/sim/inst_rom.hex
