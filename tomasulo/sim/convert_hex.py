import sys
import os

def convert(input_file, output_file):
    mem = {}
    current_addr = 0
    
    try:
        with open(input_file, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f'Error: Input file {input_file} not found.')
        sys.exit(1)
        
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith('@'):
            # Address in hex bytes
            current_addr = int(line[1:], 16)
        else:
            parts = line.split()
            for part in parts:
                val = int(part, 16)
                mem[current_addr] = val
                current_addr += 1
                
    if not mem:
        # Create empty file
        with open(output_file, 'w') as f:
            pass
        return
        
    max_addr = max(mem.keys())
    max_word_idx = max_addr // 4
    
    with open(output_file, 'w') as f:
        # Ensure we cover up to the last word needed. 
        # Note: If the file is huge and sparse, this creates a huge file with strict ordering
        # which is what readmemh without @ addresses expects. 
        # For gaps, it fills 0.
        
        for k in range(0, max_word_idx + 1):
            base = k * 4
            b0 = mem.get(base, 0)
            b1 = mem.get(base + 1, 0)
            b2 = mem.get(base + 2, 0)
            b3 = mem.get(base + 3, 0)
            
            # Pack as 32-bit Little Endian Word
            word_val = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f'{word_val:08x}\n')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: python3 convert_hex.py <input_byte_hex> <output_word_hex>')
        sys.exit(1)
        
    convert(sys.argv[1], sys.argv[2])
