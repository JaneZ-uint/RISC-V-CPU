import os
import subprocess
import sys
import re
import shutil
import argparse

# Paths
ROOT_DIR = os.getcwd()
TEST_DIR = os.path.join(ROOT_DIR, "test")
SRC_DIR = os.path.join(TEST_DIR, "src")
TESTCASES_DIR = os.path.join(ROOT_DIR, "testcases")
SIM_DIR = os.path.join(ROOT_DIR, "tomasulo", "sim")
LINK_SCRIPT = os.path.join(TEST_DIR, "link.ld")
START_ASM = os.path.join(TEST_DIR, "start.S")

# Tools
CC = "riscv64-unknown-elf-gcc"
OBJCOPY = "riscv64-unknown-elf-objcopy"

# Common Flags
CFLAGS_BASE = [
    "-mabi=ilp32",
    "-march=rv32im", 
    "-O0", 
    "-nostdlib", 
    "-I", SRC_DIR,
    "-I", TESTCASES_DIR
]

# Legacy Default Tests
DEFAULT_TESTS = [
    {"name": "sum", "expected": 5050, "arch": "rv32i"},
    {"name": "vector_add", "expected": 100, "arch": "rv32i"},
    {"name": "vector_mul", "expected": 100, "arch": "rv32i"}, 
    {"name": "m_extension_test", "expected": 4660, "arch": "rv32im"}
]

# Tests where we expect results in a0/x1 (judgeResult)
# If not listed here, assume expected=0 (Success)
EXPECTED_MAP = {
    "array_test1": 123,
    "array_test2": 43,
    "basicopt1": 88,
    "bulgarian": 159,
    "div_test": 0,
    "expr": 58,
    "gcd": 178,
    "hanoi":20,
    "magic":106,
    "lvalue2": 175,
    "manyarguments": 40,
    "mul_test":0,
    "multiarray": 115,
    "naive": 94,
    "pi":137,
    "qsort": 105,
    "queens":171,
    "statement_test": 50,
    "superloop": 134,
    "tak":186
}

SKIP_LIST = ['pi', 'basicopt1', 'qsort', 'superloop', 'tomasulo', 'bulgarian']

