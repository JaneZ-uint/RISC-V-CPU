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
    output wire issue_pred_taken_o,      // Prediction Info to Issue
    output wire [`InstAddrBus] issue_pred_target_o,
    output wire issue_empty,
    output wire issue_full,              
    
    // UPDATE INTERFACE (From Commit Stage)
    input wire bp_update_valid_i,
    input wire [`InstAddrBus] bp_update_pc_i,
    input wire bp_update_taken_i,
    input wire [`InstAddrBus] bp_update_target_i
);

    wire iq_full;
    wire pc_stall;
    
    assign pc_stall = iq_full;
    
    // =========================================================================
    // BRANCH PREDICTION LOGIC (BHT + BTB)
    // =========================================================================
    
    // --- BHT: 2-bit Saturating Counter ---
    reg [1:0] bht [0:255]; 
    integer i;
    
    // --- BTB: Valid + Tag + Target ---
    // Width = 1(Valid) + 22(Tag=PC[31:10]) + 32(Target) = 55 bits
    reg [54:0] btb [0:255];
    
    // Initialization
    initial begin
        for(i=0; i<256; i=i+1) begin
             bht[i] = 2'b01; // Weakly Not Taken
             btb[i] = 55'b0;
        end
    end
    
    // --- PREDICTION (Read Phase) ---
    // Note: We use the PC that is currently being fetched (pc_wire)
    // Because pc_reg updates PC in this cycle, we get the 'current' PC here.
    wire [`InstAddrBus] pc_wire;
    wire [7:0] index = pc_wire[9:2]; // Index mapping
    
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
    // Predict TAKEN only if BHT says Taken AND BTB matches (we know where to go)
    wire final_pred_taken = bht_pred_taken && btb_hit;
    wire [`InstAddrBus] final_pred_target = btb_target;
    
    
    // --- UPDATE (Write Phase) ---
    reg [1:0] old_state;
    reg [1:0] new_state;
    wire [7:0] upd_index = bp_update_pc_i[9:2];

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            for(i=0; i<256; i=i+1) begin
                bht[i] <= 2'b01;
                btb[i] <= 55'b0;
            end
        end else if (bp_update_valid_i) begin
            // 1. Update BHT
            // Blocking assignment for temp calculation
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

    // =========================================================================
    // COMPONENTS
    // =========================================================================

    wire pc_ce;
    
    pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .stall(pc_stall),
        .flush(flush),
        .flush_addr(flush_addr),
        .pred_taken(final_pred_taken), 
        .pred_target(final_pred_target),
        .pc(pc_wire),
        .ce(pc_ce)
    );
    
    assign inst_addr_o = pc_wire;
    assign inst_ce_o = pc_ce;
    
    // IQ Instance
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
        .pred_i(final_pred_taken),       // Store prediction
        .pred_target_i(final_pred_target),
        
        .re(issue_re),
        .inst_o(issue_inst_o),
        .pc_o(issue_pc_o),
        .pred_o(issue_pred_taken_o),
        .pred_target_o(issue_pred_target_o),
        
        .full(iq_full),
        .empty(issue_empty)
    );
    
    assign issue_full = iq_full;

endmodule
