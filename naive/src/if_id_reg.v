`include "defines.v"

module if_id_reg(
    input wire clk,
    input wire rst,
    input wire [5:0] stall,
    input wire [5:0] flush,
    
    input wire [`InstAddrBus] if_pc,
    input wire [`InstBus] if_inst,
    
    output reg [`InstAddrBus] id_pc,
    output reg [`InstBus] id_inst
);

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            id_pc <= `ZeroWord;
            id_inst <= `ZeroWord;
        end else if (flush[1] == 1'b1) begin
            id_pc <= `ZeroWord;
            id_inst <= 32'h00000013; // NOP (addi x0, x0, 0)
        end else if (stall[1] == `WriteEnable) begin
            // Stall, keep data
            id_pc <= id_pc;
            id_inst <= id_inst;
        end else begin
            id_pc <= if_pc;
            id_inst <= if_inst;
        end
    end

endmodule