def run_cmd(cmd, cwd=None, timeout=None):
    # print(f"Running: {cmd}")
    if isinstance(cmd, list):
        # Join list for shell execution to support wildcards like *.v
        cmd_str = ' '.join(cmd)
        shell = True
    else:
        cmd_str = cmd
        shell = True
        
    try:
        result = subprocess.run(cmd_str, capture_output=True, text=True, cwd=cwd, shell=shell, timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"
        
    if result.returncode != 0:
        print(f"Error running {cmd_str}:")
        print(result.stderr)
        return False, result.stderr
    return True, result.stdout

def convert_to_rom(input_file, output_file):
    mem = {}
    current_addr = 0
    
    try:
        with open(input_file, 'r') as f:
            lines = f.readlines()
            
        for line in lines:
            line = line.strip()
            if not line: continue
            
            parts = line.split()
            for part in parts:
                if part.startswith('@'):
                    current_addr = int(part[1:], 16)
                else:
                    val = int(part, 16)
                    mem[current_addr] = val
                    current_addr += 1
                    
        if not mem:
            print("  Error: Empty memory file")
            return False
            
        max_addr = max(mem.keys())
        max_word_idx = max_addr // 4
        
        with open(output_file, 'w') as f:
            for k in range(0, max_word_idx + 1):
                base = k * 4
                b0 = mem.get(base, 0)
                b1 = mem.get(base + 1, 0)
                b2 = mem.get(base + 2, 0)
                b3 = mem.get(base + 3, 0)
                
                # Little Endian to Word
                word_val = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
                f.write(f"{word_val:08x}\n")
        return True
        
    except Exception as e:
        print(f"  Conversion Error: {e}")
        return False

def run_single_test(test):
    name = test["name"]
    expected = test["expected"]
    arch_flag = f"-march={test.get('arch', 'rv32im')}"
    
    print(f"\n[TEST: {name}]")
    
    # Determine Source
    if "src" in test:
        source_c = test["src"]
    else:
        # Auto-detect
        p1 = os.path.join(SRC_DIR, f"{name}.c")
        p2 = os.path.join(TESTCASES_DIR, f"{name}.c")
        if os.path.exists(p1): source_c = p1
        elif os.path.exists(p2): source_c = p2
        else:
            print(f"  Error: Source for {name} not found")
            return False

    output_elf = os.path.join(TEST_DIR, f"{name}.elf")
    output_data = os.path.join(TEST_DIR, f"{name}.data")
    rom_file = os.path.join(SIM_DIR, "inst_rom.data")
    
    # 1. Compile
    success, out = run_cmd([
        CC, arch_flag, *CFLAGS_BASE,
        "-T", LINK_SCRIPT, 
        START_ASM, source_c, 
        "-o", output_elf,
        "-lgcc"
    ])
    if not success: return False
    
    # 2. Convert to Hex
    success, out = run_cmd([OBJCOPY, "-O", "verilog", output_elf, output_data])
    if not success: return False
    
    # 3. Prepare ROM
    # Objcopy produces Verilog Hex compatible with $readmemh for 8-bit memory
    # We just need to copy it to the sim directory as inst_rom.hex
    dest_hex = os.path.join(SIM_DIR, "inst_rom.hex")
    try:
        shutil.copy(output_data, dest_hex)
    except Exception as e:
        print(f"  Error copying hex file: {e}")
        return False
    
    # 4. Simulate
    # Ensure Testbench Compiled (Lazy)
    # Recompile only if needed or force it to be safe (since we had issues)
    # Note: testbench references inst_rom.hex by default.
    if not os.path.exists(os.path.join(SIM_DIR, "testbench.vvp")):
        print("  Compiling Simulator...")
        success, out = run_cmd(["iverilog", "-I", "../src", "-o", "testbench.vvp", "testbench.v", "../src/*.v"], cwd=SIM_DIR)
        if not success: return False

    success, out = run_cmd(["vvp", "testbench.vvp"], cwd=SIM_DIR, timeout=60)
    if not success:
        if out == "TIMEOUT":
             print(f"  ❌ FAIL (TIMEOUT)")
        return False
    
    # 5. Check Result
    # Output format: "Result in x1 (Unsigned): <val>"
    match = re.search(r"Result in x1 \(Unsigned\):\s+(\d+)", out)
    branch_total = re.search(r"TOTAL_BRANCH:\s+(\d+)", out)
    branch_correct = re.search(r"CORRECT_BRANCH:\s+(\d+)", out)

    perf_info = ""
    if branch_total and branch_correct:
        t = int(branch_total.group(1))
        c = int(branch_correct.group(1))
        acc = (c/t*100) if t > 0 else 0
        perf_info = f" (Branch Acc: {acc:.1f}%)"

    if match:
        result = int(match.group(1))
        if result == expected:
            print(f"  ✅ PASS (Got {result}){perf_info}")
            return True
        else:
            print(f"  ❌ FAIL (Expected {expected}, Got {result})")
            return False
    else:
        print("  ❌ FAIL (No Result found)")
        print("--- Output Excerpt (Last 20 lines) ---")
        print('\n'.join(out.splitlines()[-20:]))
        print("--------------------------------------")
        return False

def main():
    parser = argparse.ArgumentParser(description="Run RISC-V Tests")
    parser.add_argument("tests", nargs="*", help="Specific test names to run")
    parser.add_argument("--all", action="store_true", help="Run all tests in testcases/")
    parser.add_argument("--rebuild", action="store_true", help="Force rebuild simulator")
    args = parser.parse_args()

    # Build simulator once
    print("Building Simulator...")
    success, out = run_cmd(["iverilog", "-I", "../src", "-o", "testbench.vvp", "testbench.v", "../src/*.v"], cwd=SIM_DIR)
    if not success:
        print("Simulator build failed")
        sys.exit(1)
        
    tests_to_run = []
    
    if args.tests:
        for t in args.tests:
            if t.endswith(".c"): t = t[:-2]
            tests_to_run.append({"name": t, "expected": EXPECTED_MAP.get(t, 0)})
    elif args.all:
        files = sorted(os.listdir(TESTCASES_DIR))
        for f in files:
            if f.endswith(".c"):
                name = f[:-2]
                if name in SKIP_LIST: continue
                tests_to_run.append({"name": name, "expected": EXPECTED_MAP.get(name, 0)})
    else:
        tests_to_run = DEFAULT_TESTS

    failed = []
    for test in tests_to_run:
        if not run_single_test(test):
            failed.append(test["name"])
    
    print("\n" + "="*30)
    if not failed:
        print("ALL TESTS PASSED")
        sys.exit(0)
    else:
        print(f"FAILED TESTS: {', '.join(failed)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
