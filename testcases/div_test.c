#include "io.inc"

int main()
{
    // division test
    // 1. div
    int a = 100;
    int b = 10;
    int c = a / b;
    if (c != 10) {
        return 1;
    }

    a = -100;
    b = 10;
    c = a / b;
    if (c != -10) {
        return 2;
    }

    // 2. divu
    unsigned int ua = 30;
    unsigned int ub = 4;
    unsigned int uc = ua / ub;
    if (uc != 7) {
        return 3;
    }

    // 3. rem
    a = -100;
    b = 5;
    c = a % b;
    if (c != 0) {
        return 4;
    }

    a = -5;
    b = 2;
    c = a % b; // Should be -1
    if (c != -1) {
        return 5;
    }

    // 4. remu
    ua = 20;
    ub = 6;
    uc = ua % ub; // 2
    if (uc != 2) {
        return 6;
    }

    // 5. Corner Cases
    // Div By Zero: x / 0 = -1 set all bits to 1
    a = 1234;
    b = 0;
    c = a / b; 
    if (c != -1) {
        return 7;
    }
    
    // Divu By Zero: x / 0 = MaxUint
    uc = (unsigned)a / 0; 
    if (uc != 0xFFFFFFFF) {
        return 8;
    }

    // REM by zero = dividend
    c = a % 0;
    if (c != a) {
        return 9;
    }

    // Overflow: -2^31 / -1 = -2^31
    a = 0x80000000;
    b = -1;
    c = a / b;
    if (c != 0x80000000) {
        return 10;
    }

    // Overflow REM: -2^31 % -1 = 0
    c = a % b; 
    if (c != 0) {
        return 11;
    }

    return 0;
}
