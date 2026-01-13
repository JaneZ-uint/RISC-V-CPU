# Tomasulo CPU Debug Log

## 2026-01-13: vector_mul 死锁修复

### 问题描述
在运行 `vector_mul` 测试用例时，仿真出现 TIMEOUT（50ms）。
- 通过 Trace 发现，ROB (Reorder Buffer) 卡在 Head = 4 的位置。
- ROB ID 4 是一条 `ADD` 指令 (Opcode `01`)。
- Reservation Station显示该指令已 Issue 到 ALU，但 ROB 此后一直未收到 CDB 广播，导致无法 Commit，也没有新的指令能 Commit，流水线死锁。

### 原因分析
通过分析 `reservation_station.v` 和 `alu_common.v` 的交互逻辑：
1. **背靠背发射 (Back-to-Back Issue)**: `reservation_station` 在发现 `fu_ready` 为高时，会在连续的时钟周期内发射指令。
2. **ALU 握手冲突**: `alu_common` 模块在处理输出时，如果当前周期有新的输入 (`valid_i`) 到达，会立即更新内部状态。
3. **数据覆盖**: 当 RS 连续发射指令时，ALU 上一条指令的计算结果尚未获得 CDB 总线授权 (`alu_grant`) 进行广播，就被下一条新指令的输入覆盖了。导致上一条指令（ROB 4）的结果丢失，CDB 永远收不到该结果。

### 解决方案
修改 `tomasulo/src/reservation_station.v` 中的发射逻辑，强制在发射后插入一个周期的气泡，防止连续通过组合逻辑快速发射。

**修改前:**
```verilog
if (fu_ready && found_ready) begin
    // Issue Logic...
end
```

**修改后:**
```verilog
// 添加 !ex_valid 条件，确保如果上一周期刚发射过(导致ex_valid为高)，本周期不发射
if (fu_ready && !ex_valid && found_ready) begin
    // Issue Logic...
end
```

### 验证结果
1. **回归测试**: 运行 `make PROG=vector_add`，测试通过 (Pass)。
2. **修复验证**: 运行 `make PROG=vector_mul` (n=2, n=5)，仿真成功结束，不再 TIMEOUT。
3. **数据正确性**: 检查 Trace Log，确认第一组乘法运算 `63 * 14` 的结果 `882` (0x372) 正确写入并 Commit。

## 2026-01-13: vector_add 回归测试失败调查

### 问题描述
在运行自动化测试脚本 `final_test_tomasulo.py` 时，`vector_add` 测试失败，预期返回 100，实际返回 8。

### 调试过程
1. **重现故障**: 手动运行 `vector_add` 仿真，并在 log 中发现 `Result in a0 (x10): 692` 且 `Result in x1: 8`。
2. **反汇编分析**: 查看 `vector_add.elf` 的反汇编代码：
    ```assembly
    00000090 D A
    00000220 D B
    000003b0 D expected
    00000540 B C
    ```
    主循环代码逻辑：
    ```assembly
    40:   0007a683                lw      a3,0(a5)  ; Load A[i]
    44:   00052803                lw      a6,0(a0)  ; Load B[i]
    ...
    50:   010686b3                add     a3,a3,a6  ; C[i] = A[i] + B[i]
    54:   00d62023                sw      a3,0(a2)  ; Store C[i]
    58:   00460613                addi    a2,a2,4
    5c:   ff1792e3                bne     a5,a7,40  ; Loop
    ```
3. **结果校验循环**:
    ```assembly
    6c:   00072783                lw      a5,0(a4)  ; Load C[i] (Address 0x540...)
    70:   0006a603                lw      a2,0(a3)  ; Load Expected[i] (Address 0x3b0...)
    7c:   40c787b3                sub     a5,a5,a2
    80:   0017b793                seqz    a5,a5     ; if (C[i] == Expected[i]) a5 = 1 else 0
    84:   00f50533                add     a0,a0,a5  ; count += a5
    ```

### 失败原因假设
返回值为 `692` 或 `8` (x1) 看起来很奇怪，可能是因为：
1. **Load/Store 冒险**: Store 指令写入 C 数组后，Load 指令立即读取，LSB (Load Store Buffer) 可能没有正确处理 Store-to-Load Forwarding 或者内存一致性问题。
2. **分支预测错误**: 循环结束条件判断错误。
3. **数据冒险**: `seqz` 或 `add` 指令之间的数据依赖未正确解决。

Trace 显示: `Result in x1: 8`。
`x1` 寄存器在 `start.S` 中被赋值为 `mv x1, a0`。所以最终结果是 8。这意味着 100 次加法中只有 8 次结果匹配。

这强烈暗示存在 **Store-to-Load Forwarding** 问题或 **内存写入延迟** 问题，导致校验循环读取到的 `C[i]` 是旧值或 0。由于 `vector_add` 是紧接着计算完就进行校验，如果 Store 的数据还在 Write Buffer 中未写入 Memory，而 Load 直接从 Memory 读，就会读到错误数据。

### 后续排查计划
- 检查 `load_store_buffer.v` 对 RAW (Read After Write) 的处理。
- 检查 Load 是否能从尚未 Commit 但已在 LSB 中的 Store 转发数据。

## 2026-01-14: vector_add 修复

### 问题描述
`vector_add` 测试失败，预期 100，实际 8。
通过 Log 分析，`x1` (Ra) 寄存器值为 8。这是 `start.S` 中 `main` 返回后 `mv x1, a0` 之前的地址/状态。
实际上，测试台 (testbench) 因为检测到 Fetch Unit 对 `ecall` 的 **推测执行 (Speculative Fetch)** 而提前终止了仿真。
由于 `call main` 是 JAL 指令，当前 Tomasulo 实现没有对 JAL 进行预测 (In-Order Issue 后才跳转)，导致 Fetch Unit 顺序取指取到了 `start.S` 结尾的 `ecall`。
Testbench 检测到 `ecall` 取指后开启 1000 周期倒计时，而 `vector_add` 运行时间远超 1000 周期，导致仿真被强行杀死。

### 解决方案
1. **Load Store Buffer (LSB) 修复**: 修复了 `load_store_buffer.v` 中的竞争条件 (Race Condition) 和 `count` 计数逻辑，防止满/空状态错误 (虽然这不是导致 vector_add 8 的直接原因，但是潜在 bug)。
2. **Testbench 调整**: 将 `inst_i == ecall` 的超时时间从 1000 周期增加到 200,000 周期，确保 `main` 函数有足够时间执行完毕。

### 验证
运行 `python3 final_test_tomasulo.py`，所有测试 (`sum`, `vector_add`, `vector_mul`) 均通过。

## 2026-01-14: Update vector_mul test case
User pointed out that vector_mul expected result should be 100 (verifying all elements) instead of 2.
Current code limited the loop to n=2.
Action:
1. Modified test/src/vector_mul.c to set n=100.
2. Updated final_test_tomasulo.py to expect 100.
Result:
All tests (sum, vector_add, vector_mul) PASS.
