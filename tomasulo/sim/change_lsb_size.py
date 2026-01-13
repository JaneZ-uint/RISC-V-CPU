import os
file_path = 'tomasulo/src/tomasulo_cpu.v'
if not os.path.exists(file_path):
    file_path = '/home/zhuyihan/code/RISC-V-CPU/tomasulo/src/tomasulo_cpu.v'

with open(file_path, 'r') as f:
    content = f.read()

if 'load_store_buffer #(.SIZE(8)) u_lsb' in content:
    content = content.replace('load_store_buffer #(.SIZE(8)) u_lsb', 'load_store_buffer #(.SIZE(16)) u_lsb')
    with open(file_path, 'w') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("String not found")
