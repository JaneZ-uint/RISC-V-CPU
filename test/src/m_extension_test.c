
int m_extension_test() {
    volatile int a = 10;
    volatile int b = 3;
    volatile int res;
    int errors = 0;

    // 1. MUL: 10 * 3 = 30
    res = a * b;
    if (res != 30) errors++;

    // 2. MUL neg: 10 * -3 = -30
    res = a * (-b);
    if (res != -30) errors++;

    // 3. DIV: 10 / 3 = 3
    res = a / b;
    if (res != 3) errors++;

    // 4. DIV neg: -10 / 3 = -3
    res = (-a) / b;
    if (res != -3) errors++;

    // 5. REM: 10 % 3 = 1
    res = a % b;
    if (res != 1) errors++;

     // 6. REM neg: -10 % 3 = -1
    res = (-a) % b;
    if (res != -1) errors++;

    // 7. Larger numbers
    volatile int c = 12345;
    volatile int d = 67;
    // 12345 * 67 = 827115
    res = c * d;
    if (res != 827115) errors++;
    
    // 12345 / 67 = 184
    res = c / d;
    if (res != 184) errors++;

    if (errors == 0) return 0x1234; // Success code
    return errors;
}

int main() {
    return m_extension_test();
}
