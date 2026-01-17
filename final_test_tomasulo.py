import subprocess
import os
import re
import sys
import time

# Define tests
tests = [
    # sum: 0..100 sum = 5050. Might take longer.
    {"name": "sum", "expected": 5050},
    {"name": "vector_add", "expected": 100},
    {"name": "vector_mul", "expected": 100}, 
    {"name": "m_extension_test", "expected": 4660},
]

def run_command(cmd, timeout=None):
    # print(f"Executing: {cmd}")
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 1, stdout="TIMEOUT", stderr="TIMEOUT")

print("Starting Tomasulo CPU Verification...", flush=True)

cwd = os.getcwd() # Should be project root
test_dir = os.path.join(cwd, "test")

failed_tests = []

for test in tests:
    print(f"Running test: {test['name']}...", flush=True)
    
    # 1. Clean and Build Hex
    cmd_build = f"cd {test_dir} && make clean && make ../tomasulo/sim/inst_rom.hex PROG={test['name']}"
    res_build = run_command(cmd_build, timeout=60)
    
    if res_build.returncode != 0:
        print(f"Error building {test['name']}:\n{res_build.stderr}", flush=True)
        failed_tests.append(test['name'])
        continue

    # 2. Run Simulation
    # 'make sim' runs iverilog and vvp. We give it a generous timeout (e.g. 60s)
    cmd_sim = f"cd {test_dir} && make sim"
    res_sim = run_command(cmd_sim, timeout=120)
    
    if res_sim.returncode != 0:
         print(f"Error running simulation for {test['name']}:\n{res_sim.stderr}", flush=True)
         if "TIMEOUT" in res_sim.stdout or "TIMEOUT" in res_sim.stderr:
             print("Simulation TIMEOUT (Python script timeout)", flush=True)
         failed_tests.append(test['name'])
         continue

    # 3. Parse Output
    match = re.search(r"Result in x1 \(Signed\):\s+(-?\d+)", res_sim.stdout)
    if match:
        result = int(match.group(1))
        if result == test['expected']:
            print(f"PASS: {test['name']} (Result: {result})", flush=True)
        else:
            print(f"FAIL: {test['name']} (Expected: {test['expected']}, Got: {result})", flush=True)
            failed_tests.append(test['name'])
    else:
        print(f"FAIL: {test['name']} - Could not find result in output", flush=True)
        # print("Output snippet (last 20 lines):")
        # print("\n".join(res_sim.stdout.splitlines()[-20:]))
        failed_tests.append(test['name'])

print("\nVerification Summary:", flush=True)
if not failed_tests:
    print("All tests PASSED.", flush=True)
else:
    print(f"Failed tests: {failed_tests}", flush=True)
    sys.exit(1)
