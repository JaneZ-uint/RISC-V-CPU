import subprocess
import re
import sys
import os

# Define test cases: (program_name, expected_result_in_x1)
test_cases = [
    {"name": "sum", "expected": 5050},
    {"name": "vector_add", "expected": 100},
    {"name": "vector_mul", "expected": 100},
]

ROM_PATH = "naive/sim/inst_rom.data"

def run_command(command, cwd=None):
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {command}")
        print(f"Stderr: {e.stderr}")
        return None

def run_test(test_name, expected_value):
    print(f"[-] Running test case: {test_name}")
    
    # Clean old ROM data to force rebuild/update
    if os.path.exists(ROM_PATH):
        os.remove(ROM_PATH)
    
    print(f"    Compiling {test_name}...")
    # Using -B to force make to execute because output file is shared across targets
    compile_cmd = f"make -B PROG={test_name}"
        
    if run_command(compile_cmd, cwd="test") is None:
        print(f"    FAILURE: Compilation failed.")
        return False

    # Check if ROM was created
    if not os.path.exists(ROM_PATH):
         print(f"    FAILURE: {ROM_PATH} was not created.")
         return False

    print(f"    Running simulation...")
    sim_cmd = "vvp naive_cpu.vvp"
    output = run_command(sim_cmd)
    
    if output is None:
        print(f"    FAILURE: Simulation failed to run.")
        return False

    match = re.search(r"Result in x1:\s+(\d+)", output)
    if match:
        actual_value = int(match.group(1))
        if actual_value == expected_value:
            print(f"    PASS: Result: {actual_value}")
            return True
        else:
            print(f"    FAIL: Expected {expected_value}, but got {actual_value}")
            return False
    else:
        print(f"    FAIL: Could not find result string 'Result in x1: ...' in output.")
        return False

def main():
    print("Starting Automated Tests for RISC-V CPU...")
    print("============================================")
    
    passed_count = 0
    total_count = len(test_cases)
    
    for test in test_cases:
        if run_test(test["name"], test["expected"]):
            passed_count += 1
        print("--------------------------------------------")

    print(f"Test Summary: {passed_count}/{total_count} passing.")
    
    if passed_count == total_count:
        print("All tests passed!")
        sys.exit(0)
    else:
        print("Some tests failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
