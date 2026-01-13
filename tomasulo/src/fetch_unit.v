`include "defines.v"
`include "params.v"

module fetch_unit(
    input wire clk,
    input wire rst,
    input wire flush,
    input wire [`InstAddrBus] flush_addr,
    
    // To Instruction Memory
    output wire [`InstAddrBus] inst_addr_o,
    output wire inst_ce_o,
    input wire [`InstBus] inst_i,
    
    // To Issue Stage
    input wire issue_re,                // Read Enable from Issue
    output wire [`InstBus] issue_inst_o,
    output wire [`InstAddrBus] issue_pc_o,
    output wire issue_empty,
    output wire issue_full              // Optional debugging
);

    wire iq_full;
    wire pc_stall;
    
    assign pc_stall = iq_full;
    
    // PC Instance
    wire [`InstAddrBus] pc_wire;
    wire pc_ce;
    
    pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .stall(pc_stall),
        .flush(flush),
        .flush_addr(flush_addr),
        .pred_taken(1'b0), // Static not taken
        .pred_target(`ZeroWord),
        .pc(pc_wire),
        .ce(pc_ce)
    );
    
    assign inst_addr_o = pc_wire;
    // Only enable memory access if chip is enabled.
    // Even if stalled, we might need to read the current instruction (if we haven't latched it yet).
    // If stalled, PC doesn't change, so address is valid.
    assign inst_ce_o = pc_ce;
    
    // IQ Instance
    // Write if CE is enabled and not stalling (which means IQ not full)
    wire iq_we = (pc_ce == `ReadEnable) && (!iq_full) && (flush == `RstDisable);
    
    instruction_queue #(
        .SIZE(8),
        .PTR_WIDTH(3)
    ) u_iq (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .we(iq_we),
        .inst_i(inst_i),
        .pc_i(pc_wire),
        .re(issue_re),
        .inst_o(issue_inst_o),
        .pc_o(issue_pc_o),
        .full(iq_full),
        .empty(issue_empty)
    );
    
    assign issue_full = iq_full;

endmodule
