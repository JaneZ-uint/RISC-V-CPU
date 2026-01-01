# RV32I 指令参考（模拟器 / Verilog CPU 实现导向）

> 本文档面向 **CPU 实现 Agent / 模拟器实现 Agent**，目标不是“指令集概览”，而是：
>
> * 明确 **RV32I 每条指令的精确定义**
> * 明确 **编码格式、字段、立即数构造方式**
> * 明确 **语义（伪代码级别）**
> * 明确 **实现时的易错点 / 硬件语义**
>
> 默认上下文：
>
> * 32-bit RISC-V
> * Little-endian
> * 不包含 M / A / F / C 扩展
> * 单核、顺序执行（非乱序）

---

## 0. 全局约定（非常重要）

### 0.1 寄存器

* 通用寄存器：`x0 ~ x31`
* 每个寄存器宽度：32 bit
* **x0 恒为 0**：

  * 任何写入 `x0` 的行为必须被忽略

### 0.2 PC（程序计数器）

* PC 为 **字节地址**
* RV32I 指令长度固定为 4 字节
* 正常情况下：

```text
PC_next = PC + 4
```

* 跳转 / 分支会覆盖该行为

### 0.3 内存访问

* 内存按 **字节寻址**
* Little-endian：低字节在低地址

### 0.4 有符号 / 无符号

* 所有寄存器内部仅是 bit pattern
* 是否有符号，**由指令语义决定**

---

## 1. 指令编码总览

| 类型 | 格式               | 用途                  |
| -- | ---------------- | ------------------- |
| R  | `rd, rs1, rs2`   | 算术 / 逻辑             |
| I  | `rd, rs1, imm`   | 立即数算术 / load / jalr |
| S  | `rs1, rs2, imm`  | store               |
| B  | `rs1, rs2, imm`  | 条件分支                |
| U  | `rd, imm[31:12]` | lui / auipc         |
| J  | `rd, imm`        | jal                 |

---

## 2. 立即数编码规则（实现重点）

### 2.1 I-type Immediate

```text
imm[11:0] = inst[31:20]
```

* **有符号扩展**到 32 bit

### 2.2 S-type Immediate

```text
imm[11:5] = inst[31:25]
imm[4:0]  = inst[11:7]
```

* 拼接后 **有符号扩展**

### 2.3 B-type Immediate（极易出错）

```text
imm[12]   = inst[31]
imm[10:5] = inst[30:25]
imm[4:1]  = inst[11:8]
imm[11]   = inst[7]
imm[0]    = 0
```

* 拼接后有符号扩展
* **单位是 2 字节（最低位恒 0）**

### 2.4 U-type Immediate

```text
imm = inst[31:12] << 12
```

* **不需要符号扩展**

### 2.5 J-type Immediate（极易出错）

```text
imm[20]   = inst[31]
imm[10:1] = inst[30:21]
imm[11]   = inst[20]
imm[19:12]= inst[19:12]
imm[0]    = 0
```

* 有符号扩展
* 跳转单位为 2 字节

---

## 3. R-Type 指令

### 3.1 ADD / SUB

| 指令  | funct7  | funct3 | opcode  |
| --- | ------- | ------ | ------- |
| ADD | 0000000 | 000    | 0110011 |
| SUB | 0100000 | 000    | 0110011 |

```text
ADD: rd = rs1 + rs2
SUB: rd = rs1 - rs2
```

* 32 bit **模 2^32 溢出**

---

### 3.2 逻辑运算

| 指令  | funct3 | 语义        |
| --- | ------ | --------- |
| AND | 111    | rs1 & rs2 |
| OR  | 110    | rs1 | rs2 |
| XOR | 100    | rs1 ^ rs2 |

---

### 3.3 移位（R-type）

| 指令  | funct7  | funct3 | 语义                   |
| --- | ------- | ------ | -------------------- |
| SLL | 0000000 | 001    | rs1 << rs2[4:0]      |
| SRL | 0000000 | 101    | rs1 >> rs2[4:0]（逻辑）  |
| SRA | 0100000 | 101    | rs1 >>> rs2[4:0]（算术） |

