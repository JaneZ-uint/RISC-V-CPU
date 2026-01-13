`include "defines.v"
`include "params.v"

module reservation_station #(
    parameter SIZE = 8
)(
    input wire clk,
    input wire rst,
    input wire flush, // Branch misprediction flush
    
    // Dispatch Interface (from Issue Unit)
    input wire dispatch_we,
    input wire [`AluOpBus] dispatch_op,
    input wire [`RegBus] dispatch_vj,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_qj,
    input wire dispatch_qj_valid, // 1 = waiting for Qj (value not ready)
    input wire [`RegBus] dispatch_vk,
    input wire [`ROB_ID_WIDTH-1:0] dispatch_qk,
    input wire dispatch_qk_valid, // 1 = waiting for Qk
    input wire [`ROB_ID_WIDTH-1:0] dispatch_dest, // Destination ROB ID
    input wire [`RegBus] dispatch_imm,
    input wire [`InstAddrBus] dispatch_pc,
    input wire [`InstAddrBus] dispatch_pred_target,
    
    output wire full,
    
    // Execution Interface (to Functional Unit)
    input wire fu_ready,          // Functional Unit is ready to accept new instruction
    output reg ex_valid,          // Valid instruction issued to FU
    output reg [`AluOpBus] ex_op,
    output reg [`RegBus] ex_vj,
    output reg [`RegBus] ex_vk,
    output reg [`RegBus] ex_imm,
    output reg [`InstAddrBus] ex_pc,
    output reg [`ROB_ID_WIDTH-1:0] ex_dest,
    output reg [`InstAddrBus] ex_pred_target,
    
    // CDB Snoop Interface
    input wire cdb_valid,
    input wire [`ROB_ID_WIDTH-1:0] cdb_rob_id,
    input wire [`RegBus] cdb_value
);

    // RS Entries
    reg busy [0:SIZE-1];
    reg [`AluOpBus] op [0:SIZE-1];
    reg [`RegBus] vj [0:SIZE-1];
    reg [`RegBus] vk [0:SIZE-1];
    reg [`ROB_ID_WIDTH-1:0] qj [0:SIZE-1];
    reg qj_valid [0:SIZE-1]; 
    reg [`ROB_ID_WIDTH-1:0] qk [0:SIZE-1];
    reg qk_valid [0:SIZE-1]; 
    reg [`ROB_ID_WIDTH-1:0] dest [0:SIZE-1];
    reg [`RegBus] imm [0:SIZE-1];
    reg [`InstAddrBus] pc [0:SIZE-1];
    reg [`InstAddrBus] pred_target [0:SIZE-1];
    
    // Helper functionality: Count busy entries
    reg [31:0] busy_count;
    assign full = (busy_count == SIZE);

    integer i;

    // 1. Find Free Entry ( Combinational )
    reg [31:0] free_idx;
    reg found_free;
    always @(*) begin
        found_free = 0;
        free_idx = 0;
        for (i = 0; i < SIZE; i = i + 1) begin
            if (!busy[i] && !found_free) begin
                free_idx = i;
                found_free = 1;
            end
        end
    end

    // 2. Find Ready Entry ( Combinational )
    reg [31:0] ready_idx;
    reg found_ready;
    always @(*) begin
        found_ready = 0;
        ready_idx = 0;
        for (i = 0; i < SIZE; i = i + 1) begin
            if (busy[i] && !qj_valid[i] && !qk_valid[i] && !found_ready) begin
                ready_idx = i;
                found_ready = 1;
            end
        end
    end

    // Sequential Logic
    always @(posedge clk) begin
        if (rst == `RstEnable || flush == 1'b1) begin
            busy_count <= 0;
            ex_valid <= 0;
            ex_op <= 0;
            for (i = 0; i < SIZE; i = i + 1) begin
                busy[i] <= 0;
                qj_valid[i] <= 0;
                qk_valid[i] <= 0;
            end
        end else begin
            
            // --- Issue / Execution Logic ---
            if (fu_ready && !ex_valid && found_ready) begin
                // Issue to FU
                ex_valid <= 1'b1;
                ex_op <= op[ready_idx];
                ex_vj <= vj[ready_idx];
                ex_vk <= vk[ready_idx];
                ex_imm <= imm[ready_idx];
                ex_pc <= pc[ready_idx];
                ex_dest <= dest[ready_idx];
                ex_pred_target <= pred_target[ready_idx];
                
                // Clear the entry
                busy[ready_idx] <= 1'b0;
                $display("RS: Issued op=%h rob_id=%d to FU", op[ready_idx], dest[ready_idx]);
            end else begin
                ex_valid <= 1'b0;
            end

            // --- Dispatch Logic ---
            if (dispatch_we && found_free && !full) begin
                busy[free_idx] <= 1'b1;
                op[free_idx] <= dispatch_op;
                
                // Qj
                if (dispatch_qj_valid) begin
                   if (cdb_valid && cdb_rob_id == dispatch_qj) begin
                        vj[free_idx] <= cdb_value;
                        qj_valid[free_idx] <= 1'b0;
                   end else begin
                        qj[free_idx] <= dispatch_qj;
                        qj_valid[free_idx] <= 1'b1;
                   end
                end else begin
                    vj[free_idx] <= dispatch_vj;
                    qj_valid[free_idx] <= 1'b0;
                end
                
                // Qk
                if (dispatch_qk_valid) begin
                   if (cdb_valid && cdb_rob_id == dispatch_qk) begin
                        vk[free_idx] <= cdb_value;
                        qk_valid[free_idx] <= 1'b0;
                   end else begin
                        qk[free_idx] <= dispatch_qk;
                        qk_valid[free_idx] <= 1'b1;
                   end
                end else begin
                    vk[free_idx] <= dispatch_vk;
                    qk_valid[free_idx] <= 1'b0;
                end
                
                dest[free_idx] <= dispatch_dest;
                imm[free_idx] <= dispatch_imm;
                pc[free_idx] <= dispatch_pc;
                pred_target[free_idx] <= dispatch_pred_target;
            end
            
            // --- CDB Snoop Logic (For EXISTING entries) ---
            if (cdb_valid) begin
                for (i = 0; i < SIZE; i = i + 1) begin
                    if (busy[i]) begin
                        if (!(dispatch_we && found_free && (i == free_idx))) begin
                             if (qj_valid[i] && qj[i] == cdb_rob_id) begin
                                 vj[i] <= cdb_value;
                                 qj_valid[i] <= 1'b0;
                             end
                             if (qk_valid[i] && qk[i] == cdb_rob_id) begin
                                 vk[i] <= cdb_value;
                                 qk_valid[i] <= 1'b0;
                             end
                        end
                    end
                end
            end
            
            // --- Update Busy Count ---
            if (dispatch_we && found_free && !full) begin
                if (!(fu_ready && !ex_valid && found_ready)) begin
                    busy_count <= busy_count + 1;
                end
            end else if (fu_ready && !ex_valid && found_ready) begin
                busy_count <= busy_count - 1;
            end
            
        end
    end

endmodule
