# 2位饱和计数器分支预测设计

## 1. 概述
当前的 Tomasulo CPU 使用特定的静态分支预测（总是预测不跳转）。我们计划升级为动态的修改版2位饱和计数器方案，以提高分支预测准确性和处理器性能。

## 2. 理论基础
2位饱和计数器是一个具有四种状态的状态机，用于跟踪分支指令历史行为。

### 状态
- **00**: 强不跳转 (SN) - 预测不跳转
- **01**: 弱不跳转 (WN) - 预测不跳转
- **10**: 弱跳转 (WT)   - 预测跳转
- **11**: 强跳转 (ST)   - 预测跳转

### 状态转移逻辑
计数器根据分支的实际结果（在提交阶段评估）进行更新：
- 如果 **跳转 (Taken)**：计数器加1（在11处饱和）。
- 如果 **不跳转 (Not Taken)**：计数器减1（在00处饱和）。

| 当前状态 | 实际结果 | 下一状态 | 预测结果 |
|:-------:|:-------:|:-------:|:-------:|
| 00 (SN) | 不跳转 | 00 (SN) | 不跳转 |
| 00 (SN) | 跳转   | 01 (WN) | 不跳转 |
| 01 (WN) | 不跳转 | 00 (SN) | 不跳转 |
| 01 (WN) | 跳转   | 10 (WT) | 不跳转 |
| 10 (WT) | 不跳转 | 01 (WN) | 跳转 |
| 10 (WT) | 跳转   | 11 (ST) | 跳转 |
| 11 (ST) | 不跳转 | 10 (WT) | 跳转 |
| 11 (ST) | 跳转   | 11 (ST) | 跳转 |

## 3. 硬件实现

### 3.1 分支历史表 (BHT)
我们将在 `fetch_unit`（或在其内部实例化的专用 `branch_predictor` 模块）中实现一个 **分支历史表 (BHT)**。

- **大小**: 256 个逻辑条目（可配置）。
- **存储**: `reg [1:0] bht [0:255];`
- **索引**: `index = pc[9:2];` (使用 PC 的 9:2 位进行索引，假设指令为4字节对齐)。

### 3.2 接口变更

#### `fetch_unit.v`
需要新的输入端口来接收来自提交阶段 (ROB) 的训练数据。

```verilog
module fetch_unit (
    // ... 现有端口 ...
    
    // 分支预测更新接口 (来自 Commit 阶段)
    input wire bp_update_valid,    // 如果刚刚提交了一条分支指令，则为1
    input wire [`InstAddrBus] bp_update_pc, // 已提交分支的 PC
    input wire bp_update_taken     // 实际结果 (1=跳转, 0=不跳转)
);
```

### 3.3 内部逻辑

#### 预测 (读阶段 - 取指 IF)
在取指阶段，我们使用当前 PC 查找 BHT。

```verilog
wire [7:0] bht_index = pc_wire[9:2];
wire [1:0] current_counter = bht[bht_index];
wire pred_taken = current_counter[1]; // 最高位决定预测结果 (10, 11 => 跳转)
```

这个 `pred_taken` 信号将被发送到：
1.  `pc_reg` (如果我们要依据预测更新 PC，还需要 BTB 支持) 以立即更新下一条 PC。
2.  `instruction_queue` / `issue_unit` (通过流水线传递)，以便 ROB 知道当时的预测是什么。

*注意：如果没有分支目标缓冲 (BTB)，预测“跳转”只有在我们可以计算出目标地址时才有用。在第一阶段，为了简化，我们可能只是用这个预测来标记指令，或者假设存在 BTB。如果没有 BTB，我们可能仍然取 PC+4，但将指令标记为“预测跳转”，供后端检查，或者暂停直到译码阶段计算出目标地址。*

#### 更新 (写阶段 - 提交 Commit)
当 ROB 提交一条分支指令时，它将发送 `bp_update_*` 信号回 `fetch_unit`。

```verilog
always @(posedge clk) begin
    if (rst) begin
        // 将 BHT 重置为弱不跳转 (01) 或 强不跳转 (00)
        for (i=0; i<256; i=i+1) bht[i] <= 2'b01; 
    end else if (bp_update_valid) begin
        wire [7:0] update_index = bp_update_pc[9:2];
        reg [1:0] old_val = bht[update_index];
        reg [1:0] new_val;
        
        case (old_val)
            2'b00: new_val = bp_update_taken ? 2'b01 : 2'b00;
            2'b01: new_val = bp_update_taken ? 2'b10 : 2'b00;
            2'b10: new_val = bp_update_taken ? 2'b11 : 2'b01;
            2'b11: new_val = bp_update_taken ? 2'b11 : 2'b10;
        endcase
        
        bht[update_index] <= new_val;
    end
end
```

## 4. 与 Tomasulo 流水线的集成

1.  **取指 (Fetch)**: 预测方向。如果预测跳转且目标已知 (BTB)，更新 PC。
2.  **发射 (Issue)**: 将 `pred_taken` 传递给 ROB。
3.  **执行 (Execute)**: 计算实际条件和目标地址。在 CDB 上广播。
4.  **ROB**: 存储实际结果和预测结果。
5.  **提交 (Commit)**:
    -   比较 `pred_taken` 与 `actual_taken`。
    -   如果不匹配：触发 **Flush (冲刷)**。
    -   总是：发送 `bp_update` 信号给 `fetch_unit` 以训练 BHT。

## 5. 未来改进 (BTB)
为了充分利用 2位预测器，应该添加 **分支目标缓冲 (BTB)**。它存储预测为跳转的分支的目标地址。
-   键 (Key): PC
-   值 (Value): 目标地址
-   逻辑: 如果 BHT 预测跳转，检查 BTB。如果命中，`next_pc = BTB[pc]`。如果未命中，`next_pc = pc + 4` (稍后如果确实跳转了，则检测为预测错误)。
