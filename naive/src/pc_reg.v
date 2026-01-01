`include "defines.v"

module pc_reg(
    input wire clk,
    input wire rst,
    input wire [5:0] stall,
    input wire branch_flag,
    input wire [`InstAddrBus] branch_target_address,
    
    output reg [`InstAddrBus] pc,
    output reg ce
);

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            ce <= `ReadDisable;
        end else begin
            ce <= `ReadEnable;
        end
    end

    always @(posedge clk) begin
        if (ce == `ReadDisable) begin
            pc <= 32'h00000000;
        end else begin
            if (branch_flag) begin
                pc <= branch_target_address;
            end else if (stall[0] == `WriteEnable) begin
                // Stall, keep PC
                pc <= pc;
            end else begin
                pc <= pc + 4'h4;
            end
        end
    end

endmodule
