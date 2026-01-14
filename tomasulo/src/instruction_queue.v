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
    input wire pred_i,              // New: Predicted Taken?
    input wire [`InstAddrBus] pred_target_i, // New: Predicted Target
    
    // Read Port (To Issue)
    input wire re,
    output wire [`InstBus] inst_o,
    output wire [`InstAddrBus] pc_o,
    output wire pred_o,             // New
    output wire [`InstAddrBus] pred_target_o, // New
    
    // Status
    output wire full,
    output wire empty
);

    reg [`InstBus] buffer_inst [0:SIZE-1];
    reg [`InstAddrBus] buffer_pc [0:SIZE-1];
    reg buffer_pred [0:SIZE-1];           // New Array
    reg [`InstAddrBus] buffer_pred_target [0:SIZE-1]; // New Array
    
    reg [PTR_WIDTH-1:0] w_ptr;
    reg [PTR_WIDTH-1:0] r_ptr;
    reg [PTR_WIDTH:0] count;    // Extra bit to hold 'SIZE' value
    
    assign full = (count == SIZE);
    assign empty = (count == 0);
    
    assign inst_o = buffer_inst[r_ptr];
    assign pc_o = buffer_pc[r_ptr];
    assign pred_o = buffer_pred[r_ptr];
    assign pred_target_o = buffer_pred_target[r_ptr];
    
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
                        buffer_pred[w_ptr] <= pred_i;
                        buffer_pred_target[w_ptr] <= pred_target_i;
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
                    if (empty) begin
                        buffer_inst[w_ptr] <= inst_i;
                        buffer_pc[w_ptr] <= pc_i;
                        buffer_pred[w_ptr] <= pred_i;
                        buffer_pred_target[w_ptr] <= pred_target_i;
                        w_ptr <= w_ptr + 1'b1;
                        count <= count + 1'b1;
                    end else if (full) begin
                        r_ptr <= r_ptr + 1'b1;
                        buffer_inst[w_ptr] <= inst_i;
                        buffer_pc[w_ptr] <= pc_i;
                        buffer_pred[w_ptr] <= pred_i;
                        buffer_pred_target[w_ptr] <= pred_target_i;
                        w_ptr <= w_ptr + 1'b1;
                    end else begin
                        r_ptr <= r_ptr + 1'b1;
                        buffer_inst[w_ptr] <= inst_i;
                        buffer_pc[w_ptr] <= pc_i;
                        buffer_pred[w_ptr] <= pred_i;
                        buffer_pred_target[w_ptr] <= pred_target_i;
                        w_ptr <= w_ptr + 1'b1;
                    end
                end
                default: ; 
            endcase
        end
    end

endmodule
