# Tomasulo CPU 架构文档

## 1. 概述
本目录包含基于 Tomasulo 算法的简化版乱序执行 (Out-of-Order, OoO) RISC-V CPU 实现。该 CPU 支持投机执行、寄存器重命名和乱序执行，并通过重排序缓冲区 (ROB) 维护精确的状态更新。

## 2. 目录结构 (`src/`)

| 文件名 | 描述 | 关键功能 |
|-----------|-------------|-------------------|
| `tomasulo_cpu.v` | 顶层模块 | 连接所有流水线阶段 (Fetch, Issue, RS, ROB, LSB, ALU, RAT, RegFile)。管理全局信号如 Flush 和 CDB。 |
| `fetch_unit.v` | 取指单元 | 包含 PC 逻辑。从指令存储器读取指令并将其推入指令队列 (IQ)。 |
| `instruction_queue.v` | 指令队列 | FIFO 队列，缓冲 Fetch 和 Issue 阶段之间的指令，解耦前端和后端的延迟。 |
| `issue_unit.v` | 发射/译码单元 | 从 IQ 解码指令。分配 ROB 条目。通过 RAT 进行寄存器重命名。分派指令到 RS (ALU) 或 LSB (Mem)。 |
| `reservation_station.v`| 保留站 | 保存等待操作数的 ALU 指令。监听 CDB 以获取操作数。将准备好的指令发送给 ALU 执行。 |
| `load_store_buffer.v` | 加载/存储缓冲 | 管理内存操作。按顺序执行 Load 和 Store (简化版)。监听 CDB 以解决地址依赖。 |
| `alu_common.v` | 算术逻辑单元 | 执行算术、逻辑和分支指令。计算分支结果和跳转地址。 |
| `reorder_buffer.v` | 重排序缓冲区 (ROB) | 确保按顺序提交 (Commit)。存储投机结果。处理分支预测错误时的恢复。 |
| `rat.v` | 寄存器别名表 | 将架构寄存器 (x0-x31) 映射到最新的投机提供者 (ROB ID)。 |
| `regfile.v` | 寄存器堆 | 存储已提交的架构状态 (ARF)。仅在提交时由 ROB 更新。 |
| `cdb_arbiter.v` | CDB 仲裁器 | 仲裁 ALU 和 LSB 对公共数据总线 (CDB) 的访问。 |
| `defines.v` | 常量定义 | RISC-V 指令操作码、ALU 操作码等。 |
| `params.v` | 参数定义 | 硬件配置参数 (ROB 大小, LSB 大小等)。 |

## 3. 详细组件分析

### 3.1 取指单元 (`fetch_unit.v`)
- **角色**: 流水线的前端。
- **机制**:
  - 维护程序计数器 (`pc_reg.v`)。
  - 从指令内存中获取指令。
  - 将有效指令推入 `instruction_queue`。
  - 如果 `instruction_queue` 已满，则暂停取指。
  - 收到 ROB 的分支预测错误信号时进行 Flush (重置 PC)。

### 3.2 指令队列 (`instruction_queue.v`)
- **角色**: 弹性缓冲 (Elastic Buffer)。
- **机制**:
  - 标准 FIFO 实现。
  - 允许 Fetch 和 Issue 以不同的瞬时速率运行。

### 3.3 发射单元 (`issue_unit.v`)
- **角色**: 顺序发射 (In-order Dispatch) 和 重命名 (Renaming)。
- **关键操作**:
  - **译码 (Decode)**: 确定指令类型 (ALU, Load, Store, Branch, System)。
  - **ROB 分配**: 为新指令在 ROB 尾部预留一个位置。
  - **重命名 (读 RAT)**: 检查 `rat` 以确定操作数 (rs1, rs2) 是在寄存器堆中还是在 ROB 中等待。
    - 如果在 ROB 中 (Valid Map): 查询 ROB 状态/值。如果值未就绪，则使用 Tag (ROB ID)。
    - 如果在 ARF 中 (Invalid Map): 直接从 `regfile` 读取值。
  - **分派 (Dispatch)**: 将解码信息 + 重命名后的操作数 (值或 Tag) 发送到 `reservation_station` (ALU 操作) 或 `load_store_buffer` (内存操作)。
  - **更新 RAT**: 更新目标寄存器 (rd) 的映射，使其指向新的 ROB ID。

