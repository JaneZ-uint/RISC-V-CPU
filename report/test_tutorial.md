# Test Tutorial

这是我们整个RISC-V-CPU 大作业的各项测试指导文档。

## Test1：基本正确性测试（1-100 加和，vec_add, vec_mul）
测试点对应的.c文件在`test/src`目录下，评测脚本位于根目录下的`final_test_tomasulo.py`。

如果需要进行测试，请在根目录下运行以下命令：

```bash
python3 final_test_tomasulo.py
```

## Test2：分支预测准确率测试
静态预测（不跳转）的理论准确率是50%，而我们的cpu采用二位饱和分支预测，建立了分支历史表（BHT），因此准确率应该远高于50%。

测试点位于testcases目录下，来源是暑假PPCA RISC-V-Simulator项目的测试样例，脚本位于根目录下的`benchmark_data_testcases.py`。

如果需要进行测试，请在根目录下运行以下命令：

```bash
python3 benchmark_data_testcases.py
```

## Test3：M-Extension 测试
我们实现了RISC-V的M-Extension（乘除法取模指令），测试点位于`test/src/m_extension_test.c`，评测脚本位于根目录下的`final_test_tomasulo.py`。

如果需要进行测试，请在根目录下运行以下命令：

```bash
python3 final_test_tomasulo.py
```

## Test4：OoO 测试
为验证我们的CPU是否正确实现了乱序执行（Out-of-Order Execution），我们设计了一些专门的测试用例，这些测试用例包含了数据相关性、控制相关性等多种情况。

测试点位于`test/src/ooo_test.c`，如需看到OoO的执行结果，你需要运行：

```bash
cd test && make PROG=ooo_test ../tomasulo/sim/inst_rom.hex

cd ../tomasulo/sim && iverilog -g2012 -I ../src -o testbench.vvp testbench.v ../src/*.v && vvp testbench.vvp +HEX_FILE=inst_rom.hex > ../../test/simulation.log
```

然后你可以在`simulation.log`中查看测试结果。我们添加了一些标记来帮助你识别乱序执行的过程。