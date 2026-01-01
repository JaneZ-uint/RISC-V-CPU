.section .text
.global _start

_start:
    # Initialize stack pointer if necessary (not needed for this simple test)
    # li sp, 0x1000 

    # Call main function
    call main

    # Move return value (a0) to x1 for testbench verification
    mv x1, a0

    # Wait for pipeline to finish write-back
    nop
    nop
    nop
    nop
    nop

    # Stop simulation
    ecall

    # Infinite loop just in case
loop:
    j loop
