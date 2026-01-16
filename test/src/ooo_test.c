int main(){ volatile int a = 10; volatile int b = 20; volatile int c = 0; volatile int d = 100; c = a * b; d = d + 1; d = d + 2; d = d + 3; return c + d; }
