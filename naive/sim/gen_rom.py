import struct

def write_inst(f, inst_hex):
    f.write(inst_hex + "\n")

with open("naive/sim/inst_rom.data", "w") as f:
    # 1. addi x1, x0, 0      (sum = 0)
    write_inst(f, "00000093")
    
    # 2. addi x2, x0, 1      (i = 1)
    write_inst(f, "00100113")
    
    # 3. addi x3, x0, 101    (limit = 101)
    write_inst(f, "06500193")
    
    # loop: (PC=12)
    # 4. beq x2, x3, end     (if i == 101 goto end, offset=16)
    write_inst(f, "00310863")
    
    # 5. add x1, x1, x2      (sum += i)
    write_inst(f, "002080b3")
    
    # 6. addi x2, x2, 1      (i++)
    write_inst(f, "00110113")
    
    # 7. jal x0, loop        (goto loop, offset=-12)
    # Correct: FF5FF06F
    write_inst(f, "ff5ff06f")
    
    # end: (PC=28)
    # 8. lui x5, 0x80000     (base addr)
    write_inst(f, "800002b7")
    
    # 9. sw x1, 0(x5)        (store sum)
    write_inst(f, "0012a023")
    
    # 10. ecall              (stop)
    write_inst(f, "00000073")
    
    # Fill rest with NOPs
    for _ in range(100):
        write_inst(f, "00000013")

print("inst_rom.data generated.")
