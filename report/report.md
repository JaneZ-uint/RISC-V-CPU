# Tomasulo CPU 设计与性能分析报告

## 1. 架构设计 (Architecture Design)

本项目实现了一个基于 **Tomasulo 算法** 的乱序执行 (Out-of-Order Execution) RISC-V CPU，支持 RV32I 基础指令集及部分 M 扩展指令。该设计旨在通过硬件动态调度挖掘指令级并行 (ILP)。

### 1.1 核心组件 (Core Components)

*   **Frontend (Fetch/Decode/Issue)**
    *   **Fetch**: 包含分支预测器 (BPU)，负责以程序顺序预取指令放入指令队列 (Instruction Queue)。
    *   **Issue**: 从队列中取出指令，进行译码和发射。在此阶段检查结构冒险（ROB/RS 是否有空槽）。
*   **寄存器重命名 (Register Renaming)**
    *   **RAT (Register Alias Table)**: 维护逻辑寄存器 (如 x1) 到物理标签 (ROB ID) 的映射。通过重命名，消除了 Write-After-Write (WAW) 和 Write-After-Read (WAR) 假相关冒险，使得多条指令可以同时对同一架构寄存器进行操作。
    *   **ROB (Reorder Buffer)**: 作为一个循环缓冲区，按顺序分配条目，允许指令乱序执行，但强制按顺序提交 (Commit)。这确保了精确异常处理和架构状态的正确更新。
*   **执行引擎 (Execution Engine)**
    *   **RS (Reservation Stations)**: 保留站充当分布式调度器。每一项保存一条等待执行的指令及其操作数。如果操作数未就绪，保留站会监听 CDB。一旦所有源操作数就绪，且功能单元空闲，指令即被送往执行。
    *   **Function Units**: 包含 ALU（算术逻辑）、Multiplier/Divider（乘除法）、Branch Unit（分支）、Load/Store Unit（访存）。
    *   **CDB (Common Data Bus)**: 结果总线。执行单元完成计算后，将结果和 ROB ID 广播到 CDB。所有监听该 ID 的保留站和 ROB 都会捕获数据。

### 1.2 乱序执行机制
1.  **Issue**: 指令按序发射，分配 ROB 槽位，读取 RAT 映射或 ARF 值。
2.  **Execute**: 指令在 RS 中等待，一旦操作数 Ready 立即执行（乱序）。
3.  **Write Result**: 结果广播到 CDB，释放 RS，更新 ROB 状态。
4.  **Commit**: ROB 头部的指令若已完成，则更新 ARF 并退休（按序）。

---

## 2. 性能分析 (Performance Analysis)

本节重点分析在典型循环结构下，Tomasulo 架构如何实现高 Instructions Per Cycle (IPC)。

### 2.1 循环案例分析
考虑如下循环结构，这是计算密集型任务的常见模式：
```asm
loop:
    addi x1, x1, -1   ; op1: 循环计数递减
    bne  x1, x0, loop ; op2: 分支跳转
```

### 2.2 IPC 分析
*   **Loop IPC**: 接近 **1.0** (理想情况下)
*   **性能瓶颈突破**:
    1.  **消除数据等待 (RAW)**:
        *   在简单流水线中，`bne` 必须等待 `addi` 写回。但在 Tomasulo 中，`addi` 的结果在 EX 阶段一经计算出，立刻通过 CDB 广播给等待在 RS 中的 `bne` 指令。`bne` 可以在下一周期立即执行，无需等待 Writeback 或 Commit 阶段。
    2.  **控制相关性解耦**:
        *   Frontend 具有 **Speculative Execution (推测执行)** 能力。分支预测器预测 `bne` 跳转后，Fetch 单元会立即从 `loop` 处取新指令。这使得即便前一次迭代的 `bne` 尚未解析，后续迭代的指令也可以进入流水线这一级。
    3.  **循环展开效应 (Loop Unrolling in Hardware)**:
        *   由于 RAT 的重命名机制，不同迭代中的 `x1` 会被映射到不同的 ROB ID (例如 `ROB#1`, `ROB#3`, ...)。这使得硬件实际上隐式地展开了循环，只要功能单元足够，多个迭代的 `addi` 可以流水化甚至并行执行。

*   **结论**: 相比于顺序流水线因 stall 导致的高 CPI (>3.0)，本设计通过动态调度将 CPI 降至接近 1.0 (受限于单发射前端带宽)。

---

## 3. 性能优化机制 (Optimization Mechanisms)

### 3.1 混合分支预测 (Hybrid Branch Prediction)
*   **策略**: 结合了 **BHT (Branch History Table)** 和 **BTB (Branch Target Buffer)**。
    *   **BHT**: 使用 2-bit 饱和计数器记录历史跳转方向，对循环这种规律性强的分支预测准确率极高 (在测试集 `bulgarian` 中 > 94%)。
    *   **BTB**: 缓存跳转目标地址。当预测跳转时，直接在 IF 阶段提供目标 PC，实现了 **零周期跳转气泡 (Zero-cycle Bubble)**。

### 3.2 寄存器重命名与乱序唤醒
*   **RAT + ROB**: 彻底解决了 WAW 和 WAR 冒险，使得指令流仅受限于真实数据依赖 (RAW)。
*   **CDB Broadcast**: 实现了“全连接”的数据转发。RS 中的指令在捕获到所需数据的当拍即可请求执行，将等待延迟压缩到物理极限。

### 3.3 硬件 M 扩展 (M-Extension)
*   **硬件乘除法器**: 我们实现了独立的乘法器和除法器单元。
    *   相比软件模拟（通常需要数十/上百指令），硬件单元仅需数个周期。
    *   **Latency Hiding**: 更重要的是，由于乱序执行，耗时的除法操作不会阻塞后续无关指令的发射和执行。后续指令可以绕过正在进行除法的指令先一步执行，极大地掩盖了长延迟操作的开销。
