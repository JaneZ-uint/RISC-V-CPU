`include "defines.v"
`include "params.v"

module issue_unit(
    input wire clk,
    input wire rst,
    input wire flush,               
    
    // IQ
    input wire iq_empty,
    input wire [`InstBus] iq_inst,
    input wire [`InstAddrBus] iq_pc,
    input wire iq_pred_taken,           
    input wire [`InstAddrBus] iq_pred_target, 
    output reg iq_re,             

    // ROB Alloc
    input wire rob_full,
    output reg rob_alloc_req,
    output reg [`AluOpBus] rob_alloc_op, 
    output reg [`RegAddrBus] rob_alloc_rd,
    output reg [`InstAddrBus] rob_alloc_pc,
    output reg rob_alloc_pred,
    output reg [`InstAddrBus] rob_alloc_pred_target,
    input wire [`ROB_ID_WIDTH-1:0] rob_alloc_id, 
    
    // ROB Query
    output reg [`ROB_ID_WIDTH-1:0] rob_query1_id,
    input wire rob_query1_ready,
    input wire [`RegBus] rob_query1_value,
    
    output reg [`ROB_ID_WIDTH-1:0] rob_query2_id,
    input wire rob_query2_ready,
    input wire [`RegBus] rob_query2_value,
    
    // RAT
    output reg rat_we,
    output reg [4:0] rat_rd,
    output reg [`ROB_ID_WIDTH-1:0] rat_rob_id,
    
    output reg [4:0] rat_rs1,
    output reg [4:0] rat_rs2,
    input wire rat_rs1_valid, 
    input wire [`ROB_ID_WIDTH-1:0] rat_rs1_rob_id,
    input wire rat_rs2_valid,
    input wire [`ROB_ID_WIDTH-1:0] rat_rs2_rob_id,
    
    // RegFile
    output reg rf_re1,
    output reg [4:0] rf_raddr1,
    input wire [`RegBus] rf_rdata1,
    
    output reg rf_re2,
    output reg [4:0] rf_raddr2,
    input wire [`RegBus] rf_rdata2,
    
    // RS ALU
    input wire rs_alu_full,
    output reg rs_alu_we,
    output reg [`AluOpBus] rs_alu_op,
    output reg [`RegBus] rs_alu_vj,
    output reg [`ROB_ID_WIDTH-1:0] rs_alu_qj,
    output reg rs_alu_qj_valid,
    output reg [`RegBus] rs_alu_vk,
    output reg [`ROB_ID_WIDTH-1:0] rs_alu_qk,
    output reg rs_alu_qk_valid,
    output reg [`ROB_ID_WIDTH-1:0] rs_alu_dest,
    output reg [`RegBus] rs_alu_imm,
    output reg [`InstAddrBus] rs_alu_pc,
    output reg [`InstAddrBus] rs_alu_pred_target,

    // RS MDU (New)
    input wire rs_mdu_full,
    output reg rs_mdu_we,
    output reg [`AluOpBus] rs_mdu_op,
    output reg [`RegBus] rs_mdu_vj,
    output reg [`ROB_ID_WIDTH-1:0] rs_mdu_qj,
    output reg rs_mdu_qj_valid,
    output reg [`RegBus] rs_mdu_vk,
    output reg [`ROB_ID_WIDTH-1:0] rs_mdu_qk,
    output reg rs_mdu_qk_valid,
    output reg [`ROB_ID_WIDTH-1:0] rs_mdu_dest,
    output reg [`RegBus] rs_mdu_imm,
    output reg [`InstAddrBus] rs_mdu_pc,
    output reg [`InstAddrBus] rs_mdu_pred_target,
    
    // LSB
    input wire lsb_full,
    output reg lsb_we,
    output reg [`AluOpBus] lsb_op,
    output reg [2:0] lsb_sub_op, 
    output reg [`RegBus] lsb_vj,
    output reg [`ROB_ID_WIDTH-1:0] lsb_qj,
    output reg lsb_qj_valid,
    output reg [`RegBus] lsb_vk,
    output reg [`ROB_ID_WIDTH-1:0] lsb_qk,
    output reg lsb_qk_valid,
    output reg [`ROB_ID_WIDTH-1:0] lsb_dest, 
    output reg [`RegBus] lsb_imm,
    output reg [`InstAddrBus] lsb_pc
);

    wire [6:0] opcode = iq_inst[6:0];
    wire [2:0] funct3 = iq_inst[14:12];
    wire [6:0] funct7 = iq_inst[31:25];
    wire [4:0] rd     = iq_inst[11:7];
    wire [4:0] rs1    = iq_inst[19:15];
    wire [4:0] rs2    = iq_inst[24:20];
    
    reg [`AluOpBus] alu_op;
    reg is_alu;
    reg is_mdu;       // New Flag
    reg is_load;
    reg is_store;
    reg is_branch;
    reg is_jal;
    reg is_jalr;
    reg is_lui;
    reg is_auipc;
    reg is_system;
    
    reg [31:0] imm;
    reg stall;
    
    always @(*) begin
        alu_op = `ALU_OP_NOP;
        is_alu = 0; is_mdu = 0; is_load = 0; is_store = 0; is_branch = 0;
        is_jal = 0; is_jalr = 0; is_lui = 0; is_auipc = 0;
        is_system = 0;
        imm = 0;
        
        case (opcode)
            `INST_OP_IMM: begin
                is_alu = 1; imm = {{20{iq_inst[31]}}, iq_inst[31:20]};
                case (funct3)
                    `FUNCT3_ADD_SUB: alu_op = `ALU_OP_ADD;
                    `FUNCT3_SLL:     alu_op = `ALU_OP_SLL;
                    `FUNCT3_SLT:     alu_op = `ALU_OP_SLT;
                    `FUNCT3_SLTU:    alu_op = `ALU_OP_SLTU;
                    `FUNCT3_XOR:     alu_op = `ALU_OP_XOR;
                    `FUNCT3_SRL_SRA: alu_op = (funct7[5]) ? `ALU_OP_SRA : `ALU_OP_SRL;
                    `FUNCT3_OR:      alu_op = `ALU_OP_OR;
                    `FUNCT3_AND:     alu_op = `ALU_OP_AND;
                endcase
            end
            `INST_OP: begin
                if (funct7 == `FUNCT7_M) begin
                    is_mdu = 1; imm = 0;
                    case (funct3)
                        `FUNCT3_MUL:    alu_op = `ALU_OP_MUL;
                        `FUNCT3_MULH:   alu_op = `ALU_OP_MULH;
                        `FUNCT3_MULHSU: alu_op = `ALU_OP_MULHSU;
                        `FUNCT3_MULHU:  alu_op = `ALU_OP_MULHU;
                        `FUNCT3_DIV:    alu_op = `ALU_OP_DIV;
                        `FUNCT3_DIVU:   alu_op = `ALU_OP_DIVU;
                        `FUNCT3_REM:    alu_op = `ALU_OP_REM;
                        `FUNCT3_REMU:   alu_op = `ALU_OP_REMU;
                    endcase
                end else begin
                    is_alu = 1; imm = 0; 
                    case (funct3)
                        `FUNCT3_ADD_SUB: alu_op = (funct7[5]) ? `ALU_OP_SUB : `ALU_OP_ADD;
                        `FUNCT3_SLL:     alu_op = `ALU_OP_SLL;
                        `FUNCT3_SLT:     alu_op = `ALU_OP_SLT;
                        `FUNCT3_SLTU:    alu_op = `ALU_OP_SLTU;
                        `FUNCT3_XOR:     alu_op = `ALU_OP_XOR;
                        `FUNCT3_SRL_SRA: alu_op = (funct7[5]) ? `ALU_OP_SRA : `ALU_OP_SRL;
                        `FUNCT3_OR:      alu_op = `ALU_OP_OR;
                        `FUNCT3_AND:     alu_op = `ALU_OP_AND;
                    endcase
                end
            end
            `INST_LUI:   begin is_lui = 1; alu_op = `ALU_OP_LUI; imm = {iq_inst[31:12], 12'b0}; end
            `INST_AUIPC: begin is_auipc = 1; alu_op = `ALU_OP_ADD; imm = {iq_inst[31:12], 12'b0}; end
            `INST_JAL:   begin is_jal = 1; imm = {{12{iq_inst[31]}}, iq_inst[19:12], iq_inst[20], iq_inst[30:21], 1'b0}; alu_op = `ALU_OP_JAL; end
            `INST_JALR:  begin is_jalr = 1; imm = {{20{iq_inst[31]}}, iq_inst[31:20]}; alu_op = `ALU_OP_JAL; end
            `INST_BRANCH: begin
                is_branch = 1; imm = {{20{iq_inst[31]}}, iq_inst[7], iq_inst[30:25], iq_inst[11:8], 1'b0}; 
                case (funct3)
                    `FUNCT3_BEQ:  alu_op = `ALU_OP_BEQ;
                    `FUNCT3_BNE:  alu_op = `ALU_OP_BNE;
                    `FUNCT3_BLT:  alu_op = `ALU_OP_BLT;
                    `FUNCT3_BGE:  alu_op = `ALU_OP_BGE;
                    `FUNCT3_BLTU: alu_op = `ALU_OP_BLTU;
                    `FUNCT3_BGEU: alu_op = `ALU_OP_BGEU;
                endcase
            end
            `INST_LOAD:  begin is_load = 1; alu_op = `ALU_OP_LOAD; imm = {{20{iq_inst[31]}}, iq_inst[31:20]}; end
            `INST_STORE: begin is_store = 1; alu_op = `ALU_OP_STORE; imm = {{20{iq_inst[31]}}, iq_inst[31:25], iq_inst[11:7]}; end
            `INST_ECALL: begin is_system = 1; end
        endcase
    end
    
    wire use_alu_rs = is_alu || is_lui || is_auipc || is_branch || is_jal || is_jalr;
    wire use_mdu_rs = is_mdu;
    wire use_lsb = is_load || is_store;
    
    always @(*) begin
        iq_re = 0;
        rob_alloc_req = 0; rob_alloc_op = alu_op; rob_alloc_rd = rd; rob_alloc_pc = iq_pc; 
        rob_alloc_pred = iq_pred_taken;             // Pass prediction
        rob_alloc_pred_target = iq_pred_target;     // Pass prediction
        
        rat_we = 0; rat_rd = rd; rat_rob_id = rob_alloc_id;
        rat_rs1 = rs1; rat_rs2 = rs2;
        rf_re1 = 0; rf_raddr1 = rs1; rf_re2 = 0; rf_raddr2 = rs2;
        rob_query1_id = rat_rs1_rob_id; rob_query2_id = rat_rs2_rob_id;
        
        // ALU RS Defaults
        rs_alu_we = 0; rs_alu_op = alu_op; rs_alu_vj = 0; rs_alu_qj = 0; rs_alu_qj_valid = 0;
        rs_alu_vk = 0; rs_alu_qk = 0; rs_alu_qk_valid = 0; rs_alu_dest = rob_alloc_id;
        rs_alu_imm = imm; rs_alu_pc = iq_pc; 
        rs_alu_pred_target = iq_pred_target; 

        // MDU RS Defaults
        rs_mdu_we = 0; rs_mdu_op = alu_op; rs_mdu_vj = 0; rs_mdu_qj = 0; rs_mdu_qj_valid = 0;
        rs_mdu_vk = 0; rs_mdu_qk = 0; rs_mdu_qk_valid = 0; rs_mdu_dest = rob_alloc_id;
        rs_mdu_imm = imm; rs_mdu_pc = iq_pc; 
        rs_mdu_pred_target = iq_pred_target; 

        // LSB Defaults
        lsb_we = 0; lsb_op = alu_op; lsb_sub_op = funct3; 
        lsb_vj = 0; lsb_qj = 0; lsb_qj_valid = 0;
        lsb_vk = 0; lsb_qk = 0; lsb_qk_valid = 0; lsb_dest = rob_alloc_id; 
        lsb_imm = imm; lsb_pc = iq_pc;
        
        stall = 0;
        if (use_alu_rs && rs_alu_full) stall = 1;
        if (use_mdu_rs && rs_mdu_full) stall = 1;
        if (use_lsb && lsb_full) stall = 1;
        if (rob_full) stall = 1;
        if (is_system) stall = 1; 
        
        if (!iq_empty && !stall) begin
            iq_re = 1;
            rob_alloc_req = 1;
            
            if ((is_alu || is_mdu || is_lui || is_auipc || is_jal || is_jalr || is_load) && (rd != 0)) begin
                rat_we = 1;
            end
            
            // Operands
            // ALU, MDU, Branch, JALR, Load, Store all need RS1
            if ((is_alu && opcode != `INST_LUI && opcode != `INST_AUIPC && opcode != `INST_JAL) ||
                is_mdu || is_branch || is_jalr || is_load || is_store) begin
                
                if (rat_rs1_valid) begin 
                    if (rob_query1_ready) begin
                       rs_alu_vj = rob_query1_value; rs_alu_qj_valid = 0;
                       rs_mdu_vj = rob_query1_value; rs_mdu_qj_valid = 0;
                       lsb_vj = rob_query1_value; lsb_qj_valid = 0;
                    end else begin
                       rs_alu_qj = rat_rs1_rob_id; rs_alu_qj_valid = 1;
                       rs_mdu_qj = rat_rs1_rob_id; rs_mdu_qj_valid = 1;
                       lsb_qj = rat_rs1_rob_id; lsb_qj_valid = 1;
                    end
                end else begin 
                    rf_re1 = 1;
                    rs_alu_vj = rf_rdata1; rs_alu_qj_valid = 0;
                    rs_mdu_vj = rf_rdata1; rs_mdu_qj_valid = 0;
                    lsb_vj = rf_rdata1; lsb_qj_valid = 0;
                end
            end else if (is_jal || is_auipc) begin
                 rs_alu_vj = iq_pc; rs_alu_qj_valid = 0;
            end
            
            // RS2
            if ((opcode == `INST_OP) || is_mdu || is_branch || is_store) begin
                if (rat_rs2_valid) begin
                    if (rob_query2_ready) begin
                       rs_alu_vk = rob_query2_value; rs_alu_qk_valid = 0;
                       rs_mdu_vk = rob_query2_value; rs_mdu_qk_valid = 0;
                       lsb_vk = rob_query2_value; lsb_qk_valid = 0;
                    end else begin
                       rs_alu_qk = rat_rs2_rob_id; rs_alu_qk_valid = 1;
                       rs_mdu_qk = rat_rs2_rob_id; rs_mdu_qk_valid = 1;
                       lsb_qk = rat_rs2_rob_id; lsb_qk_valid = 1;
                    end
                end else begin
                    rf_re2 = 1;
                    rs_alu_vk = rf_rdata2; rs_alu_qk_valid = 0;
                    rs_mdu_vk = rf_rdata2; rs_mdu_qk_valid = 0;
                    lsb_vk = rf_rdata2; lsb_qk_valid = 0;
                end
            end else begin
                rs_alu_vk = imm; rs_alu_qk_valid = 0;
            end
            
            if (use_alu_rs) begin
                rs_alu_we = 1;
            end else if (use_mdu_rs) begin
                rs_mdu_we = 1;
            end else if (use_lsb) begin
                lsb_we = 1;
            end
        end
    end

    // TRACING
    always @(posedge clk) begin
        if (iq_re) begin
            $display("Time: %t | ISSUE: PC=%h | Op=%h | DestROB=%d | RD=%d", $time, iq_pc, alu_op, rob_alloc_id, rob_alloc_rd);
        end
    end

endmodule