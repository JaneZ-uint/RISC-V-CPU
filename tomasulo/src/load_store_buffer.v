`include "defines.v"
`include "params.v"

module load_store_buffer #(
    parameter SIZE = 8
)(
    input wire clk,
    input wire rst,
    input wire flush,
    
    // Dispatch Interface
    input wire lsb_we,
    input wire [`AluOpBus] lsb_op,
    input wire [2:0] lsb_sub_op, // funct3
    input wire [`RegBus] lsb_vj,
    input wire [`ROB_ID_WIDTH-1:0] lsb_qj,
    input wire lsb_qj_valid,
    input wire [`RegBus] lsb_vk,
    input wire [`ROB_ID_WIDTH-1:0] lsb_qk,
    input wire lsb_qk_valid,
    input wire [`ROB_ID_WIDTH-1:0] lsb_dest,
    input wire [`RegBus] lsb_imm,
    input wire [`InstAddrBus] lsb_pc,
    
    output wire full,
    
    // CDB Snoop
    input wire cdb_valid,
    input wire [`ROB_ID_WIDTH-1:0] cdb_rob_id,
    input wire [`RegBus] cdb_value,
    
    // CDB Broadcast Request
    input wire arb_allow,     // Arbiter allows LSB to broadcast
    output reg arb_req,       // LSB requests to broadcast
    output reg [`ROB_ID_WIDTH-1:0] arb_dest,
    output reg [`RegBus] arb_val,
    
    // Memory Interface
    output reg mem_req,       // Request valid
    output reg mem_we,        // 1=Write, 0=Read
    output reg [31:0] mem_addr,
    output reg [31:0] mem_wdata,
    output reg [3:0] mem_mask, // Byte mask
    input wire mem_ready,     // Memory ready to accept request
    input wire [31:0] mem_rdata,
    input wire mem_rvalid     // Memory read data valid
);

    // FIFO Entry Definitions
    reg [`AluOpBus] op [0:SIZE-1];
    reg [2:0] sub_op [0:SIZE-1];
    reg [`RegBus] vj [0:SIZE-1];
    reg [`RegBus] vk [0:SIZE-1];
    reg [`ROB_ID_WIDTH-1:0] qj [0:SIZE-1];
    reg qj_valid [0:SIZE-1];
    reg [`ROB_ID_WIDTH-1:0] qk [0:SIZE-1];
    reg qk_valid [0:SIZE-1];
    reg [`ROB_ID_WIDTH-1:0] dest [0:SIZE-1];
    reg [`RegBus] imm [0:SIZE-1];
    
    // Pointers
    reg [$clog2(SIZE)-1:0] head;
    reg [$clog2(SIZE)-1:0] tail;
    reg [$clog2(SIZE):0] count;
    
    assign full = (count == SIZE);
    wire empty = (count == 0);
    
    integer i;

    // State Machine for current memory operation
    localparam IDLE = 0, WAIT_MEM = 1, WAIT_CDB = 2;
    reg [1:0] state;
    reg [31:0] load_result_buffer;

    always @(posedge clk) begin
        if (rst == `RstEnable || flush == 1'b1) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            arb_req <= 0;
            mem_req <= 0;
            state <= IDLE;
            for(i=0; i<SIZE; i=i+1) begin
                 qj_valid[i] <= 0;
                 qk_valid[i] <= 0;
            end
        end else begin
            
            // --- Dispatch ---
            if (lsb_we && !full) begin
                op[tail] <= lsb_op;
                sub_op[tail] <= lsb_sub_op;
                dest[tail] <= lsb_dest;
                imm[tail] <= lsb_imm;
                
                // Operand Logic with Forwarding check (Snoop during Dispatch)
                if (lsb_qj_valid) begin
                    if (cdb_valid && cdb_rob_id == lsb_qj) begin
                        vj[tail] <= cdb_value;
                        qj_valid[tail] <= 0;
                    end else begin
                        qj[tail] <= lsb_qj;
                        qj_valid[tail] <= 1;
                    end
                end else begin
                    vj[tail] <= lsb_vj;
                    qj_valid[tail] <= 0;
                end
                
                if (lsb_qk_valid) begin
                    if (cdb_valid && cdb_rob_id == lsb_qk) begin
                        vk[tail] <= cdb_value;
                        qk_valid[tail] <= 0;
                    end else begin
                        qk[tail] <= lsb_qk;
                        qk_valid[tail] <= 1;
                    end
                end else begin
                    vk[tail] <= lsb_vk;
                    qk_valid[tail] <= 0;
                end
                
                tail <= (tail == SIZE-1) ? 0 : tail + 1;
                
                if (!(state == WAIT_CDB && arb_allow && count > 0)) begin // Simple logic handling count update vs retire
                     count <= count + 1;
                end
            end else if (state == WAIT_CDB && arb_allow && count > 0) begin
                count <= count - 1;
            end

            // --- Snoop for Existing Entries ---
            if (cdb_valid) begin
                for (i = 0; i < SIZE; i = i + 1) begin
                    // We can just iterate all, valid or not, or be smarter. 
                    // Since it's a circular buffer, indices from head to tail minus 1 are valid. 
                    // But iterating all is easier for RTL (registers always exist).
                    if (qj_valid[i] && qj[i] == cdb_rob_id) begin
                        vj[i] <= cdb_value;
                        qj_valid[i] <= 0;
                    end
                    if (qk_valid[i] && qk[i] == cdb_rob_id) begin
                        vk[i] <= cdb_value;
                        qk_valid[i] <= 0;
                    end
                end
            end

            // --- Execute Head ---
            // Simplified: Only process Head. In-Order Execution.
            
            arb_req <= 0; // Default
            mem_req <= 0; // Default
            
            case (state)
                IDLE: begin
                    if (!empty) begin
                        // Check operands
                        // Load: needs Vj (Base)
                        // Store: needs Vj (Base) and Vk (Value)
                        
                        // Wait for operands
                        if (!qj_valid[head]) begin
                            if (op[head] == `ALU_OP_LOAD) begin
                                // LOAD
                                wire [31:0] addr = vj[head] + imm[head];
                                mem_addr <= addr;
                                mem_we <= 0;
                                mem_req <= 1;
                                // Wait for mem_ready handshake
                                if (mem_ready) begin
                                    state <= WAIT_MEM; // Wait for Data IDLE->WAIT_MEM
                                end
                            end else if (op[head] == `ALU_OP_STORE) begin
                                // STORE
                                if (!qk_valid[head]) begin
                                    wire [31:0] addr = vj[head] + imm[head];
                                    wire [31:0] store_val = vk[head];
                                    
                                    mem_addr <= addr;
                                    mem_we <= 1;
                                    mem_wdata <= store_val;
                                    
                                    // Calc Mask
                                    case (sub_op[head])
                                        3'b000: mem_mask <= 4'b0001 << addr[1:0]; // SB
                                        3'b001: mem_mask <= 4'b0011 << {addr[1], 1'b0}; // SH
                                        default: mem_mask <= 4'b1111; // SW
                                    endcase
                                    
                                    // Align Data for Store (Shift data to correct byte lanes)
                                    case (sub_op[head])
                                        3'b000: mem_wdata <= (store_val & 32'hFF) << (addr[1:0]*8);
                                        3'b001: mem_wdata <= (store_val & 32'hFFFF) << (addr[1]*16);
                                        default: mem_wdata <= store_val;
                                    endcase
                                    
                                    mem_req <= 1;
                                    if (mem_ready) begin
                                        state <= WAIT_CDB; // Store serves as "complete" immediately after issue? 
                                        // Actually need to broadcast "Store Done" (rob_id)
                                        // Or just finish.
                                    end
                                end
                            end
                        end
                    end
                end
                
                WAIT_MEM: begin
                    if (mem_rvalid) begin
                        // Process Data
                        reg [31:0] raw_data;
                        reg [31:0] final_data;
                        raw_data = mem_rdata;
                        
                        // Byte Offset
                        wire [1:0] offset = mem_addr[1:0]; // stored in latch if needed, or assume stable? 
                        // Danger: mem_addr is reg, stays stable until state IDLE
                        
                        case (sub_op[head]) // Using head is safe as head doesn't move
                            3'b000: final_data = {{24{raw_data[7+offset*8]}}, raw_data[offset*8 +: 8]}; // LB
                            3'b001: final_data = {{16{raw_data[15+offset[1]*16]}}, raw_data[offset[1]*16 +: 16]}; // LH
                            3'b010: final_data = raw_data; // LW
                            3'b100: final_data = {24'b0, raw_data[offset*8 +: 8]}; // LBU
                            3'b101: final_data = {16'b0, raw_data[offset[1]*16 +: 16]}; // LHU
                            default: final_data = raw_data;
                        endcase
                        
                        load_result_buffer <= final_data;
                        state <= WAIT_CDB;
                    end
                end
                
                WAIT_CDB: begin
                    arb_req <= 1;
                    arb_dest <= dest[head];
                    if (op[head] == `ALU_OP_LOAD) begin
                        arb_val <= load_result_buffer;
                    end else begin
                        arb_val <= 0; // Store returns nothing, just validation
                        // Or maybe addr?
                    end
                    
                    if (arb_allow) begin // Arbiter Granted
                        // Move Head
                        head <= (head == SIZE-1) ? 0 : head + 1;
                        state <= IDLE;
                    end
                end
            endcase
            
        end
    end

endmodule
