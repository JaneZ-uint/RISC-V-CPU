`include "defines.v"

module regfile(
    input wire clk,
    input wire rst,
    
    // Write Port
    input wire we,
    input wire [`RegAddrBus] waddr,
    input wire [`DataBus] wdata,
    
    // Read Port 1
    input wire re1,
    input wire [`RegAddrBus] raddr1,
    output reg [`DataBus] rdata1,
    
    // Read Port 2
    input wire re2,
    input wire [`RegAddrBus] raddr2,
    output reg [`DataBus] rdata2
);

    reg [`DataBus] regs[0:31];
    integer i;

    // Write
    always @(posedge clk) begin
        if (rst == `RstDisable) begin
            if ((we == `WriteEnable) && (waddr != 5'h0)) begin
                regs[waddr] <= wdata;
            end
        end else begin
             for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= `ZeroWord;
            end
        end
    end

    // Read 1
    always @(*) begin
        if (rst == `RstEnable) begin
            rdata1 = `ZeroWord;
        end else if (raddr1 == 5'h0) begin
            rdata1 = `ZeroWord;
        end else if ((raddr1 == waddr) && (we == `WriteEnable) && (re1 == `ReadEnable)) begin
            rdata1 = wdata; // Internal Forwarding
        end else if (re1 == `ReadEnable) begin
            rdata1 = regs[raddr1];
        end else begin
            rdata1 = `ZeroWord;
        end
    end

    // Read 2
    always @(*) begin
        if (rst == `RstEnable) begin
            rdata2 = `ZeroWord;
        end else if (raddr2 == 5'h0) begin
            rdata2 = `ZeroWord;
        end else if ((raddr2 == waddr) && (we == `WriteEnable) && (re2 == `ReadEnable)) begin
            rdata2 = wdata; // Internal Forwarding
        end else if (re2 == `ReadEnable) begin
            rdata2 = regs[raddr2];
        end else begin
            rdata2 = `ZeroWord;
        end
    end

endmodule
