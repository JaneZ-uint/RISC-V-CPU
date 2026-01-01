`include "defines.v"

module id_ex_reg(
    input wire clk,
    input wire rst,
    input wire [5:0] stall,
    input wire [5:0] flush,
    
    input wire [`AluOpBus] id_aluop,
    input wire [`DataBus] id_reg1,
    input wire [`DataBus] id_reg2,
    input wire [`RegAddrBus] id_wd,
    input wire id_wreg,
    input wire [`InstAddrBus] id_pc,
    input wire [`DataBus] id_imm,
    input wire [`DataBus] id_reg2_data,
    input wire [`InstBus] id_inst,
    
    output reg [`AluOpBus] ex_aluop,
    output reg [`DataBus] ex_reg1,
    output reg [`DataBus] ex_reg2,
    output reg [`RegAddrBus] ex_wd,
    output reg ex_wreg,
    output reg [`InstAddrBus] ex_pc,
    output reg [`DataBus] ex_imm,
    output reg [`DataBus] ex_reg2_data,
    output reg [`InstBus] ex_inst
);

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            ex_aluop <= `ALU_OP_NOP;
            ex_reg1 <= `ZeroWord;
            ex_reg2 <= `ZeroWord;
            ex_wd <= 5'b00000;
            ex_wreg <= `WriteDisable;
            ex_pc <= `ZeroWord;
            ex_imm <= `ZeroWord;
            ex_reg2_data <= `ZeroWord;
            ex_inst <= `ZeroWord;
        end else if (flush[2] == 1'b1) begin
            ex_aluop <= `ALU_OP_NOP;
            ex_reg1 <= `ZeroWord;
            ex_reg2 <= `ZeroWord;
            ex_wd <= 5'b00000;
            ex_wreg <= `WriteDisable;
            ex_pc <= `ZeroWord;
            ex_imm <= `ZeroWord;
            ex_reg2_data <= `ZeroWord;
            ex_inst <= `ZeroWord;
        end else if (stall[2] == `WriteEnable) begin
            // Keep
        end else begin
            ex_aluop <= id_aluop;
            ex_reg1 <= id_reg1;
            ex_reg2 <= id_reg2;
            ex_wd <= id_wd;
            ex_wreg <= id_wreg;
            ex_pc <= id_pc;
            ex_imm <= id_imm;
            ex_reg2_data <= id_reg2_data;
            ex_inst <= id_inst;
        end
    end

endmodule
