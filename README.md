# RISC-V CPU Implementation

This repository contains the final project for the CS2957 Computer Architecture course. It features two RISC-V CPU implementations in Verilog:
1.  **Naive CPU**: A classic five-stage pipelined processor.
2.  **Tomasulo CPU**: An advanced Out-of-Order (OoO) processor based on the Tomasulo algorithm with Reorder Buffer (ROB).

Both CPUs support the **RV32I** base integer instruction set. The Tomasulo CPU additionally supports the **RV32M** extension (hardware multiplication and division).

## Features

### 1. Naive CPU
*   **Architecture**: Classic 5-stage pipeline (IF, ID, EX, MEM, WB).
*   **Hazard Handling**: Data forwarding and stalling logic.
*   **Branch Prediction**: Static prediction.

### 2. Tomasulo CPU (Out-of-Order)
*   **Algorithm**: Tomasulo with Reorder Buffer (ROB) for In-Order Commit.
*   **Frontend**:
    *   **Fetch Unit**: Fetches instructions from memory.
    *   **Branch Prediction**: 
        *   **BHT (Branch History Table)**: 2-bit Saturating Counter for direction prediction.
        *   **BTB (Branch Target Buffer)**: Functioning as a cache for branch targets.
*   **Issue Logic**:
    *   Decodes instructions and dispatches them to Reservation Stations (RS), Load-Store Buffer (LSB), and allocates ROB entries.
    *   Handles Register Renaming using ROB IDs.
*   **Execution Units**:
    *   **ALU**: Arithmetic and Logic Unit.
    *   **MDU**: Multiplier/Divider Unit (Pipelined Multiplier).
    *   **Reservation Stations (RS)**: Buffers instructions waiting for operands. Snoops the Common Data Bus (CDB).
    *   **Load-Store Buffer (LSB)**: Buffers memory operations.
*   **Commit**:
    *   **Reorder Buffer (ROB)**: Ensures instructions are retired in program order to maintain precise exceptions.
    *   Updates the Architectural Register File (ARF) and handles Branch Misprediction (Flush).

## Directory Structure

```text
.
├── naive/                  # Naive 5-Stage Pipeline CPU
│   ├── src/                # Verilog source files
│   ├── sim/                # Simulation files
│   └── doc/                # Documentation
├── tomasulo/               # Tomasulo Out-of-Order CPU
│   ├── src/                # Verilog source files
│   ├── sim/                # Simulation files
│   └── doc/                # Specific documentation (Debug, M-Ext, etc.)
├── test/                   # Test Framework & Source Code
│   ├── src/                # C Assembly test cases
│   ├── Makefile            # Build compilation script
│   └── start.S             # Boot code
├── testcases/              # Pre-compiled test dumps and sources
├── doc/                    # General Documentation
│   ├── Instructions.md     # ISA Reference
│   └── ...
├── final_test.py           # Python script for batch testing Naive CPU
├── final_test_tomasulo.py  # Python script for batch testing Tomasulo CPU
└── README.md               # Project Documentation
```

## Prerequisites

To build and simulate the CPUs, you need the following tools installed:

1.  **Icarus Verilog (`iverilog`)**: For compiling and simulating Verilog designs.
2.  **RISC-V GNU Toolchain (`riscv64-unknown-elf-gcc`)**: For compiling C/Assembly test cases to RISC-V binaries.
    *   Ensure it supports `rv32i` and `rv32im` architectures.
3.  **Python 3**: For running test scripts.
4.  **Make**: For build automation.

## How to Run

### 1. Running Standard Benchmarks (Tomasulo)

You can run the provided automated test script which compiles test cases, builds the simulator, and verifies the output.

```bash
python3 final_test_tomasulo.py
```

This script will:
*   Build the Verilog simulator using `iverilog`.
*   Compile C test cases (like `sum`, `vector_add`, `vector_mul`) using `riscv64-unknown-elf-gcc`.
*   Run the simulation and check the result against expected values.

### 2. Running Individual Tests Manually

You can also compile and run specific tests manually.

**Step 1: Compile the test program**
Navigate to the `test/` directory and use `make` to compile a program (e.g., `vector_mul`).

```bash
cd test
# For standard RV32I tests
make PROG=vector_mul

# For RV32M tests (Multiplication/Division)
# Adjust LIBGCC_PATH to point to your toolchain's library location if needed
make PROG=m_extension_test CFLAGS="-march=rv32im -mabi=ilp32 -O2 -nostdlib" LIBGCC_PATH="/path/to/libgcc.a"
```
This generates `inst_rom.data` (hex file) in `../naive/sim/`.

**Step 2: Copy the ROM file**
Copy the generated instruction memory file to the Tomasulo simulation directory.

```bash
cp ../naive/sim/inst_rom.data ../tomasulo/sim/inst_rom.data
```

**Step 3: Run the Simulation**
Navigate to the simulation directory and run `iverilog`.

```bash
cd ../tomasulo/sim
iverilog -I ../src -o testbench.vvp testbench.v ../src/*.v
vvp testbench.vvp
```

### 3. Verification of Out-of-Order Execution

To verify the OoO capability specifically (observing instruction issue vs. completion times), you can run the special `ooo_test`:

```bash
cd test
# Create/Update src/ooo_test.c first (see issue log)
make PROG=ooo_test CFLAGS="-march=rv32im -mabi=ilp32 -O0 -nostdlib"
cp ../naive/sim/inst_rom.data inst_rom.data
make sim > simulation.log
```
Check `simulation.log` for `[ISSUE]` and `[COMPL]` timestamps.