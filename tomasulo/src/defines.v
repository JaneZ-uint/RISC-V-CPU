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
`define AluOpBus 4:0    
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
`define INST_ECALL   7'b1110011 

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

// Funct7 M-Extension
`define FUNCT7_M       7'b0000001

// Funct3 M-Extension
`define FUNCT3_MUL     3'b000
`define FUNCT3_MULH    3'b001
`define FUNCT3_MULHSU  3'b010
`define FUNCT3_MULHU   3'b011
`define FUNCT3_DIV     3'b100
`define FUNCT3_DIVU    3'b101
`define FUNCT3_REM     3'b110
`define FUNCT3_REMU    3'b111

// ALU Ops (5 bits)
`define ALU_OP_NOP  5'b00000
`define ALU_OP_ADD  5'b00001
`define ALU_OP_SUB  5'b00010
`define ALU_OP_SLL  5'b00011
`define ALU_OP_SLT  5'b00100
`define ALU_OP_SLTU 5'b00101
`define ALU_OP_XOR  5'b00110
`define ALU_OP_SRL  5'b00111
`define ALU_OP_SRA  5'b01000
`define ALU_OP_OR   5'b01001
`define ALU_OP_AND  5'b01010
`define ALU_OP_LUI  5'b01011 
`define ALU_OP_JAL  5'b01100 

// Branch Ops
`define ALU_OP_BEQ  5'b10000
`define ALU_OP_BNE  5'b10001
`define ALU_OP_BLT  5'b10010
`define ALU_OP_BGE  5'b10011
`define ALU_OP_BLTU 5'b10100
`define ALU_OP_BGEU 5'b10101

// LS Ops
`define ALU_OP_LOAD  5'b11000
`define ALU_OP_STORE 5'b11001

// MDU Ops
`define ALU_OP_MUL    5'b11010
`define ALU_OP_MULH   5'b11011
`define ALU_OP_MULHSU 5'b11100
`define ALU_OP_MULHU  5'b11101
`define ALU_OP_DIV    5'b11110
`define ALU_OP_DIVU   5'b11111
`define ALU_OP_REM    5'b01101  // Filling gaps
`define ALU_OP_REMU   5'b01110

`endif