---

### 3.4 比较

| 指令   | funct3 | 语义                           |
| ---- | ------ | ---------------------------- |
| SLT  | 010    | (signed rs1 < rs2) ? 1 : 0   |
| SLTU | 011    | (unsigned rs1 < rs2) ? 1 : 0 |

---

## 4. I-Type 算术指令

### 4.1 ADDI

```text
rd = rs1 + imm
```

* imm 为有符号

---

### 4.2 逻辑立即数

| 指令   | funct3 | 语义        |
| ---- | ------ | --------- |
| ANDI | 111    | rs1 & imm |
| ORI  | 110    | rs1 | imm |
| XORI | 100    | rs1 ^ imm |

---

### 4.3 移位立即数（注意 funct7）

| 指令   | funct7  | funct3 | 语义            |
| ---- | ------- | ------ | ------------- |
| SLLI | 0000000 | 001    | rs1 << shamt  |
| SRLI | 0000000 | 101    | rs1 >> shamt  |
| SRAI | 0100000 | 101    | rs1 >>> shamt |

* shamt = imm[4:0]

---

### 4.4 比较立即数

| 指令    | funct3 | 语义                  |
| ----- | ------ | ------------------- |
| SLTI  | 010    | signed(rs1) < imm   |
| SLTIU | 011    | unsigned(rs1) < imm |

---

## 5. Load 指令（I-type）

| 指令  | funct3 | 宽度 | 符号   |
| --- | ------ | -- | ---- |
| LB  | 000    | 8  | sign |
| LH  | 001    | 16 | sign |
| LW  | 010    | 32 | sign |
| LBU | 100    | 8  | zero |
| LHU | 101    | 16 | zero |

```text
addr = rs1 + imm
rd = MEM[addr]
```

* 必须处理 **对齐 / 非对齐策略**（建议先假设对齐）

---

## 6. Store 指令（S-type）

| 指令 | funct3 | 宽度 |
| -- | ------ | -- |
| SB | 000    | 8  |
| SH | 001    | 16 |
| SW | 010    | 32 |

```text
addr = rs1 + imm
MEM[addr] = rs2
```

---

## 7. 分支指令（B-type）

| 指令   | funct3 | 条件                   |
| ---- | ------ | -------------------- |
| BEQ  | 000    | rs1 == rs2           |
| BNE  | 001    | rs1 != rs2           |
| BLT  | 100    | signed(rs1) < rs2    |
| BGE  | 101    | signed(rs1) >= rs2   |
| BLTU | 110    | unsigned(rs1) < rs2  |
| BGEU | 111    | unsigned(rs1) >= rs2 |

```text
if (cond) PC = PC + imm
else      PC = PC + 4
```

---

## 8. 跳转指令

### 8.1 JAL (J-type)

```text
rd = PC + 4
PC = PC + imm
```

---

### 8.2 JALR (I-type)

```text
t = PC + 4
PC = (rs1 + imm) & ~1
rd = t
```

* **最低位必须清零**

---

## 9. U-Type 指令

### 9.1 LUI

```text
rd = imm << 12
```

---

### 9.2 AUIPC

```text
rd = PC + (imm << 12)
```

---

## 10. 系统指令（最小支持）

### 10.1 ECALL / EBREAK

| 指令     | imm |
| ------ | --- |
| ECALL  | 0   |
| EBREAK | 1   |

* 模拟器中通常作为 **退出 / trap**

---

## 11. 实现建议（给 Agent）

* **先实现整数子集 + 分支 + load/store**
* PC 更新逻辑必须独立、清晰
* 立即数生成建议写成独立模块
* x0 写回统一 mask

---

## 12. 常见错误清单

* ❌ B/J 型立即数拼错位
* ❌ 忘记 PC 是字节地址
* ❌ SRA / SRAI 用成逻辑右移
* ❌ JALR 忘记清零最低位
* ❌ SLTU / BLTU 错用有符号比较

---

> 本文档是 **Verilog CPU / 指令级模拟器的权威参考**。
> 后续如加入 M / CSR / 中断，本文件将扩展而不是修改语义。
