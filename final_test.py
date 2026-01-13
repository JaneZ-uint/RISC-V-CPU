import subprocess
import os
import re
import time

tests = [
    {"name": "sum", "expected": 5050},
    {"name": "vector_add", "expected": 100},
    {"name": "vector_mul", "expected": 2},
]

def run_command(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)

print("Starting CPU Verification...")

cwd = os.getcwd()
test_dir = os.path.join(cwd, "test")

for test in tests:
    print(f"Running test: {test['name']}")
    
    # Clean prev build to ensure rebuild
    run_command(f"cd {test_dir} && make clean")
    
    # 1. Compile
    cmd_make = f"cd {test_dir} && make PROG={test['name']}"
    res = run_command(cmd_make)
    if res.returncode != 0:
        print(f"Error compiling {test['name']}:\n{res.stderr}")
        continue
        
    # 2. Copy ROM
    src_rom = os.path.join(cwd, "naive", "sim", "inst_rom.data")
    dst_rom = os.path.join(cwd, "inst_rom.data")
    
    if os.path.exists(src_rom):
        run_command(f"cp {src_rom} {dst_rom}")
    else:
        print(f"Error: {src_rom} not found.")
        continue
        
    # 3. Run Simulation
    cmd_sim = "vvp naive_cpu.vvp"
    res_sim = run_command(cmd_sim)
    
    # 4. Parse Output
    match = re.search(r"Result in x1:\s+(\d+)", res_sim.stdout)
    if match:
        result = int(match.group(1))
        if result == test['expected']:
            print(f"PASS: {test['name']} (Result: {result})")
        else:
            print(f"FAIL: {test['name']} (Expected: {test['expected']}, Got: {result})")
    else:
        print(f"FAIL: {test['name']} - Could not find result in output")
        print("Output snippet:")
        print(res_sim.stdout[-500:])

print("Done.")
