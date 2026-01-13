`ifndef DEFINES_V
`define DEFINES_V

// Global
`define RstEnable 1'b1
`define RstDisable 1'b0
`define ZeroWord 32'h00000000
`define WriteEnable 1'b1
`define WriteDisable 1'b0
`define ReadEnable 1'b1
`define ReadDisable 1'b0
`define AluOpBus 3:0
`define AluSelBus 2:0
`define InstBus 31:0
`define InstAddrBus 31:0
`define DataBus 31:0
`define RegAddrBus 4:0
`define RegBus 31:0

// Opcodes
`define INST_LUI     7'b0110111
`define INST_AUIPC   7'b0010111
`define INST_JAL     7'b1101111
`define INST_JALR    7'b1100111
`define INST_BRANCH  7'b1100011
`define INST_LOAD    7'b0000011
`define INST_STORE   7'b0100011
`define INST_OP_IMM  7'b0010011
`define INST_OP      7'b0110011
`define INST_ECALL   7'b1110011 // System

// Funct3 for Branch
`define FUNCT3_BEQ   3'b000
`define FUNCT3_BNE   3'b001
`define FUNCT3_BLT   3'b100
`define FUNCT3_BGE   3'b101
`define FUNCT3_BLTU  3'b110
`define FUNCT3_BGEU  3'b111

// Funct3 for Load
`define FUNCT3_LB    3'b000
`define FUNCT3_LH    3'b001
`define FUNCT3_LW    3'b010
`define FUNCT3_LBU   3'b100
`define FUNCT3_LHU   3'b101

// Funct3 for Store
`define FUNCT3_SB    3'b000
`define FUNCT3_SH    3'b001
`define FUNCT3_SW    3'b010

// Funct3 for OP_IMM / OP
`define FUNCT3_ADD_SUB 3'b000
`define FUNCT3_SLL     3'b001
`define FUNCT3_SLT     3'b010
`define FUNCT3_SLTU    3'b011
`define FUNCT3_XOR     3'b100
`define FUNCT3_SRL_SRA 3'b101
`define FUNCT3_OR      3'b110
`define FUNCT3_AND     3'b111

// ALU Ops
`define ALU_OP_NOP  4'b0000
`define ALU_OP_ADD  4'b0001
`define ALU_OP_SUB  4'b0010
`define ALU_OP_SLL  4'b0011
`define ALU_OP_SLT  4'b0100
`define ALU_OP_SLTU 4'b0101
`define ALU_OP_XOR  4'b0110
`define ALU_OP_SRL  4'b0111
`define ALU_OP_SRA  4'b1000
`define ALU_OP_OR   4'b1001
`define ALU_OP_AND  4'b1010
`define ALU_OP_LUI  4'b1011 // Pass Imm
`define ALU_OP_JAL  4'b1100 // PC + 4

`endif
