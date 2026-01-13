`include "defines.v"

module instruction_queue #(
    parameter SIZE = 8,
    parameter PTR_WIDTH = 3
)(
    input wire clk,
    input wire rst,
    input wire flush,               // Flush on branch misprediction
    
    // Write Port (From Fetch)
    input wire we,
    input wire [`InstBus] inst_i,
    input wire [`InstAddrBus] pc_i,
    
    // Read Port (To Issue)
    input wire re,
    output wire [`InstBus] inst_o,
    output wire [`InstAddrBus] pc_o,
    
    // Status
    output wire full,
    output wire empty
);

    reg [`InstBus] buffer_inst [0:SIZE-1];
    reg [`InstAddrBus] buffer_pc [0:SIZE-1];
    
    reg [PTR_WIDTH-1:0] w_ptr;
    reg [PTR_WIDTH-1:0] r_ptr;
    reg [PTR_WIDTH:0] count;    // Extra bit to hold 'SIZE' value
    
    assign full = (count == SIZE);
    assign empty = (count == 0);
    
    assign inst_o = buffer_inst[r_ptr];
    assign pc_o = buffer_pc[r_ptr];
    
    always @(posedge clk) begin
        if (rst == `RstEnable || flush == 1'b1) begin
            w_ptr <= 0;
            r_ptr <= 0;
            count <= 0;
        end else begin
            case ({we, re})
                2'b10: begin // Write only
                    if (!full) begin
                        buffer_inst[w_ptr] <= inst_i;
                        buffer_pc[w_ptr] <= pc_i;
                        w_ptr <= w_ptr + 1'b1;
                        count <= count + 1'b1;
                    end
                end
                2'b01: begin // Read only
                    if (!empty) begin
                        r_ptr <= r_ptr + 1'b1;
                        count <= count - 1'b1;
                    end
                end
                2'b11: begin // Read and Write
                    // If full, we can read (make space) but not write in same cycle effectively unless we forward?
                    // Standard FIFO: Read decrs count, Write incrs count. Net 0.
                    // If empty: Read fails, Write succeeds. Net +1.
                    // If full: Read succeeds, Write succeeds (into the spot freed?). Net 0.
                    
                    if (empty) begin
                        // Can't read from empty
                        buffer_inst[w_ptr] <= inst_i;
                        buffer_pc[w_ptr] <= pc_i;
                        w_ptr <= w_ptr + 1'b1;
                        count <= count + 1'b1;
                    end else if (full) begin
                        // Read first, then write? 
                        // In hardware, simultaneous.
                        // Read happens from r_ptr. Write happens to w_ptr. 
                        // If full, w_ptr == r_ptr. 
                        // So we overwrite the one being read? No, that's dangerous.
                        // Standard FIFO logic usually prohibits write if full.
                        // But if we read in same cycle, we DO make space.
                        
                        r_ptr <= r_ptr + 1'b1;
                        buffer_inst[w_ptr] <= inst_i;
                        buffer_pc[w_ptr] <= pc_i;
                        w_ptr <= w_ptr + 1'b1;
                        // Count stays same (Full)
                    end else begin
                        // Not full, not empty
                        r_ptr <= r_ptr + 1'b1;
                        buffer_inst[w_ptr] <= inst_i;
                        buffer_pc[w_ptr] <= pc_i;
                        w_ptr <= w_ptr + 1'b1;
                        // Count stays same
                    end
                end
                default: ; 
            endcase
        end
    end

endmodule
