# RISC-V M-Extension 高性能实现规范 (Tomasulo)

## 1. 概述 (Overview)

RISC-V M 扩展 (M-Extension) 提供了标准的整数乘法与除法指令。

**注意**：在本项目中，**严禁**在 RTL 实现中直接使用 Verilog 的 `*` (乘法)、`/` (除法) 或 `%` (求余) 运算符来完成核心计算。

**设计目标**：
1.  **高性能乘法器**：不能直接将 32 个数相加，必须引入 Booth 编码和 Wallace Tree技术，得到两个数，最后将这两个数相加得到结果。
2.  **迭代除法器**：必须采用基于移位-减法的迭代算法（如 Radix-2 Non-Restoring Algorithm），通过状态机实现。
3.  **乱序集成**：MDU (Multiplication and Division Unit) 需作为独立的功能单元集成到 Tomasulo 架构中，支持 Tag 传递和 CDB 广播。

## 2. 指令集定义 (Instruction Set)

所有 M指令 Opcode=`0110011`, Funct7=`0000001`。

| 指令 | 格式 | Funct3 | 描述 | 运算定义 | 目标延迟 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **MUL** | R | 000 | 乘法低位 | `(rs1 * rs2)[31:0]` | 3-5 Cycles (Pipelined) |
| **MULH** | R | 001 | 乘法高位 (S) | `(signed(rs1) * signed(rs2))[63:32]` | 3-5 Cycles |
| **MULHSU**| R | 010 | 乘法高位 (S*U) | `(signed(rs1) * unsigned(rs2))[63:32]` | 3-5 Cycles |
| **MULHU** | R | 011 | 乘法高位 (U) | `(unsigned(rs1) * unsigned(rs2))[63:32]` | 3-5 Cycles |
| **DIV** | R | 100 | 除法 (S) | `rs1 / rs2` | 16-32 Cycles (Iterative) |
| **DIVU** | R | 101 | 除法 (U) | `unsigned(rs1) / unsigned(rs2)` | 16-32 Cycles |
| **REM** | R | 110 | 求余 (S) | `rs1 % rs2` | 16-32 Cycles |
| **REMU** | R | 111 | 求余 (U) | `unsigned(rs1) % unsigned(rs2)` | 16-32 Cycles |

## 3. 架构集成 (Integration)

### 3.1 译码与识别
在 `issue_unit.v` 中，除了检查 `opcode`，还需检查 `funct7`。M 指令应被分派到专用的 `RS_MDU` (Reservation Station for MDU)。

### 3.2 模块接口定义
MDU 模块是一个复杂的时序逻辑，不是组合逻辑。

```verilog
module mdu_top (
    input clk, rst, flush,
    
    // 发射接口 (来自 RS)
    input start_i,           // 请求有效
    input [2:0] sub_op_i,    // funct3 (区分 MUL/DIV/REM...)
    input [31:0] rs1_i, 
    input [31:0] rs2_i,
    input [3:0] rob_id_i,    // 携带 Tag 进入流水线
    
    // 握手信号
    output ready_o,          // 1=空闲 (或流水线未满), 0=忙 (除法器正在迭代)
    
    // 写回接口 (去 CDB)
    output done_o,           // 计算完成脉冲
    output [31:0] result_o,  // 32位结果
    output [3:0] rob_id_o    // 用于唤醒保留站的 Tag
);
```

### 3.3 流水线 Tag 传递
由于乘法器是流水线的，输入的 `rob_id_i` 必须在模块内部通过移位寄存器延迟相应的周期数，确保当 `result_o` 输出时，`rob_id_o` 是匹配的。

---

## 4. 高速乘法器设计 (High-Speed Multiplier)

**禁止使用 `assign p = a * b;`**。必须按以下结构实现：

### 4.1 核心算法结构
乘法器至少包含三个阶段：
1.  部分积生成 (Partial Product Generation)
2.  部分积压缩 (Partial Product Reduction)
3.  最终加法 (Final Addition)

### 4.2 符号位预处理 (统一化)
为了复用同一个有符号乘法器核心来处理 `MUL/MULH/MULHSU/MULHU`，通过位扩展将所有操作数转化为 33 位有符号数：

*   **输入**: 32位 `A`, `B`。
*   **扩展**:
    *   `Signed`: 最高位补符号位 -> 33 bits.
    *   `Unsigned`: 最高位补 0 -> 33 bits.
*   **核心计算**: 计算 33-bit * 33-bit 有符号乘法，产生 66-bit 结果。

### 4.3 Stage 1: Booth 编码 (Radix-4)
普通的 32-bit 乘法会产生 32 个部分积。使用 Radix-4 Booth 编码可将部分积减少一半（至 17 个）。

*   **原理**: 扫描乘数的三位（重叠一位），根据 `{-2, -1, 0, 1, 2}` 的权重选择部分积。
*   **操作**: 左移 (`<<1`)、取反加一 (补码) 或 置零。

### 4.4 Stage 2: Wallace Tree压缩
不能使用 17 个加法器串联（延迟太大）。必须使用压缩树。

*   **元件**: 全加器 (Full Adder) 作为 **3:2 压缩器** (Carry Save Adder)。
    *   输入: 3 个 bit (x, y, z)
    *   输出: 2 个 bit (Sum, Carry) -> 权重不同
*   **层级**:
    *   Layer 1: 将 17 个部分积 3个一组，压缩成 ~12 组。
    *   Layer 2: 将 12 组压缩成 ~8 组。
    *   ...
    *   Final: 直到只剩下 **2 个** 64-bit 向量（Sum 向量 和 Carry 向量）。

### 4.5 Stage 3: 最终加法 (Final Adder)
*   将 Wallace Tree 输出的两个向量相加：`Final_Result = Vec_Sum + Vec_Carry`。


---

## 5. 高速除法器设计 (High-Speed Divider)

**禁止使用 `assign q = a / b;`**。必须实现迭代算法。

### 5.1 算法: Radix-2 Non-Restoring Division (非恢复余数法)
*   **特点**: 不需要像恢复余数法那样在减法结果为负时“回退”加法。
*   **逻辑**: 每一个时钟周期处理 1 bit。
*   **状态机**:
    *   `IDLE`: 等待 Start。
    *   `INIT`: 处理除数为0、溢出、符号位记录。取绝对值。
    *   `CALC`: 循环 32 次。每次左移余数，根据符号加或减除数，更新商。
    *   `FIX`: 对余数进行可能的修正。根据记录的符号位将商和余数转回补码。
    *   `DONE`: 输出结果。

### 5.2 结构冒险 (Structural Hazard)
由于除法器需要 32+ 周期且不可流水线化（正在计算时无法接受新任务）：
*   当状态机不在 `IDLE` 时，`ready_o` 信号必须置 **0**。
*   Issue Unit 必须以此信号作为流控，暂停对 MDU 的指令发射。

### 5.3 硬件处理特殊情况
RISC-V 规范要求的特殊情况必须在 `INIT` 或 `FIX` 阶段通过多路选择器处理：
1.  `x / 0 = -1 (All 1s)`
2.  `x % 0 = x`
3.  `(-2^31) / -1 = -2^31` (Overflow)
