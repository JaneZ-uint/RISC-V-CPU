# Naive 五级流水 CPU 设计说明（RV32I / Verilog）

> 本文档是 **五级流水 RV32I CPU（Naive 实现）** 的总体设计说明。
>
> 目标读者：
>
> * Verilog 实现 Agent
>
> * 微结构 / 流水线设计 Agent
>
> * 测试与验证 Agent
>
> 本 CPU 以 **“正确性优先、结构清晰、易于验证”** 为第一目标，
> **不追求性能最优，也不引入复杂旁路/乱序机制**。

---

## 1. 设计目标（Design Goals）

### 1.1 功能目标

* 实现 **RV32I 基础整数指令集**
* 采用 **经典五级流水线**：IF / ID / EX / MEM / WB
* 支持顺序一致的、单发射执行模型
* 能正确运行：

  * hand-written 汇编
  * gcc -march=rv32i 编译的简单程序（无库）

### 1.2 非目标（刻意不做）

* ❌ 不支持 M / F / A / C 扩展
* ❌ 不支持中断 / 异常 / CSR（仅保留 ECALL 作为退出）
* ❌ 不支持乱序执行
* ❌ 不支持 cache / MMU

### 1.3 设计原则

* **Naive > Clever**：

  * 能 stall 就 stall
  * 能 flush 就 flush
* 控制逻辑显式、可读
* 每一级流水行为在文档中都能单独解释

---

## 2. 支持的指令子集

### 2.1 算术 / 逻辑指令

* R-type：`ADD SUB AND OR XOR SLL SRL SRA SLT SLTU`
* I-type：`ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU`

### 2.2 Load / Store

* Load：`LB LH LW LBU LHU`
* Store：`SB SH SW`

### 2.3 控制流

* Branch：`BEQ BNE BLT BGE BLTU BGEU`
* Jump：`JAL JALR`

### 2.4 其他

* `LUI AUIPC`
* `ECALL`（模拟器退出 / 测试终止）

> 所有指令语义以 `instructions.md` 为准。

---

## 3. 总体微结构概览

### 3.1 五级流水划分

| Stage | 名称                 | 核心职责             |
| ----- | ------------------ | ---------------- |
| IF    | Instruction Fetch  | 取指、PC 更新         |
| ID    | Instruction Decode | 解码、读寄存器、生成立即数    |
| EX    | Execute            | ALU 运算、分支判断、地址计算 |
| MEM   | Memory             | Load / Store     |
| WB    | Write Back         | 写回寄存器            |

### 3.2 流水寄存器

* IF/ID
* ID/EX
* EX/MEM
* MEM/WB

每一级流水寄存器：

* 保存 **必要的数据信号**（operand / imm / PC）
* 保存 **控制信号**（alu_op / mem_read / reg_write 等）

---

## 4. 执行循环（Execution Loop）

### 4.1 单周期视角（逻辑时间）

在每一个时钟周期内：

1. IF：

   * 使用当前 PC 访问指令存储器
2. ID：

   * 解码上一周期取到的指令
3. EX：

   * 执行 ALU 运算或分支判断
4. MEM：

   * 访问数据存储器（如需要）
5. WB：

   * 将结果写回寄存器堆

所有阶段 **并行执行**，通过流水寄存器隔离。

---

### 4.2 PC 更新规则（关键）

PC 默认行为：

```text
PC_next = PC + 4
```

PC 被修改的唯一情况：

* 分支指令在 EX 阶段判定成功
* JAL / JALR 在 EX 阶段产生跳转目标

Naive 策略：

* **EX 阶段确定跳转**
* IF / ID / ID/EX 统一 flush

---

## 5. 冒险处理策略（Naive）

### 5.1 数据冒险（Data Hazard）

* **不实现旁路（forwarding）**
* 所有 RAW hazard 通过 **stall** 解决

典型规则：

* 若 ID 阶段指令读取的寄存器

  * 等待 EX/MEM/WB 阶段尚未写回
  * → pipeline stall

> 虽然性能较差，但逻辑最简单、最安全。

---

### 5.2 控制冒险（Control Hazard）

* 分支 / 跳转在 EX 阶段才解析
* 在此之前取的指令全部无效

处理方式：

* 分支成功：

  * flush IF/ID
  * flush ID/EX

---

## 6. 各流水级详细行为

### 6.1 IF（取指）

* 输入：PC
* 输出：指令、PC
* 行为：

  * inst = IMEM[PC]
  * PC + 4 预计算

---

### 6.2 ID（译码）

* 解码 opcode / funct3 / funct7
* 读取 RegFile：rs1 / rs2
* 生成立即数
* 产生控制信号

---

### 6.3 EX（执行）

* ALU 运算
* 比较（branch）
* 计算 load/store 地址
* 生成跳转目标

---

### 6.4 MEM（访存）

* Load：

  * 从数据存储器读取
  * 执行符号/零扩展

* Store：

  * 写入数据存储器

---

### 6.5 WB（写回）

* 写回源：

  * ALU 结果
  * Load 数据
  * PC + 4（JAL/JALR）

* 写回目标：rd（x0 除外）

---

## 7. 内存模型（Memory Model）

### 7.1 指令存储器（IMEM）

* 只读
* 按字节寻址
* 假设 **指令对齐**

---

### 7.2 数据存储器（DMEM）

* 字节寻址
* Little-endian
* Naive 假设：

  * Load / Store 地址对齐

---

### 7.3 地址空间约定（建议）

| 区域   | 地址范围          |
| ---- | ------------- |
| IMEM | 0x0000_0000 ~ |
| DMEM | 0x8000_0000 ~ |

（具体可由测试框架决定）

---

## 8. 测试设计（Testing Strategy）

### 8.1 单指令测试

* 每条指令单独编写汇编
* 验证：

  * 寄存器结果
  * PC 行为

---

### 8.2 冒险测试

* RAW hazard：

```asm
add x1, x2, x3
add x4, x1, x5
```

* Load-use hazard

---

### 8.3 控制流测试

* taken / not-taken branch
* JAL / JALR

---

### 8.4 程序级测试

* 小型 C 程序：

  * 循环
  * if / else
  * 函数调用（jal/jalr）

---

### 8.5 退出机制

* 使用 `ECALL` 作为程序结束
* 测试平台捕获该信号并停止仿真

---

## 9. 扩展方向（Future Work）

* 数据旁路（forwarding）
* 分支提前判定
* Pipeline 性能优化
* 支持 M 扩展
* 支持 CSR / 中断

---

> 本文档定义的是一个 **教学级 / 研究级但工程风格严谨的五级流水 CPU**。
> 所有实现必须优先保证 **与本设计说明的一致性**。
