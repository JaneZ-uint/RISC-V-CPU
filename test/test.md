# 测试指南

本目录包含用于验证 RISC-V CPU 功能的测试程序和构建脚本。

## 目录结构

- `src/`: 包含 C 语言编写的测试用例源码。
  - `sum.c`: 1-100 累加求和测试。
  - `vector_add.c`: 向量加法测试。
  - `vector_mul.c`: 向量乘法测试。
- `Makefile`: 编译脚本，用于生成仿真所需的指令数据。
- `link.ld`: 链接脚本，定义内存布局。
- `start.S`: 汇编启动代码，负责调用 main 函数并处理返回值。

## 测试步骤

### 1. 选择测试用例

修改 `Makefile` 文件，将 `vector_mul.elf` 目标中的依赖源文件修改为你想要测试的文件。

例如，要测试 `vector_add.c`，请修改 `Makefile` 中的对应行：

```makefile
vector_mul.elf: start.S src/vector_add.c link.ld
$(CC) $(CFLAGS) -T link.ld start.S src/vector_add.c -o vector_mul.elf
```

*(注意：虽然输出文件名仍叫 `vector_mul.elf`，但这只是一个中间文件名，不影响最终生成的 `inst_rom.data`)*

### 2. 编译生成指令数据

在 `test` 目录下运行以下命令：

```bash
make clean
make
```

成功执行后，会在 `../naive/sim/` 目录下生成 `inst_rom.data` 文件。

### 3. 运行仿真

回到项目根目录，使用 Icarus Verilog 运行仿真：

```bash
cd ..
iverilog -o naive_cpu.vvp -I naive/src naive/sim/testbench.v naive/src/*.v
vvp naive_cpu.vvp
```

### 4. 验证结果

仿真输出中会显示 `ECALL encountered` 以及 `x1` 寄存器的值。

- 对于 `sum.c`，预期结果 `x1` 为 `5050`。
- 对于 `vector_add.c` 和 `vector_mul.c`，预期结果 `x1` 为 `100` (表示 100 个元素计算全部正确)。

示例输出：
```
ECALL encountered at time             34235000
Result in x1:        100
```
