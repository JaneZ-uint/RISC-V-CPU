`include "defines.v"

module id_stage(
    input wire rst,
    input wire [`InstAddrBus] pc_i,
    input wire [`InstBus] inst_i,
    
    // RegFile Interface
    input wire [`DataBus] reg1_data_i,
    input wire [`DataBus] reg2_data_i,
    output reg reg1_read_o,
    output reg reg2_read_o,
    output reg [`RegAddrBus] reg1_addr_o,
    output reg [`RegAddrBus] reg2_addr_o,
    
    // Hazard Detection Inputs
    input wire ex_wreg_i,
    input wire [`RegAddrBus] ex_wd_i,
    input wire mem_wreg_i,
    input wire [`RegAddrBus] mem_wd_i,
    
    // Outputs to EX
    output reg [`AluOpBus] aluop_o,
    output reg [`AluSelBus] alusel_o,
    output reg [`DataBus] reg1_o,
    output reg [`DataBus] reg2_o,
    output reg [`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg [`InstAddrBus] pc_o,
    output reg [`DataBus] imm_o,
    output reg [`DataBus] reg2_data_o, // For Store (rs2)
    
    output reg stall_req
);

    wire [6:0] opcode = inst_i[6:0];
    wire [2:0] funct3 = inst_i[14:12];
    wire [6:0] funct7 = inst_i[31:25];
    
    reg [`DataBus] imm;

    always @(*) begin
        if (rst == `RstEnable) begin
            aluop_o = `ALU_OP_NOP;
            alusel_o = 3'b000;
            wd_o = 5'b00000;
            wreg_o = `WriteDisable;
            reg1_read_o = 1'b0;
            reg2_read_o = 1'b0;
            reg1_addr_o = 5'b00000;
            reg2_addr_o = 5'b00000;
            imm = `ZeroWord;
            pc_o = `ZeroWord;
            stall_req = 1'b0;
        end else begin
            aluop_o = `ALU_OP_NOP;
            alusel_o = 3'b000;
            wd_o = inst_i[11:7];
            wreg_o = `WriteDisable;
            reg1_read_o = 1'b0;
            reg2_read_o = 1'b0;
            reg1_addr_o = inst_i[19:15]; // rs1
            reg2_addr_o = inst_i[24:20]; // rs2
            imm = `ZeroWord;
            pc_o = pc_i;
            stall_req = 1'b0;

            case (opcode)
                `INST_OP_IMM: begin
                    wreg_o = `WriteEnable;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b0;
                    imm = {{20{inst_i[31]}}, inst_i[31:20]};
                    case (funct3)
                        `FUNCT3_ADD_SUB: aluop_o = `ALU_OP_ADD;
                        `FUNCT3_SLT:     aluop_o = `ALU_OP_SLT;
                        `FUNCT3_SLTU:    aluop_o = `ALU_OP_SLTU;
                        `FUNCT3_XOR:     aluop_o = `ALU_OP_XOR;
                        `FUNCT3_OR:      aluop_o = `ALU_OP_OR;
                        `FUNCT3_AND:     aluop_o = `ALU_OP_AND;
                        `FUNCT3_SLL: begin
                            aluop_o = `ALU_OP_SLL;
                            imm = {27'b0, inst_i[24:20]}; // shamt
                        end
                        `FUNCT3_SRL_SRA: begin
                            if (funct7[5]) aluop_o = `ALU_OP_SRA;
                            else           aluop_o = `ALU_OP_SRL;
                            imm = {27'b0, inst_i[24:20]}; // shamt
                        end
                        default: aluop_o = `ALU_OP_NOP;
                    endcase
                end
                `INST_OP: begin
                    wreg_o = `WriteEnable;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    case (funct3)
                        `FUNCT3_ADD_SUB: begin
                            if (funct7[5]) aluop_o = `ALU_OP_SUB;
                            else           aluop_o = `ALU_OP_ADD;
                        end
                        `FUNCT3_SLL:     aluop_o = `ALU_OP_SLL;
                        `FUNCT3_SLT:     aluop_o = `ALU_OP_SLT;
                        `FUNCT3_SLTU:    aluop_o = `ALU_OP_SLTU;
                        `FUNCT3_XOR:     aluop_o = `ALU_OP_XOR;
                        `FUNCT3_SRL_SRA: begin
                            if (funct7[5]) aluop_o = `ALU_OP_SRA;
                            else           aluop_o = `ALU_OP_SRL;
                        end
                        `FUNCT3_OR:      aluop_o = `ALU_OP_OR;
                        `FUNCT3_AND:     aluop_o = `ALU_OP_AND;
                        default: aluop_o = `ALU_OP_NOP;
                    endcase
                end
                `INST_LUI: begin
                    wreg_o = `WriteEnable;
                    reg1_read_o = 1'b0;
                    reg2_read_o = 1'b0;
                    aluop_o = `ALU_OP_LUI; // Pass Imm
                    imm = {inst_i[31:12], 12'b0};
                end
                `INST_AUIPC: begin
                    wreg_o = `WriteEnable;
                    reg1_read_o = 1'b0; // Use PC
                    reg2_read_o = 1'b0;
                    aluop_o = `ALU_OP_ADD;
                    // We need to pass PC as operand 1.
                    // But reg1_o is assigned from reg1_data_i usually.
                    // We will handle operand muxing below.
                    imm = {inst_i[31:12], 12'b0};
                end
                `INST_JAL: begin
                    wreg_o = `WriteEnable;
                    reg1_read_o = 1'b0;
                    reg2_read_o = 1'b0;
                    aluop_o = `ALU_OP_JAL;
                    imm = {{12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
                end
                `INST_JALR: begin
                    wreg_o = `WriteEnable;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b0;
                    aluop_o = `ALU_OP_JAL; // Use same logic, but target calc differs
                    imm = {{20{inst_i[31]}}, inst_i[31:20]};
                end
                `INST_BRANCH: begin
                    wreg_o = `WriteDisable;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1;
                    aluop_o = `ALU_OP_NOP; // ALU not used for result, but for comparison?
                    // We can use ALU for comparison or separate logic in EX.
                    // Let's set aluop to something specific or handle in EX.
                    // For now, NOP, but we need to pass operands.
                    imm = {{20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
                end
                `INST_LOAD: begin
                    wreg_o = `WriteEnable;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b0;
                    aluop_o = `ALU_OP_ADD; // Calculate Address
                    imm = {{20{inst_i[31]}}, inst_i[31:20]};
                end
                `INST_STORE: begin
                    wreg_o = `WriteDisable;
                    reg1_read_o = 1'b1;
                    reg2_read_o = 1'b1; // Need rs2 for data
                    aluop_o = `ALU_OP_ADD; // Calculate Address
                    imm = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
                end
                default: begin
                end
            endcase
        end
    end

    // Operand Muxing
    always @(*) begin
        if (rst == `RstEnable) begin
            reg1_o = `ZeroWord;
            reg2_o = `ZeroWord;
        end else begin
            // Operand 1
            if (opcode == `INST_AUIPC || opcode == `INST_JAL) begin
                reg1_o = pc_i;
            end else if (reg1_read_o) begin
                reg1_o = reg1_data_i;
            end else begin
                reg1_o = `ZeroWord;
            end

            // Operand 2
            if (opcode == `INST_OP_IMM || opcode == `INST_LUI || opcode == `INST_AUIPC || opcode == `INST_LOAD || opcode == `INST_STORE) begin
                reg2_o = imm;
            end else if (opcode == `INST_JAL || opcode == `INST_JALR) begin
                reg2_o = 32'd4; // For Link Address (PC+4)
            end else if (reg2_read_o) begin
                reg2_o = reg2_data_i;
            end else begin
                reg2_o = `ZeroWord;
            end
        end
    end

    // Output Immediate and RS2 Data
    always @(*) begin
        imm_o = imm;
        reg2_data_o = reg2_data_i;
    end

    // Hazard Detection
    always @(*) begin
        stall_req = 1'b0;
        if (rst == `RstDisable) begin
            if (reg1_read_o && reg1_addr_o != 5'b0) begin
                if ((ex_wreg_i && ex_wd_i == reg1_addr_o) || 
                    (mem_wreg_i && mem_wd_i == reg1_addr_o)) begin
                    stall_req = 1'b1;
                end
            end
            if (reg2_read_o && reg2_addr_o != 5'b0) begin
                if ((ex_wreg_i && ex_wd_i == reg2_addr_o) || 
                    (mem_wreg_i && mem_wd_i == reg2_addr_o)) begin
                    stall_req = 1'b1;
                end
            end
        end
    end

endmodule
