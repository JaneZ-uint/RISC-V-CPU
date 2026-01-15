import subprocess
import os
import re
import sys

# Define tests
tests = [
    {"name": "sum", "expected": 5050},
    {"name": "vector_add", "expected": 100},
    {"name": "vector_mul", "expected": 100}, # Based on current n=2 in C file
    {"name": "m_extension_test", "expected": 4660},
]

def run_command(cmd):
    # print(f"Executing: {cmd}")
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)

print("Starting Tomasulo CPU Verification...")

cwd = os.getcwd() # Should be project root
test_dir = os.path.join(cwd, "test")
sim_dir = os.path.join(cwd, "tomasulo", "sim")
naive_sim_dir = os.path.join(cwd, "naive", "sim")

# Ensure simulator is built
print("Building Simulator...")
cmd_build_sim = f"cd {sim_dir} && iverilog -I ../src -o testbench.vvp testbench.v ../src/*.v"
res = run_command(cmd_build_sim)
if res.returncode != 0:
    print(f"Error building simulator:\n{res.stderr}")
    sys.exit(1)

failed_tests = []

for test in tests:
    print(f"Running test: {test['name']}")
    
    # 1. Compile Test Case
    # Clean first
    run_command(f"cd {test_dir} && make clean")
    
    extra_args = ""
    if test['name'] == "m_extension_test":
        extra_args = 'CFLAGS="-march=rv32im -mabi=ilp32 -O2 -nostdlib"'
    
    cmd_make = f"cd {test_dir} && make PROG={test['name']} {extra_args}"
    res = run_command(cmd_make)
    if res.returncode != 0:
        print(f"Error compiling {test['name']}:\n{res.stderr}")
        failed_tests.append(test['name'])
        continue
        
    # 2. Copy ROM
    # The makefile in test/ generates ../naive/sim/inst_rom.data
    src_rom = os.path.join(naive_sim_dir, "inst_rom.data")
    dst_rom = os.path.join(sim_dir, "inst_rom.data")
    
    if os.path.exists(src_rom):
        run_command(f"cp {src_rom} {dst_rom}")
    else:
        print(f"Error: {src_rom} not found.")
        failed_tests.append(test['name'])
        continue
        
    # 3. Run Simulation
    cmd_sim = f"cd {sim_dir} && vvp testbench.vvp"
    res_sim = run_command(cmd_sim)
    
    # 4. Parse Output
    # Look for "Result in x1: <val>"
    match = re.search(r"Result in x1:\s+(\d+)", res_sim.stdout)
    if match:
        result = int(match.group(1))
        if result == test['expected']:
            print(f"PASS: {test['name']} (Result: {result})")
        else:
            print(f"FAIL: {test['name']} (Expected: {test['expected']}, Got: {result})")
            failed_tests.append(test['name'])
            # print(res_sim.stdout[-1000:])
    else:
        print(f"FAIL: {test['name']} - Could not find result in output")
        print("Output snippet (last 20 lines):")
        print("\n".join(res_sim.stdout.splitlines()[-20:]))
        failed_tests.append(test['name'])

print("\nVerification Summary:")
if not failed_tests:
    print("All tests PASSED.")
else:
    print(f"Failed tests: {failed_tests}")
    sys.exit(1)