### 3.4 保留站 (`reservation_station.v`)
- **角色**: ALU 操作的指令窗口 (Instruction Window)。
- **机制**:
  - **等待 (Wait)**: 存储操作数 (Qj, Qk) 尚未就绪的指令。
  - **监听 (Snoop)**: 监听 CDB。如果 CDB 广播的 ID 匹配等待的 Qj 或 Qk，捕获该值。
  - **选择 (Select)**: 逻辑查找两个操作数都就绪的条目 (`found_ready`)。
  - **执行 (Execute)**: 将就绪指令发送给 `alu_common` 模块并释放 RS 条目。

### 3.5 加载存储缓冲 (`load_store_buffer.v`)
- **角色**: 内存队列。
- **机制**:
  - 作为循环缓冲 (FIFO) 运行。
  - **分派**: 条目按程序顺序进入 `tail`。
  - **执行 (Head)**:
    - **Load**: 等待操作数 (基地址)，计算有效地址，发起内存读取。数据返回后，请求 CDB 广播。
    - **Store**: 等待操作数 (基地址 + 数据)。计算地址。等待提交信号 (在本设计中通过 ROB 退休或简化流程处理)。*注*: Store 通常在提交时才真正写入内存。
  - **顺序性**: 严格执行 Head 指令，确保本简化模型中的内存一致性。

### 3.6 重排序缓冲区 (`reorder_buffer.v`)
- **角色**: 提交 / 退休 (Commit / Retirement)。
- **机制**:
  - **分配**: 由 Issue 单元在 `tail` 添加条目。
  - **写回**: 监听 CDB。当指令完成 (ALU 或 Load) 时，将 ROB 条目标记为 `Ready` 并存储结果 `Value`。
  - **提交 (Head)**:
    - 检查 `head` 是否 `Ready`。
    - 如果 Ready，则退休指令：
      - 将结果写入 `regfile`。
      - 更新 `rat` (如果是最新的映射则清除)。
      - **分支恢复**: 对于分支指令，比较内部预测与实际 `outcome`。如果不匹配，触发流水线 `flush`。

### 3.7 寄存器别名表 (`rat.v`)
- **角色**: 状态跟踪。
- **机制**:
  - 32 个条目的表。
  - `map_valid[reg] = 1`: 寄存器 `reg` 的值正由 `map_rob_id[reg]` 计算。
  - `map_valid[reg] = 0`: 寄存器 `reg` 的值已提交在寄存器堆中。
  - 允许 Issue 单元知道“谁拥有 R1 的最新值？”

### 3.8 CDB 仲裁器 (`cdb_arbiter.v`)
- **角色**: 总线管理。
- **机制**:
  - 接收来自 ALU 和 LSB 的请求。
  - 根据固定优先级 (例如 LSB > ALU) 授予广播权限。
  - 获胜者将 `cdb_rob_id` 和 `cdb_value` 驱动到 RS, ROB 和 LSB。

## 4. ADD 指令的数据流 (`add x1, x2, x3`)
1. **Fetch**: 从内存取指，放入 IQ。
2. **Issue**:
   - 查 RAT 获取 `x2`, `x3` 的状态。获取值 (如果就绪) 或 Tag (ROB ID)。
   - 分配 ROB ID `N`。更新 RAT: `x1` 现在指向 ROB `N`。
   - 将 Op `ADD`, 操作数, 和目标 `N` 分派到 RS。
3. **Execution**:
   - RS 等待 `x2` 和 `x3` 就绪 (监听 CDB)。
   - 指令就绪 -> 发送到 ALU。
   - ALU 计算结果。
4. **Writeback**:
   - ALU 请求 CDB。仲裁器授权。
   - 结果带 Tag `N` 广播到 CDB。
   - 等待 `N` 的 RS 条目捕获该值。
   - ROB 条目 `N` 存储该值并标记为 Ready。
5. **Commit**:
   - 当 `N` 到达 ROB 头部时，ROB 将值写入 RegFile `x1`。
   - ROB 更新 RAT (如果 RAT `x1` 仍指向 `N`，将由 Valid 变回 Invalid/直接指向 ARF)。
