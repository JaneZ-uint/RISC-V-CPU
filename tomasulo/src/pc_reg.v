`include "defines.v"

module pc_reg(
    input wire clk,
    input wire rst,
    
    input wire stall,               // 1: IQ is full or other stall condition
    input wire flush,               // 1: Branch misprediction
    input wire [`InstAddrBus] flush_addr, // Correct address after misprediction
    
    // Branch Prediction Interface (Placeholder for now)
    input wire pred_taken,          // 1: Predict taken
    input wire [`InstAddrBus] pred_target,
    
    output reg [`InstAddrBus] pc,
    output reg ce                   // Chip Enable
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
            if (flush) begin
                // Highest priority: Restore from misprediction
                pc <= flush_addr;
            end else if (stall) begin
                // Stall: Keep current PC
                pc <= pc;
            end else if (pred_taken) begin
                // Predict Taken
                pc <= pred_target;
            end else begin
                // Sequential
                pc <= pc + 4'h4;
            end
        end
    end

endmodule
