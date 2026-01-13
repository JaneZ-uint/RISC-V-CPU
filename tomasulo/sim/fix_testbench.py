import os
file_path = 'tomasulo/sim/testbench.v'
if not os.path.exists(file_path):
    file_path = '/home/zhuyihan/code/RISC-V-CPU/tomasulo/sim/testbench.v'

with open(file_path, 'r') as f:
    content = f.read()

if 'repeat(1000)' in content:
    content = content.replace('repeat(1000)', 'repeat(200000)')
    with open(file_path, 'w') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("String not found")
