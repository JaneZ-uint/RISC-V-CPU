`include "defines.v"
`include "params.v"

module reorder_buffer(
    input wire clk,
    input wire rst,
    input wire flush,               // Global flush
    
    // Status
    output wire full,
    output wire empty,
    
    // Allocation (Issue Stage)
    input wire alloc_req,
    input wire [`AluOpBus] alloc_op,
    input wire [`RegAddrBus] alloc_rd, // Generic 5-bit
    input wire [`InstAddrBus] alloc_pc,
    input wire alloc_pred,          // 1=Taken
    input wire [`InstAddrBus] alloc_pred_target,
    output wire [`ROB_ID_WIDTH-1:0] alloc_id_o, // Tail ID
    
    // Query Ports (Issue Stage) - To check status of operands
    input wire [`ROB_ID_WIDTH-1:0] query1_id,
    output wire query1_ready,
    output wire [`RegBus] query1_value,
    
    input wire [`ROB_ID_WIDTH-1:0] query2_id,
    output wire query2_ready,
    output wire [`RegBus] query2_value,
    
    // Write Back (CDB Broadcast)
    input wire cdb_valid,
    input wire [`ROB_ID_WIDTH-1:0] cdb_rob_id,
    input wire [`RegBus] cdb_value,
    input wire [`InstAddrBus] cdb_addr,     // For Store addr or Branch target calculation
    input wire cdb_branch_outcome,          // For branch actual result
    
    // Commit Information (Output to Commit/Retire Logic)
    output wire commit_valid,               // Ready to commit head
    output wire [`ROB_ID_WIDTH-1:0] commit_id_o,
    output wire [`AluOpBus] commit_op_o,
    output wire [`RegAddrBus] commit_rd_o,
    output wire [`RegBus] commit_value_o,
    output wire [`InstAddrBus] commit_pc_o,
    output wire [`InstAddrBus] commit_addr_o,
    output wire commit_pred_o,              // Prediction made
    output wire commit_outcome_o,           // Actual outcome
    output wire [`InstAddrBus] commit_pred_target_o,
    
    // Commit Action
    input wire commit_ack,                   // Retire head

    // Branch Predictor Update (Passed to Fetch Unit)
    output reg bp_update_valid,
    output reg [`InstAddrBus] bp_update_pc,
    output reg bp_update_taken,
    output reg [`InstAddrBus] bp_update_target,

    // Statistics Outputs
    output reg [31:0] cnt_total_branch,
    output reg [31:0] cnt_correct_branch
);

    // ROB Entry Structure
    reg busy [`ROB_SIZE-1:0];
    reg ready [`ROB_SIZE-1:0];
    reg [`AluOpBus] op [`ROB_SIZE-1:0];
    reg [`RegAddrBus] rd [`ROB_SIZE-1:0];
    reg [`RegBus] value [`ROB_SIZE-1:0];
    reg [`InstAddrBus] pc [`ROB_SIZE-1:0];
    reg [`InstAddrBus] addr [`ROB_SIZE-1:0]; 
    reg pred [`ROB_SIZE-1:0];
    reg outcome [`ROB_SIZE-1:0];
    reg [`InstAddrBus] pred_target [`ROB_SIZE-1:0];

    reg [`ROB_ID_WIDTH-1:0] head;
    reg [`ROB_ID_WIDTH-1:0] tail;
    reg [`ROB_ID_WIDTH:0] count;
    
    assign full = (count == `ROB_SIZE);
    assign empty = (count == 0);
    
    assign alloc_id_o = tail;
    
    // Query Logic (Combinational)
    assign query1_ready = ready[query1_id];
    assign query1_value = value[query1_id];
    
    assign query2_ready = ready[query2_id];
    assign query2_value = value[query2_id];
    
    // Commit Output (Head)
    assign commit_valid = (!empty) && ready[head];
    assign commit_id_o = head;
    assign commit_op_o = op[head];
    assign commit_rd_o = rd[head];
    assign commit_value_o = value[head];
    assign commit_pc_o = pc[head];
    assign commit_addr_o = addr[head];
    assign commit_pred_o = pred[head];
    assign commit_outcome_o = outcome[head];
    assign commit_pred_target_o = pred_target[head];
    
    // Branch Update Logic
    always @(*) begin
        bp_update_valid = 0;
        bp_update_pc = 0;
        bp_update_taken = 0;
        bp_update_target = 0;
        
        if (commit_ack && !empty && ready[head]) begin
            // Check if it's a branch instruction
            if (op[head] == `ALU_OP_BEQ || op[head] == `ALU_OP_BNE || 
                op[head] == `ALU_OP_BLT || op[head] == `ALU_OP_BGE || 
                op[head] == `ALU_OP_BLTU || op[head] == `ALU_OP_BGEU) begin
                
                bp_update_valid = 1;
                bp_update_pc = pc[head];
                bp_update_taken = outcome[head];
                bp_update_target = addr[head]; 
            end
        end
    end

    integer i;
    
    always @(posedge clk) begin
        if (rst == `RstEnable) begin  // Removed flush reset for counters to persist through flushes!
                                      // Actually if we flush, we don't want to reset stats for the whole run.
                                      // Stats should accumulate.
            head <= 0;
            tail <= 0;
            count <= 0;
            cnt_total_branch <= 0;
            cnt_correct_branch <= 0;
            for (i=0; i<`ROB_SIZE; i=i+1) begin
                busy[i] <= 0;
                ready[i] <= 0;
                pred[i] <= 0;
                op[i] <= 0;
                // value, addr, pc etc don't need reset
            end
        end else if (flush == 1'b1) begin
            // Standard Flush Logic
            $display("ROB: FLUSH TRIGGERED at Time=%t. Head=%d, Op=%h", $time, head, op[head]);
            head <= 0;
            tail <= 0;
            count <= 0;
            for (i=0; i<`ROB_SIZE; i=i+1) begin
                busy[i] <= 0;
                ready[i] <= 0;
                pred[i] <= 0;
                op[i] <= 0;
            end
            
            // Handle Misprediction Statistics
            // Since we flushed, the instruction at head caused it.
            // Check if it's one of our conditional branches.
            if (op[head] == `ALU_OP_BEQ || op[head] == `ALU_OP_BNE || 
                op[head] == `ALU_OP_BLT || op[head] == `ALU_OP_BGE || 
                op[head] == `ALU_OP_BLTU || op[head] == `ALU_OP_BGEU) begin
                
                $display("ROB: Counting Flush as Misprediction. PC=%h TotalBranch=%d", pc[head], cnt_total_branch + 1);
                cnt_total_branch <= cnt_total_branch + 1;
            end
            // Do NOT reset counters on flush!
        end else begin
            // 1. Allocation (Issue)
            if (alloc_req && !full) begin
                busy[tail] <= 1'b1;
                ready[tail] <= 1'b0;
                op[tail] <= alloc_op;
                rd[tail] <= alloc_rd;
                pc[tail] <= alloc_pc;
                pred[tail] <= alloc_pred;
                pred_target[tail] <= alloc_pred_target;
                
                tail <= tail + 1'b1;
                if (!commit_ack) begin
                    count <= count + 1'b1;
                end
            end
            
            // 2. Commit (Retire)
            if (commit_ack && !empty && ready[head]) begin
                busy[head] <= 1'b0;
                head <= head + 1'b1;
                if (!(alloc_req && !full)) begin
                     count <= count - 1'b1;
                end
                
                // --- STATISTICS UPDATE ---
                if (op[head] == `ALU_OP_BEQ || op[head] == `ALU_OP_BNE || 
                    op[head] == `ALU_OP_BLT || op[head] == `ALU_OP_BGE || 
                    op[head] == `ALU_OP_BLTU || op[head] == `ALU_OP_BGEU) begin
                    
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
            end
            
            // 3. Write Back (CDB)
            if (cdb_valid) begin
                if (busy[cdb_rob_id]) begin
                    ready[cdb_rob_id] <= 1'b1;
                    value[cdb_rob_id] <= cdb_value;
                    addr[cdb_rob_id] <= cdb_addr;
                    outcome[cdb_rob_id] <= cdb_branch_outcome;
                end
            end
        end
    end


    // DEBUG PRINT
    always @(posedge clk) begin
        if (commit_ack && !empty && ready[head]) begin
            if (op[head] >= 5'b10000 && op[head] <= 5'b10101) begin // Branch Ops
                 $display("COMMIT: PC=%h | Op=%h | Pred=%b | Outcome=%b | Flush=%b", pc[head], op[head], pred[head], outcome[head], flush);
            end
        end
    end
endmodule
