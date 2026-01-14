import os
import subprocess
import re
import glob
import sys

def run_command(cmd, cwd=None, timeout=None):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="TIMEOUT")
    except Exception as e:
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr=str(e))

def convert_data_to_hex(input_file, output_file):
    mem = {}
    current_addr = 0
    try:
        with open(input_file, 'r') as f:
            lines = f.readlines()
            
        for line in lines:
            line = line.strip()
            if not line:
                continue
            if line.startswith('@'):
                current_addr = int(line[1:], 16)
            else:
                parts = line.split()
                for part in parts:
                    try:
                        val = int(part, 16)
                        mem[current_addr] = val
                        current_addr += 1
                    except ValueError:
                        pass
    except Exception as e:
        print(f"Convert Error: {e}")
        pass
                
    if not mem:
        return
    max_addr = max(mem.keys())
    max_word_idx = max_addr // 4
    
    with open(output_file, 'w') as f:
        for k in range(0, max_word_idx + 1):
            base = k * 4
            b0 = mem.get(base, 0)
            b1 = mem.get(base + 1, 0)
            b2 = mem.get(base + 2, 0)
            b3 = mem.get(base + 3, 0)
            word_val = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f"{word_val:08x}\n")

def main():
    print("Starting Benchmark for Tomasulo CPU using .data files...")
    sys.stdout.flush()
    
    root_dir = os.getcwd()
    testcases_dir = os.path.join(root_dir, "testcases")
    sim_dir = os.path.join(root_dir, "tomasulo", "sim")
    tomasulo_sim_rom = os.path.join(sim_dir, "inst_rom.data")

    # Build
    cmd_build = "iverilog -g2012 -I ../src -o testbench.vvp testbench.v ../src/*.v"
    res = run_command(cmd_build, cwd=sim_dir, timeout=60)
    if res.returncode != 0:
        print("Error building simulator:")
        print(res.stderr)
        return

    test_files = glob.glob(os.path.join(testcases_dir, "*.data"))
    test_files = sorted([os.path.basename(f) for f in test_files])
    
    # Filter out long running tests
    skip_list = ['pi.data', 'basicopt1.data' , 'qsort.data' , 'superloop.data']
    test_files = [f for f in test_files if f not in skip_list]
    
    print(f"Found {len(test_files)} test cases")
    print(f"{'Test Case':<20} | {'Total':<10} | {'Correct':<10} | {'Accuracy':<10}")
    print("-" * 60)
    sys.stdout.flush()
    
    results = []

    for test_file in test_files:
        test_name = os.path.splitext(test_file)[0]
        src_path = os.path.join(testcases_dir, test_file)
        
        try:
            convert_data_to_hex(src_path, tomasulo_sim_rom)
            
            # Using None timeout to let it run (for array_test1 speed)
            res_sim = run_command("vvp testbench.vvp", cwd=sim_dir, timeout=None)
            
            output = res_sim.stdout
            total_match = re.search(r"TOTAL_BRANCH:\s+(\d+)", output)
            correct_match = re.search(r"CORRECT_BRANCH:\s+(\d+)", output)
            
            if total_match and correct_match:
                total = int(total_match.group(1))
                correct = int(correct_match.group(1))
                if total > 0:
                    accuracy = (correct / total) * 100
                    acc_str = f"{accuracy:.2f}%"
                else:
                    accuracy = 0
                    acc_str = "N/A"
                print(f"{test_name:<20} | {total:<10} | {correct:<10} | {acc_str:<10}")
                results.append({"name": test_name, "total": total, "correct": correct, "accuracy": accuracy})
            else:
                if res_sim.stderr == "TIMEOUT":
                     print(f"{test_name:<20} | TIMEOUT")
                elif "TIMEOUT" in output:
                     print(f"{test_name:<20} | TIMEOUT (Sim)")
                else:
                     # Check if it finished or crashed
                     print(f"{test_name:<20} | ERROR: Parse Failed. Output len: {len(output)}")
                     # Optional: print last few lines of output
                     lines = output.strip().split('\n')
                     if lines:
                         print(f"Last line: {lines[-1]}")

        except Exception as e:
            print(f"{test_name:<20} | ERROR: {e}")
        
        sys.stdout.flush()

    print("\nBenchmark Finished.")
    if results:
        avg_acc = sum([r['accuracy'] for r in results]) / len(results)
        print(f"Average Accuracy: {avg_acc:.2f}%")

if __name__ == "__main__":
    main()
