`include "defines.v"
`include "params.v"

module rat(
    input wire clk,
    input wire rst,
    input wire flush,
    
    // Write Port (Allocation)
    input wire we,
    input wire [4:0] rw_addr,
    input wire [`ROB_ID_WIDTH-1:0] write_rob_id,
    
    // Read Ports
    input wire [4:0] rs1_addr,
    output wire rs1_valid,
    output wire [`ROB_ID_WIDTH-1:0] rs1_rob_id,
    
    input wire [4:0] rs2_addr,
    output wire rs2_valid,
    output wire [`ROB_ID_WIDTH-1:0] rs2_rob_id,
    
    // Commit Port
    input wire commit_we,
    input wire [4:0] commit_addr,
    input wire [`ROB_ID_WIDTH-1:0] commit_rob_id
);

    reg [`ROB_ID_WIDTH-1:0] map_rob_id [0:31];
    reg [31:0] map_valid; 

    assign rs1_valid = map_valid[rs1_addr];
    assign rs1_rob_id = map_rob_id[rs1_addr];
    
    assign rs2_valid = map_valid[rs2_addr];
    assign rs2_rob_id = map_rob_id[rs2_addr];
    
    integer i;

    always @(posedge clk) begin
        if (rst == `RstEnable || flush == 1'b1) begin
            map_valid <= 32'b0;
        end else begin
            // Commit: If the committing ROB ID matches the current mapping, clear it (Set to ARF)
            if (commit_we && (commit_addr != 5'b0)) begin
                if (map_valid[commit_addr] && map_rob_id[commit_addr] == commit_rob_id) begin
                    map_valid[commit_addr] <= 1'b0;
                end
            end
            
            // Allocate: Overwrite mapping (Even if committing same cycle, Alloc is newer)
            if (we && (rw_addr != 5'b0)) begin
                map_valid[rw_addr] <= 1'b1;
                map_rob_id[rw_addr] <= write_rob_id;
            end
        end
    end

endmodule
