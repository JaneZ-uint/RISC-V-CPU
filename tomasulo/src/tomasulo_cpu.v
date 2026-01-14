`include "defines.v"
`include "params.v"

module tomasulo_cpu(
    input wire clk,
    input wire rst,
    
    // Instruction Memory Interface
    input wire [`InstBus] inst_i,
    output wire [`InstAddrBus] inst_addr_o,
    output wire inst_ce_o,
    
    // Data Memory Interface
    input wire [`DataBus] mem_data_i,
    input wire mem_valid_i,         
    input wire mem_ready_i,         
    output wire [`DataBus] mem_addr_o,
    output wire [`DataBus] mem_data_o,
    output wire mem_we_o,
    output wire mem_req_o,          
    output wire [3:0] mem_sel_o     
);

    // --- Global Signals ---
    wire flush;
    wire [`InstAddrBus] flush_addr;
            
    // --- CDB Bus ---
    wire cdb_valid;
    wire [`ROB_ID_WIDTH-1:0] cdb_rob_id;
    wire [`RegBus] cdb_value;
    wire [`InstAddrBus] cdb_addr;
    wire cdb_branch_outcome;
    
    // --- Fetch Unit <-> Issue Unit ---
    wire [`InstBus] issue_inst;
    wire [`InstAddrBus] issue_pc;
    wire issue_re;   
    wire iq_empty;
    wire iq_full;
    wire issue_pred_taken;
    wire [`InstAddrBus] issue_pred_target;
    
    // --- ROB <-> Fetch Unit (For Update) ---
    wire bp_update_valid;
    wire [`InstAddrBus] bp_update_pc;
    wire bp_update_taken;
    wire [`InstAddrBus] bp_update_target;
    
    // --- Issue Unit <-> ROB ---
    wire rob_full;
    wire rob_alloc_req;
    wire [`AluOpBus] rob_alloc_op;
    wire [`RegAddrBus] rob_alloc_rd;
    wire [`InstAddrBus] rob_alloc_pc;
    wire rob_alloc_pred;
    wire [`InstAddrBus] rob_alloc_pred_target;
    wire [`ROB_ID_WIDTH-1:0] rob_alloc_id;
    
    wire [`ROB_ID_WIDTH-1:0] rob_query1_id;
    wire rob_query1_ready;
    wire [`RegBus] rob_query1_value;
    wire [`ROB_ID_WIDTH-1:0] rob_query2_id;
    wire rob_query2_ready;
    wire [`RegBus] rob_query2_value;
    
    // --- Issue Unit <-> RAT ---
    wire rat_we;
    wire [4:0] rat_rd;
    wire [`ROB_ID_WIDTH-1:0] rat_rob_id;
    wire [4:0] rat_rs1;
    wire [4:0] rat_rs2;
    wire rat_rs1_valid;
    wire [`ROB_ID_WIDTH-1:0] rat_rs1_rob_id;
    wire rat_rs2_valid;
    wire [`ROB_ID_WIDTH-1:0] rat_rs2_rob_id;
    
    // --- Issue Unit <-> RegFile ---
    wire rf_re1;
    wire [4:0] rf_raddr1;
    wire [`RegBus] rf_rdata1;
    wire rf_re2;
    wire [4:0] rf_raddr2;
    wire [`RegBus] rf_rdata2;
    
    // --- Issue Unit <-> RS ALU ---
    wire rs_alu_full;
    wire rs_alu_we;
    wire [`AluOpBus] rs_alu_op;
    wire [`RegBus] rs_alu_vj;
    wire [`ROB_ID_WIDTH-1:0] rs_alu_qj;
    wire rs_alu_qj_valid;
    wire [`RegBus] rs_alu_vk;
    wire [`ROB_ID_WIDTH-1:0] rs_alu_qk;
    wire rs_alu_qk_valid;
    wire [`ROB_ID_WIDTH-1:0] rs_alu_dest;
    wire [`RegBus] rs_alu_imm;
    wire [`InstAddrBus] rs_alu_pc;
    wire [`InstAddrBus] rs_alu_pred_target;

    // --- Issue Unit <-> LSB ---
    wire lsb_full;
    wire lsb_dispatch_we;
    wire [`AluOpBus] lsb_op;
    wire [2:0] lsb_sub_op;
    wire [`RegBus] lsb_vj;
    wire [`ROB_ID_WIDTH-1:0] lsb_qj;
    wire lsb_qj_valid;
    wire [`RegBus] lsb_vk;
    wire [`ROB_ID_WIDTH-1:0] lsb_qk;
    wire lsb_qk_valid;
    wire [`ROB_ID_WIDTH-1:0] lsb_dest;
    wire [`RegBus] lsb_imm;
    wire [`InstAddrBus] lsb_pc;
    
    // --- ALU Execution Signals ---
    wire alu_fu_ready;
    wire ex_alu_valid;
    wire [`AluOpBus] ex_alu_op;
    wire [`RegBus] ex_alu_vj;
    wire [`RegBus] ex_alu_vk;
    wire [`RegBus] ex_alu_imm;
    wire [`InstAddrBus] ex_alu_pc;
    wire [`ROB_ID_WIDTH-1:0] ex_alu_dest;
    wire [`InstAddrBus] ex_alu_pred_target; 
    
    wire alu_out_valid;
    wire [`ROB_ID_WIDTH-1:0] alu_out_rob_id;
    wire [`RegBus] alu_out_value;
    wire [`InstAddrBus] alu_out_target;
    wire alu_out_outcome;
    wire alu_grant;
    
    // --- LSB Signals ---
    wire lsb_arb_req;
    wire [`ROB_ID_WIDTH-1:0] lsb_arb_dest;
    wire [`RegBus] lsb_arb_val;
    wire lsb_grant;
    
    // --- ROB Commit ----
    wire commit_valid;
    wire [`ROB_ID_WIDTH-1:0] commit_id;
    wire [`AluOpBus] commit_op;
    wire [`RegAddrBus] commit_rd;
    wire [`RegBus] commit_value;
    wire [`InstAddrBus] commit_pc;
    wire [`InstAddrBus] commit_addr;
    wire commit_pred;
    wire commit_outcome;
    wire [`InstAddrBus] commit_pred_target;
    
    // --- FLUSH LOGIC ---
    assign flush = (commit_valid && 
                    (commit_op == `ALU_OP_BEQ || commit_op == `ALU_OP_BNE || 
                     commit_op == `ALU_OP_BLT || commit_op == `ALU_OP_BGE || 
                     commit_op == `ALU_OP_BLTU || commit_op == `ALU_OP_BGEU) && 
                    (commit_outcome != commit_pred)); 
    
    wire is_jal_retiring = (commit_valid && (commit_op == `ALU_OP_JAL));
    assign flush_addr = commit_addr; 
    wire real_flush = flush || is_jal_retiring; 

    // Note: For naive implementation, we might not flush on JAL if we predicted taken.
    // But since our fetch unit might just increment PC by 4 unless we have this predictor,
    // JAL will always cause a flush in base implementation.
    // WITH PREDICTION: If we predicted JAL taken correctly, we shouldn't flush.
    // But JAL always jumps.
    // If our predictor predicted taken to correct target:
    // fetch_unit would have jumped.
    // If not, we flush.
    // For now, let's keep simple flush logic: if prediction was wrong (taken vs not taken), we flush.
    // But JAL is always taken. So if we didn't predict taken (and correct target), we need to flush.
    // However, our current flush logic only checks (commit_outcome != commit_pred).
    // For JAL, outcome is always Taken. If pred was Not Taken, we flush. Correct.
    
    // Warning: We also need to check if Target was correct!
    // If Taken predicted but wrong target -> Flush.
    // Current simple flush logic might miss target mismatch.
    // Let's refine flush logic:
    
    wire branch_mispred = (commit_valid && 
                    (commit_op == `ALU_OP_BEQ || commit_op == `ALU_OP_BNE || 
                     commit_op == `ALU_OP_BLT || commit_op == `ALU_OP_BGE || 
                     commit_op == `ALU_OP_BLTU || commit_op == `ALU_OP_BGEU) && 
                    (commit_outcome != commit_pred));
                    
    // For JAL/JALR or Taken Branches, if target doesn't match, we must flush too.
    // Ideally we check:
    wire target_mismatch = (commit_valid && commit_outcome && (commit_addr != commit_pred_target));
    
    // Since we are adding logic, let's update real_flush.
    // Note: JAL/JALR are unconditional jumps. Outcome is Taken.
    
    wire control_flow_instruction = (commit_op == `ALU_OP_BEQ || commit_op == `ALU_OP_BNE || 
                     commit_op == `ALU_OP_BLT || commit_op == `ALU_OP_BGE || 
                     commit_op == `ALU_OP_BLTU || commit_op == `ALU_OP_BGEU ||
                     commit_op == `ALU_OP_JAL); // JALR (not supported in naive prediction fully yet maybe? treating as JAL in opcode enum usually separate)

    // Wait, ALU_OP_JAL handles both JAL and JALR in this simple CPU? 
    // In issue_unit: JAL -> ALU_OP_JAL, JALR -> ALU_OP_JAL. Yes.
    
    wire needs_flush = commit_valid && (
        (control_flow_instruction && (commit_outcome != commit_pred)) ||
        (control_flow_instruction && commit_outcome && (commit_addr != commit_pred_target))
    );
    
    // Redefine flush for modules
    assign real_flush = needs_flush;

    wire reg_commit_we = (commit_valid && (commit_rd != 0) && (commit_op != `ALU_OP_STORE) && (commit_op != `ALU_OP_BEQ) && (commit_op != `ALU_OP_BNE) && (commit_op != `ALU_OP_BLT) && (commit_op != `ALU_OP_BGE) && (commit_op != `ALU_OP_BLTU) && (commit_op != `ALU_OP_BGEU));                                                      
    
    // --- MODULES ---
    
    fetch_unit u_fetch_unit(
        .clk(clk), .rst(rst), .flush(real_flush), .flush_addr(flush_addr),
        .inst_addr_o(inst_addr_o), .inst_ce_o(inst_ce_o), .inst_i(inst_i),
        .issue_re(issue_re), 
        .issue_inst_o(issue_inst), .issue_pc_o(issue_pc),
        .issue_pred_taken_o(issue_pred_taken), .issue_pred_target_o(issue_pred_target),
        .issue_empty(iq_empty), .issue_full(iq_full),
        
        .bp_update_valid_i(bp_update_valid),
        .bp_update_pc_i(bp_update_pc),
        .bp_update_taken_i(bp_update_taken),
        .bp_update_target_i(bp_update_target)
    );
    
    issue_unit u_issue_unit(
        .clk(clk), .rst(rst), .flush(real_flush),
        .iq_empty(iq_empty), .iq_inst(issue_inst), .iq_pc(issue_pc), 
        .iq_pred_taken(issue_pred_taken), .iq_pred_target(issue_pred_target),
        .iq_re(issue_re),
        // ROB Alloc
        .rob_full(rob_full), .rob_alloc_req(rob_alloc_req), .rob_alloc_op(rob_alloc_op),
        .rob_alloc_rd(rob_alloc_rd), .rob_alloc_pc(rob_alloc_pc),
        .rob_alloc_pred(rob_alloc_pred), .rob_alloc_pred_target(rob_alloc_pred_target),
        .rob_alloc_id(rob_alloc_id),
        // ROB Query
        .rob_query1_id(rob_query1_id), .rob_query1_ready(rob_query1_ready), .rob_query1_value(rob_query1_value),                                                                                                                
        .rob_query2_id(rob_query2_id), .rob_query2_ready(rob_query2_ready), .rob_query2_value(rob_query2_value),                                                                                                                
        // RAT
        .rat_we(rat_we), .rat_rd(rat_rd), .rat_rob_id(rat_rob_id),
        .rat_rs1(rat_rs1), .rat_rs2(rat_rs2),
        .rat_rs1_valid(rat_rs1_valid), .rat_rs1_rob_id(rat_rs1_rob_id),
        .rat_rs2_valid(rat_rs2_valid), .rat_rs2_rob_id(rat_rs2_rob_id),
        // RegFile
        .rf_re1(rf_re1), .rf_raddr1(rf_raddr1), .rf_rdata1(rf_rdata1),
        .rf_re2(rf_re2), .rf_raddr2(rf_raddr2), .rf_rdata2(rf_rdata2),
        // RS ALU
        .rs_alu_full(rs_alu_full), .rs_alu_we(rs_alu_we), .rs_alu_op(rs_alu_op),
        .rs_alu_vj(rs_alu_vj), .rs_alu_qj(rs_alu_qj), .rs_alu_qj_valid(rs_alu_qj_valid),
        .rs_alu_vk(rs_alu_vk), .rs_alu_qk(rs_alu_qk), .rs_alu_qk_valid(rs_alu_qk_valid),
        .rs_alu_dest(rs_alu_dest), .rs_alu_imm(rs_alu_imm), .rs_alu_pc(rs_alu_pc),
        .rs_alu_pred_target(rs_alu_pred_target),
        // LSB
        .lsb_full(lsb_full), .lsb_we(lsb_dispatch_we), .lsb_op(lsb_op), .lsb_sub_op(lsb_sub_op),
        .lsb_vj(lsb_vj), .lsb_qj(lsb_qj), .lsb_qj_valid(lsb_qj_valid),
        .lsb_vk(lsb_vk), .lsb_qk(lsb_qk), .lsb_qk_valid(lsb_qk_valid),
        .lsb_dest(lsb_dest), .lsb_imm(lsb_imm), .lsb_pc(lsb_pc)
    );
    
    reorder_buffer u_rob(
        .clk(clk), .rst(rst), .flush(real_flush),
        .full(rob_full), .empty(),
        // Alloc
        .alloc_req(rob_alloc_req), .alloc_op(rob_alloc_op), .alloc_rd(rob_alloc_rd),
        .alloc_pc(rob_alloc_pc), .alloc_pred(rob_alloc_pred), .alloc_pred_target(rob_alloc_pred_target),
        .alloc_id_o(rob_alloc_id),
        // Query
        .query1_id(rob_query1_id), .query1_ready(rob_query1_ready), .query1_value(rob_query1_value),
        .query2_id(rob_query2_id), .query2_ready(rob_query2_ready), .query2_value(rob_query2_value),
        // CDB Snoop
        .cdb_valid(cdb_valid), .cdb_rob_id(cdb_rob_id), .cdb_value(cdb_value),
        .cdb_addr(cdb_addr), .cdb_branch_outcome(cdb_branch_outcome),
        // Commit
        .commit_valid(commit_valid), .commit_id_o(commit_id), .commit_op_o(commit_op),
        .commit_rd_o(commit_rd), .commit_value_o(commit_value), .commit_pc_o(commit_pc),
        .commit_addr_o(commit_addr), .commit_pred_o(commit_pred), .commit_outcome_o(commit_outcome),
        .commit_pred_target_o(commit_pred_target),
        .commit_ack(commit_valid),
        
        // Branch Update
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target)
    );
    
    rat u_rat(
        .clk(clk), .rst(rst), .flush(real_flush),
        .we(rat_we), .rw_addr(rat_rd), .write_rob_id(rat_rob_id),
        .rs1_addr(rat_rs1), .rs1_valid(rat_rs1_valid), .rs1_rob_id(rat_rs1_rob_id),
        .rs2_addr(rat_rs2), .rs2_valid(rat_rs2_valid), .rs2_rob_id(rat_rs2_rob_id),
        .commit_we(reg_commit_we), 
        .commit_addr(commit_rd), 
        .commit_rob_id(commit_id)
    );
    
    regfile u_regfile(
        .clk(clk), .rst(rst),
        .we(reg_commit_we), .waddr(commit_rd), .wdata(commit_value),
        .re1(rf_re1), .raddr1(rf_raddr1), .rdata1(rf_rdata1),
        .re2(rf_re2), .raddr2(rf_raddr2), .rdata2(rf_rdata2)
    );
    
    reservation_station #(.SIZE(8)) u_rs_alu (
        .clk(clk), .rst(rst), .flush(real_flush),
        // Dispatch
        .dispatch_we(rs_alu_we), .dispatch_op(rs_alu_op),
        .dispatch_vj(rs_alu_vj), .dispatch_qj(rs_alu_qj), .dispatch_qj_valid(rs_alu_qj_valid),
        .dispatch_vk(rs_alu_vk), .dispatch_qk(rs_alu_qk), .dispatch_qk_valid(rs_alu_qk_valid),
        .dispatch_dest(rs_alu_dest), .dispatch_imm(rs_alu_imm), .dispatch_pc(rs_alu_pc),
        .dispatch_pred_target(rs_alu_pred_target),
        .full(rs_alu_full),
        // Execution Output
        .fu_ready(alu_fu_ready), .ex_valid(ex_alu_valid), .ex_op(ex_alu_op),
        .ex_vj(ex_alu_vj), .ex_vk(ex_alu_vk), .ex_imm(ex_alu_imm), .ex_pc(ex_alu_pc),
        .ex_dest(ex_alu_dest), .ex_pred_target(ex_alu_pred_target),
        // CDB Snoop
        .cdb_valid(cdb_valid), .cdb_rob_id(cdb_rob_id), .cdb_value(cdb_value)
    );
    
    alu_common u_alu(
        .clk(clk), .rst(rst),
        .valid_i(ex_alu_valid), .op_i(ex_alu_op), .vj_i(ex_alu_vj), .vk_i(ex_alu_vk),
        .imm_i(ex_alu_imm), .pc_i(ex_alu_pc), .dest_i(ex_alu_dest), .pred_target_i(ex_alu_pred_target),
        .valid_o(alu_out_valid), .rob_id_o(alu_out_rob_id), .value_o(alu_out_value), 
        .target_addr_o(alu_out_target), .branch_outcome_o(alu_out_outcome),
        .cdb_grant_i(alu_grant)
    );
    assign alu_fu_ready = !alu_out_valid; 
    
    load_store_buffer #(.SIZE(16)) u_lsb (
        .clk(clk), .rst(rst), .flush(real_flush),
        .we(lsb_dispatch_we), .op(lsb_op), .sub_op(lsb_sub_op),
        .vj(lsb_vj), .qj(lsb_qj), .qj_valid(lsb_qj_valid),
        .vk(lsb_vk), .qk(lsb_qk), .qk_valid(lsb_qk_valid),
        .dest(lsb_dest), .imm(lsb_imm), .pc(lsb_pc),
        .full(lsb_full),
        .cdb_valid(cdb_valid), .cdb_rob_id(cdb_rob_id), .cdb_value(cdb_value),
        .cdb_grant(lsb_grant), 
        .lsb_out_valid(lsb_arb_req), .lsb_out_rob_id(lsb_arb_dest), .lsb_out_value(lsb_arb_val),
        .mem_req(mem_req_o), .mem_we(mem_we_o), .mem_addr(mem_addr_o), .mem_wdata(mem_data_o),
        .mem_mask(mem_sel_o), .mem_ready(mem_ready_i), .mem_data(mem_data_i)
    );
    
    cdb_arbiter u_cdb_arbiter(
        .clk(clk), .rst(rst),
        .alu_valid(alu_out_valid), .alu_rob_id(alu_out_rob_id), .alu_value(alu_out_value),
        .alu_addr(alu_out_target), .alu_branch_outcome(alu_out_outcome),
        .alu_grant(alu_grant),
        .lsb_valid(lsb_arb_req), .lsb_rob_id(lsb_arb_dest), .lsb_value(lsb_arb_val),
        .lsb_grant(lsb_grant),
        .cdb_valid(cdb_valid), .cdb_rob_id(cdb_rob_id), .cdb_value(cdb_value),
        .cdb_addr(cdb_addr), .cdb_branch_outcome(cdb_branch_outcome)
    );

endmodule
