`include "defines.v"

module ex_mem_reg(
    input wire clk,
    input wire rst,
    input wire [5:0] stall,
    input wire [5:0] flush,
    
    input wire [`RegAddrBus] ex_wd,
    input wire ex_wreg,
    input wire [`DataBus] ex_wdata,
    input wire [`DataBus] ex_mem_addr,
    input wire [`DataBus] ex_store_data,
    input wire [`InstBus] ex_inst,
    
    output reg [`RegAddrBus] mem_wd,
    output reg mem_wreg,
    output reg [`DataBus] mem_wdata,
    output reg [`DataBus] mem_mem_addr,
    output reg [`DataBus] mem_store_data,
    output reg [`InstBus] mem_inst
);

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            mem_wd <= 5'b00000;
            mem_wreg <= `WriteDisable;
            mem_wdata <= `ZeroWord;
            mem_mem_addr <= `ZeroWord;
            mem_store_data <= `ZeroWord;
            mem_inst <= `ZeroWord;
        end else if (flush[3] == 1'b1) begin
            mem_wd <= 5'b00000;
            mem_wreg <= `WriteDisable;
            mem_wdata <= `ZeroWord;
            mem_mem_addr <= `ZeroWord;
            mem_store_data <= `ZeroWord;
            mem_inst <= `ZeroWord;
        end else if (stall[3] == `WriteEnable) begin
            // Keep
        end else begin
            mem_wd <= ex_wd;
            mem_wreg <= ex_wreg;
            mem_wdata <= ex_wdata;
            mem_mem_addr <= ex_mem_addr;
            mem_store_data <= ex_store_data;
            mem_inst <= ex_inst;
        end
    end

endmodule
