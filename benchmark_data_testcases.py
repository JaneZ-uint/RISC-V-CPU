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

def main():
    print("Starting Benchmark for Tomasulo CPU using .data files...")
    sys.stdout.flush()
    
    root_dir = os.getcwd()
    testcases_dir = os.path.join(root_dir, "testcases")
    sim_dir = os.path.join(root_dir, "tomasulo", "sim")
    
    # Build
    cmd_build = "iverilog -g2012 -I ../src -o testbench.vvp testbench.v ../src/*.v"
    res = run_command(cmd_build, cwd=sim_dir, timeout=60)
    if res.returncode != 0:
        print("Error building simulator:")
        print(res.stderr)
        return

    test_files = glob.glob(os.path.join(testcases_dir, "*.data"))
    test_files = sorted([os.path.basename(f) for f in test_files])
    
    # Filter out long running tests if needed
    skip_list = [] 
    test_files = [f for f in test_files if f not in skip_list]
    
    print(f"Found {len(test_files)} test cases")
    print(f"{'Test Case':<20} | {'Total':<10} | {'Correct':<10} | {'Accuracy':<10} | {'Output':<10}")
    print("-" * 75)
    sys.stdout.flush()
    
    results = []

    for test_file in test_files:
        test_name = os.path.splitext(test_file)[0]
        src_path = os.path.join(testcases_dir, test_file)
        
        # We pass the absolute path of the .data file directly to the testbench
        # The testbench must support +HEX_FILE argument
        # Use simple forward slashes for paths to avoid escaping issues in shell
        src_path = src_path.replace(os.path.sep, "/")
        
        cmd_sim = f"vvp testbench.vvp +HEX_FILE=\"{src_path}\""
        
        try:
            # 30 seconds timeout per test
            res_sim = run_command(cmd_sim, cwd=sim_dir, timeout=30)
            
            output = res_sim.stdout
            total_match = re.search(r"TOTAL_BRANCH:\s+(\d+)", output)
            correct_match = re.search(r"CORRECT_BRANCH:\s+(\d+)", output)
            
            output_val = "N/A"
            # Look for Result in a0
            res_match = re.search(r"Result in a0 \(Unsigned\):\s+(\d+)", output)
            if res_match:
                output_val = str(int(res_match.group(1)) & 0xFF)

            if total_match and correct_match:
                total = int(total_match.group(1))
                correct = int(correct_match.group(1))
                if total > 0:
                    accuracy = (correct / total) * 100
                    acc_str = f"{accuracy:.2f}%"
                else:
                    accuracy = 100.0
                    acc_str = "100.00%"
                
                print(f"{test_name:<20} | {total:<10} | {correct:<10} | {acc_str:<10} | {output_val:<10}")
                results.append({"name": test_name, "total": total, "correct": correct, "accuracy": accuracy, "output": output_val})
            else:
                if res_sim.stderr == "TIMEOUT":
                     print(f"{test_name:<20} | TIMEOUT")
                elif "TIMEOUT" in output:
                     print(f"{test_name:<20} | TIMEOUT (Sim)")
                else:
                     if output_val != "N/A":
                         print(f"{test_name:<20} | {'?':<10} | {'?':<10} | {'?':<10} | {output_val:<10}")
                     else:
                         print(f"{test_name:<20} | ERROR: Parse Failed")

        except Exception as e:
            print(f"{test_name:<20} | ERROR: {e}")
        
        sys.stdout.flush()

    print("\nBenchmark Finished.")
    if results:
        avg_acc = sum([r['accuracy'] for r in results]) / len(results)
        print(f"Average Accuracy: {avg_acc:.2f}%")

if __name__ == "__main__":
    main()
