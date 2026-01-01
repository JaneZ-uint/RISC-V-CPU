`include "defines.v"

module ctrl(
    input wire rst,
    input wire stall_req_id,
    input wire branch_flag, // From EX stage

    output reg [5:0] stall, // 0: PC, 1: IF/ID, 2: ID/EX, 3: EX/MEM, 4: MEM/WB
    output reg [5:0] flush  // 0: PC, 1: IF/ID, 2: ID/EX, 3: EX/MEM, 4: MEM/WB
);

    always @(*) begin
        stall = 6'b000000;
        flush = 6'b000000;

        if (rst == `RstEnable) begin
            // Do nothing
        end else if (branch_flag) begin
            // Branch taken: Flush IF/ID and ID/EX
            // PC will be updated by branch target
            flush[1] = 1'b1; // Flush IF/ID
            flush[2] = 1'b1; // Flush ID/EX
        end else if (stall_req_id) begin
            // Load-Use Hazard: Stall PC and IF/ID, Flush ID/EX
            stall[0] = 1'b1; // Stall PC
            stall[1] = 1'b1; // Stall IF/ID
            flush[2] = 1'b1; // Flush ID/EX (Insert Bubble)
        end
    end

endmodule
