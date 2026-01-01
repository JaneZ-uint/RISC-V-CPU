`include "defines.v"

module mem_wb_reg(
    input wire clk,
    input wire rst,
    input wire [5:0] stall,
    input wire [5:0] flush,
    
    input wire [`RegAddrBus] mem_wd,
    input wire mem_wreg,
    input wire [`DataBus] mem_wdata,
    
    output reg [`RegAddrBus] wb_wd,
    output reg wb_wreg,
    output reg [`DataBus] wb_wdata
);

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            wb_wd <= 5'b00000;
            wb_wreg <= `WriteDisable;
            wb_wdata <= `ZeroWord;
        end else if (flush[4] == 1'b1) begin
            wb_wd <= 5'b00000;
            wb_wreg <= `WriteDisable;
            wb_wdata <= `ZeroWord;
        end else if (stall[4] == `WriteEnable) begin
            // Keep
        end else begin
            wb_wd <= mem_wd;
            wb_wreg <= mem_wreg;
            wb_wdata <= mem_wdata;
        end
    end

endmodule
