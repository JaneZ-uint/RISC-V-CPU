#include "io.inc"

int main()
{
    // multiplication test
    // 1. mul
    int a = 10;
    int b = 20;
    int c = a * b;
    if (c != 200) {
        return 1;
    }

    a = -10;
    b = 20;
    c = a * b;
    if (c != -200) {
        return 2;
    }
    
    a = 0;
    b = 1283;
    c = a * b;
    if (c != 0) {
        return 3;
    }

    // 2. mulh
    // 0x7FFFFFFF * 0x7FFFFFFF = 0x3FFFFFFF_00000001
    int high;
    a = 2147483647; 
    b = 2147483647;
    asm volatile ("mulh %0, %1, %2" : "=r"(high) : "r"(a), "r"(b));
    if (high != 1073741823) { 
        return 4; 
    }

    // -1 * -1 = 1 (High part is 0)
    a = -1;
    b = -1;
    asm volatile ("mulh %0, %1, %2" : "=r"(high) : "r"(a), "r"(b));
    if (high != 0) { 
        return 5; 
    }

    // 3. mulhsu
    // -1 (Signed) * 2 (Unsigned) = -2 (0xFFFFFFFE) -> High should be -1 (0xFFFFFFFF)
    a = -1; 
    b = 2;
    asm volatile ("mulhsu %0, %1, %2" : "=r"(high) : "r"(a), "r"(b));
    if (high != -1) { 
        return 6; 
    }

    // 4. mulhu
    // 0xFFFFFFFF * 0xFFFFFFFF = (2^32-1)^2 = 2^64 - 2*2^32 + 1
    // High part should be 0xFFFFFFFE
    unsigned int ua = 0xFFFFFFFF;
    unsigned int ub = 0xFFFFFFFF;
    unsigned int uhigh;
    asm volatile ("mulhu %0, %1, %2" : "=r"(uhigh) : "r"(ua), "r"(ub));
    if (uhigh != 0xFFFFFFFE) { 
        return 7; 
    }

    return 0;
}
