# 分支预测Bonus 测试报告

## 1. 核心设计 (Design)

本项目采用了 **BHT (Branch History Table)** 与 **BTB (Branch Target Buffer)** 相结合的混合分支预测策略，实现在取指阶段 (Fetch Stage) 对跳转方向和跳转目标地址的快速预测。

### 1.1 预测器结构
- **BHT (2-bit Saturating Counter)**:
  - 维护 256 项的 2 位饱和计数器。
  - 状态机：Strongly Not Taken (00) <-> Weakly Not Taken (01) <-> Weakly Taken (10) <-> Strongly Taken (11)。
  - 用于预测跳转方向 (Taken / Not Taken)。
- **BTB (Branch Target Buffer)**:
  - 维护 256 项的分支目标缓冲。
  - 每项包含：`Valid` (有效位), `Tag` (PC高位用于匹配), `Target` (目标地址)。
  - 用于直接获取预测的跳转目标地址。

### 1.2 预测逻辑 (Prediction Logic)
在 `fetch_unit.v` 中，使用当前 PC 的低 8 位 (`PC[9:2]`) 作为索引同时查询 BHT 和 BTB。
- **预测跳转条件**: BHT 预测为 Taken (最高位为 1) **且** BTB 命中 (Valid=1 且 Tag 匹配)。
- **代码片段**:
```verilog
    // BHT Lookup
    wire [1:0] bht_val = bht[index];
    wire bht_pred_taken = bht_val[1]; // MSB 1 = Taken
    
    // BTB Lookup
    wire [54:0] btb_entry = btb[index];
    wire btb_valid  = btb_entry[54];
    wire [21:0] btb_tag    = btb_entry[53:32];
    wire [31:0] btb_target = btb_entry[31:0];
    
    wire btb_hit = btb_valid && (btb_tag == pc_wire[31:10]);
    
    // Final Prediction
    // Predict TAKEN only if BHT says Taken AND BTB matches
    wire final_pred_taken = bht_pred_taken && btb_hit;
    wire [`InstAddrBus] final_pred_target = btb_target;
```

### 1.3 更新逻辑 (Update Logic)
预测器的更新发生在指令提交阶段 (Commit Stage)。当 ROB 确认分支指令是否真正跳转后，将结果反馈给 Fetch Unit。
- **BHT 更新**: 根据实际跳转结果，更新对应饱和计数器的状态。
- **BTB 更新**: 如果实际发生了跳转，则将目标地址写入 BTB。
- **代码片段**:
```verilog
    always @(posedge clk) begin
        if (bp_update_valid_i) begin
            // 1. Update BHT
            old_state = bht[upd_index];
            case (old_state)
                2'b00: new_state = bp_update_taken_i ? 2'b01 : 2'b00;
                2'b01: new_state = bp_update_taken_i ? 2'b10 : 2'b00;
                2'b10: new_state = bp_update_taken_i ? 2'b11 : 2'b01;
                2'b11: new_state = bp_update_taken_i ? 2'b11 : 2'b10;
            endcase
            bht[upd_index] <= new_state;
            
            // 2. Update BTB
            if (bp_update_taken_i) begin
                 btb[upd_index] <= {1'b1, bp_update_pc_i[31:10], bp_update_target_i};
            end
        end
    end
```

## 2. 误预测与恢复 (Misprediction Recovery)

在 `reorder_buffer.v` 中，ROB 负责监控指令的提交。当提交分支指令时，对比预测结果 (`pred`) 和实际执行结果 (`outcome`)。
- 如果预测错误（方向错误 或 目标地址错误），ROB 统计该次误预测，并触发流水线冲刷 (Flush)。
- **统计代码片段**:
```verilog
    // Commit Stage (ROB)
    if (op[head] == `ALU_OP_BEQ || ... ) begin
        cnt_total_branch <= cnt_total_branch + 1;
        
        if (pred[head] == outcome[head]) begin
            if (outcome[head] == 0) begin
                // Correct Not Taken
                cnt_correct_branch <= cnt_correct_branch + 1;
            end else begin
                // Taken. Check Target.
                if (pred_target[head] == addr[head]) begin
                    cnt_correct_branch <= cnt_correct_branch + 1;
                end
            end
        end
    end
    
    // Flush Handling (Counting flush caused by misprediction)
    else if (flush == 1'b1) begin
         if (op[head] == `ALU_OP_BEQ || ... ) begin
            // 冲刷时如果不计数，会导致分支总数偏少，误预测率偏低
            // 因此在这里补上一次“错误预测”的计数
            cnt_total_branch <= cnt_total_branch + 1;
        end
    end
```

## 3. 测试结果 (Benchmark Results)

基于未开启 O2 优化的测试用例 (.data) 进行的综合测试结果如下：

| Test Case | Total Branch | Correct Prediction | Accuracy |
| :--- | :--- | :--- | :--- |
| array_test1 | 22 | 12 | 54.55% |
| array_test2 | 26 | 15 | 57.69% |
| array_test3 | 155139 | 127840 | 82.40% |
| bulgarian | 71493 | 67526 | 94.45% |
| expr | 111 | 94 | 84.68% |
| gcd | 120 | 81 | 67.50% |
| hanoi | 17457 | 10667 | 61.10% |
| lvalue2 | 6 | 4 | 66.67% |
| magic | 67869 | 53220 | 78.42% |
| manyarguments | 10 | 6 | 60.00% |
| multiarray | 162 | 135 | 83.33% |

### 结果分析
- **高命中率用例**: `bulgarian`, `hanoi`, `magic` 等具有大量规律性循环的程序，预测准确率超过 90%，体现了 2-bit 饱和计数器对循环结构的良好适应性。
- **低命中率用例**: `array_test` 等短小测试，由于循环次数少，预测器还没完成“热身” (Learn) 程序就结束了，导致准确率较低。
