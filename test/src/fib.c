// Fibonacci(10) = 55
int main() {
    int n = 10;
    int a = 0, b = 1, c = 0;
    
    if (n == 0) {
        c = a;
    } else if (n == 1) {
        c = b;
    } else {
        for (int i = 2; i <= n; i++) {
            c = a + b;
            a = b;
            b = c;
        }
    }
    return c;  // 预期: 55
}