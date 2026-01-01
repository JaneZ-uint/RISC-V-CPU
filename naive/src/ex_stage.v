`include "defines.v"

module ex_stage(
    input wire rst,
    
    // Inputs from ID
    input wire [`AluOpBus] aluop_i,
    input wire [`DataBus] reg1_i,
    input wire [`DataBus] reg2_i,
    input wire [`RegAddrBus] wd_i,
    input wire wreg_i,
    input wire [`InstAddrBus] pc_i,
    input wire [`DataBus] imm_i,
    input wire [`DataBus] reg2_data_i, // rs2 raw value
    input wire [`InstBus] inst_i,
    
    // Outputs to MEM
    output reg [`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg [`DataBus] wdata_o,
    output reg [`DataBus] mem_addr_o,
    output reg [`DataBus] store_data_o,
    output reg [`InstBus] inst_o,
    
    // Outputs to Ctrl/PC
    output reg branch_flag_o,
    output reg [`InstAddrBus] branch_target_address_o
);

    wire [2:0] funct3 = inst_i[14:12];
    
    // ALU Logic
    always @(*) begin
        if (rst == `RstEnable) begin
            wdata_o = `ZeroWord;
            mem_addr_o = `ZeroWord;
        end else begin
            case (aluop_i)
                `ALU_OP_ADD: wdata_o = reg1_i + reg2_i;
                `ALU_OP_SUB: wdata_o = reg1_i - reg2_i;
                `ALU_OP_SLL: wdata_o = reg1_i << reg2_i[4:0];
                `ALU_OP_SLT: wdata_o = ($signed(reg1_i) < $signed(reg2_i)) ? 32'b1 : 32'b0;
                `ALU_OP_SLTU: wdata_o = (reg1_i < reg2_i) ? 32'b1 : 32'b0;
                `ALU_OP_XOR: wdata_o = reg1_i ^ reg2_i;
                `ALU_OP_SRL: wdata_o = reg1_i >> reg2_i[4:0];
                `ALU_OP_SRA: wdata_o = $signed(reg1_i) >>> reg2_i[4:0];
                `ALU_OP_OR:  wdata_o = reg1_i | reg2_i;
                `ALU_OP_AND: wdata_o = reg1_i & reg2_i;
                `ALU_OP_LUI: wdata_o = reg2_i; // reg2 is imm
                `ALU_OP_JAL: wdata_o = pc_i + 4; // Link Address
                default: wdata_o = `ZeroWord;
            endcase
            
            // For Load/Store, mem_addr is ALU result (ADD)
            mem_addr_o = wdata_o;
        end
    end

    // Branch Logic
    always @(*) begin
        branch_flag_o = 1'b0;
        branch_target_address_o = `ZeroWord;
        if (rst == `RstDisable) begin
            case (inst_i[6:0]) // Opcode
                `INST_JAL: begin
                    branch_flag_o = 1'b1;
                    branch_target_address_o = pc_i + imm_i;
                end
                `INST_JALR: begin
                    branch_flag_o = 1'b1;
                    branch_target_address_o = (reg1_i + imm_i) & ~32'b1; // LSB set to 0
                end
                `INST_BRANCH: begin
                    case (funct3)
                        `FUNCT3_BEQ:  if (reg1_i == reg2_data_i) branch_flag_o = 1'b1;
                        `FUNCT3_BNE:  if (reg1_i != reg2_data_i) branch_flag_o = 1'b1;
                        `FUNCT3_BLT:  if ($signed(reg1_i) < $signed(reg2_data_i)) branch_flag_o = 1'b1;
                        `FUNCT3_BGE:  if ($signed(reg1_i) >= $signed(reg2_data_i)) branch_flag_o = 1'b1;
                        `FUNCT3_BLTU: if (reg1_i < reg2_data_i) branch_flag_o = 1'b1;
                        `FUNCT3_BGEU: if (reg1_i >= reg2_data_i) branch_flag_o = 1'b1;
                    endcase
                    branch_target_address_o = pc_i + imm_i;
                end
            endcase
        end
    end

    // Pass through
    always @(*) begin
        wd_o = wd_i;
        wreg_o = wreg_i;
        store_data_o = reg2_data_i;
        inst_o = inst_i;
    end

endmodule
