`include "defines.v"
`include "params.v"

module cdb_arbiter(
    input wire clk,
    input wire rst,
    
    // ALU Interface
    input wire alu_valid,
    input wire [`ROB_ID_WIDTH-1:0] alu_rob_id,
    input wire [`RegBus] alu_value,
    input wire [`InstAddrBus] alu_addr,
    input wire alu_branch_outcome,
    output reg alu_grant,

    // MDU Interface
    input wire mdu_valid,
    input wire [`ROB_ID_WIDTH-1:0] mdu_rob_id,
    input wire [`RegBus] mdu_value,
    output reg mdu_grant,
    
    
    // LSB Interface (Placeholder)
    input wire lsb_valid,
    input wire [`ROB_ID_WIDTH-1:0] lsb_rob_id,
    input wire [`RegBus] lsb_value,
    output reg lsb_grant,
    
    // CDB Output (Broadcast to RS/ROB)
    output reg cdb_valid,
    output reg [`ROB_ID_WIDTH-1:0] cdb_rob_id,
    output reg [`RegBus] cdb_value,
    output reg [`InstAddrBus] cdb_addr,
    output reg cdb_branch_outcome
);

    // Simple Fixed Priority Arbiter (LSB > MDU > ALU)
    
    always @(*) begin
        alu_grant = 0;
        lsb_grant = 0;
        mdu_grant = 0;

        cdb_valid = 0;
        cdb_rob_id = 0;
        cdb_value = 0;
        cdb_addr = 0;
        cdb_branch_outcome = 0;
        
        if (lsb_valid) begin // Prioritize Load/Store if ready (avoid clogging memory unit)
            lsb_grant = 1;
            cdb_valid = 1;
            cdb_rob_id = lsb_rob_id;
            cdb_value = lsb_value;
            cdb_addr = 0; 
        end else if (mdu_valid) begin
            mdu_grant = 1;
            cdb_valid = 1;
            cdb_rob_id = mdu_rob_id;
            cdb_value = mdu_value;
            cdb_addr = 0;
        end else if (alu_valid) begin
            alu_grant = 1;
            cdb_valid = 1;
            cdb_rob_id = alu_rob_id;
            cdb_value = alu_value;
            cdb_addr = alu_addr;
            cdb_branch_outcome = alu_branch_outcome;
        end
    end
endmodule
