`include "defines.v"
`include "params.v"

module load_store_buffer #(
    parameter SIZE = 8
)(
    input wire clk,
    input wire rst,
    input wire flush,
    
    // Dispatch (from Issue Unit)
    input wire we,
    input wire [`AluOpBus] op,
    input wire [2:0] sub_op,
    input wire [`RegBus] vj,
    input wire [`ROB_ID_WIDTH-1:0] qj,
    input wire qj_valid, // 1 if waiting for ROB
    input wire [`RegBus] vk,
    input wire [`ROB_ID_WIDTH-1:0] qk,
    input wire qk_valid, // 1 if waiting for ROB
    input wire [`ROB_ID_WIDTH-1:0] dest, 
    input wire [`RegBus] imm, 
    input wire [`InstAddrBus] pc, 
    
    output wire full,
    
    // CDB Snoop
    input wire cdb_valid,
    input wire [`ROB_ID_WIDTH-1:0] cdb_rob_id,
    input wire [`RegBus] cdb_value,
    
    // Memory Interface
    input wire mem_ready,
    input wire [`RegBus] mem_data, 
    output reg mem_req,
    output reg mem_we,
    output reg [`RegBus] mem_addr,
    output reg [`RegBus] mem_wdata,
    output reg [3:0] mem_mask,
    
    // Commit/Writeback to ROB (via CDB or dedicated path?)
    // Here we assume LSB writes to CDB
    input wire cdb_grant,
    input wire [`ROB_ID_WIDTH-1:0] rob_head,
    output reg lsb_out_valid,
    output reg [`ROB_ID_WIDTH-1:0] lsb_out_rob_id,
    output reg [`RegBus] lsb_out_value
);

    // FIFO pointers
    reg [$clog2(SIZE)-1:0] head;
    reg [$clog2(SIZE)-1:0] tail;
    reg [SIZE-1:0] valid; // Occupied slots
    
    wire empty = (valid == 0);
    // wire full = (valid == {SIZE{1'b1}}); // Simple check if all 1s
    // Better full Check: if tail+1 == head (modulo)
    // Actually using a counter or simplified valid check is easier.
    // Let's use count.
    reg [$clog2(SIZE):0] count;
    assign full = (count == SIZE);
    
    // Storage
    reg [`AluOpBus] op_buf [SIZE-1:0];
    reg [2:0] sub_op_buf [SIZE-1:0];
    reg [`RegBus] vj_buf [SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] qj_buf [SIZE-1:0];
    reg [SIZE-1:0] qj_valid_buf;
    reg [`RegBus] vk_buf [SIZE-1:0];
    reg [`ROB_ID_WIDTH-1:0] qk_buf [SIZE-1:0];
    reg [SIZE-1:0] qk_valid_buf;
    reg [`ROB_ID_WIDTH-1:0] dest_buf [SIZE-1:0];
    reg [`RegBus] imm_buf [SIZE-1:0];
    // pc not strictly needed for execution unless exception
    
    // State machine for head execution
    localparam IDLE = 0;
    localparam WAIT_MEM = 1;
    localparam WAIT_CDB = 2;
    reg [1:0] state;
    
    reg [31:0] load_result;
    
    // Pre-calculate head address and store value
    wire [31:0] head_addr = vj_buf[head] + imm_buf[head];
    wire [31:0] head_store_val = vk_buf[head];
    
    // Wires for temp usage in combinational logic
    reg [31:0] raw_data;
    reg [31:0] final_data;

    integer i;

    wire push = we && !full;
    wire pop = ((state == WAIT_MEM) && mem_ready && (op_buf[head] != `ALU_OP_LOAD)) ||
               ((state == WAIT_CDB) && cdb_grant);

    always @(posedge clk) begin
        if (rst || flush) begin // Flush clears LSB? Usually LSB holds instructions until commit or squash.
                                // If branch mispredict, we must flush speculative insts.
                                // For now, assume flush kills everything.
            head <= 0;
            tail <= 0;
            count <= 0;
            valid <= 0;
            state <= IDLE;
            mem_req <= 0;
            lsb_out_valid <= 0;
            mem_we <= 0;
        end else begin
            // Count Update
            if (push && !pop) count <= count + 1;
            else if (!push && pop) count <= count - 1;

            // Dispatch
            if (push) begin
                op_buf[tail] <= op;
                sub_op_buf[tail] <= sub_op;
                dest_buf[tail] <= dest;
                imm_buf[tail] <= imm;
                
                // Operand 1
                if (qj_valid) begin // Waiting
                    if (cdb_valid && cdb_rob_id == qj) begin
                        vj_buf[tail] <= cdb_value;
                        qj_valid_buf[tail] <= 0;
                    end else begin
                        qj_buf[tail] <= qj;
                        qj_valid_buf[tail] <= 1;
                    end
                end else begin
                    vj_buf[tail] <= vj;
                    qj_valid_buf[tail] <= 0;
                end
                
                // Operand 2
                if (qk_valid) begin // Waiting
                    if (cdb_valid && cdb_rob_id == qk) begin
                        vk_buf[tail] <= cdb_value;
                        qk_valid_buf[tail] <= 0;
                    end else begin
                        qk_buf[tail] <= qk;
                        qk_valid_buf[tail] <= 1;
                    end
                end else begin
                    vk_buf[tail] <= vk;
                    qk_valid_buf[tail] <= 0;
                end
                
                valid[tail] <= 1;
                tail <= (tail + 1) % SIZE;
            end
            
            // CDB Snoop (Update waiting operands)
            if (cdb_valid) begin
                for (i = 0; i < SIZE; i = i + 1) begin
                    if (valid[i]) begin
                        if (qj_valid_buf[i] && qj_buf[i] == cdb_rob_id) begin
                            vj_buf[i] <= cdb_value;
                            qj_valid_buf[i] <= 0;
                        end
                        if (qk_valid_buf[i] && qk_buf[i] == cdb_rob_id) begin
                            vk_buf[i] <= cdb_value;
                            qk_valid_buf[i] <= 0;
                        end
                    end
                end
            end

            // --- Execute Head ---
            // Unless we just dispatched and updated count, we might need to be careful.
            // But we use non-blocking assignments.
            
            // Default inactive
            // mem_req <= 0; // Don't clear request if we are waiting
            // lsb_out_valid <= 0; // Don't clear if waiting for CDB grant
            
            case (state)
                IDLE: begin
                    lsb_out_valid <= 0;
                    mem_req <= 0;
                    if (count > 0) begin // Head is valid
                         // Wait for operands
                        if (!qj_valid_buf[head]) begin
                            if (op_buf[head] == `ALU_OP_LOAD) begin
                                // LOAD
                                // Use pre-calculated head_addr
                                mem_addr <= head_addr;
                                mem_we <= 0;
                                mem_req <= 1;
                                state <= WAIT_MEM; 
                                
                            end else if (op_buf[head] == `ALU_OP_STORE && dest_buf[head] == rob_head) begin
                                // STORE
                                if (!qk_valid_buf[head]) begin
                                    mem_addr <= head_addr;
                                    mem_we <= 1;
                                    mem_wdata <= head_store_val;
                                    
                                    case (sub_op_buf[head])
                                        3'b000: mem_mask <= 4'b0001 << head_addr[1:0]; // SB
                                        3'b001: mem_mask <= 4'b0011 << head_addr[1:0]; // SH
                                        3'b010: mem_mask <= 4'b1111;              // SW
                                        default: mem_mask <= 4'b1111;
                                    endcase
                                    
                                    mem_req <= 1;
                                    state <= WAIT_MEM;
                                end
                            end
                        end
                    end
                end
                
                WAIT_MEM: begin
                    if (mem_ready) begin
                        mem_req <= 0;
                        if (op_buf[head] == `ALU_OP_LOAD) begin
                            raw_data = mem_data;
                            final_data = 0;
                            case (sub_op_buf[head]) // funct3
                                3'b000: final_data = {{24{raw_data[7]}}, raw_data[7:0]}; // LB
                                3'b001: final_data = {{16{raw_data[15]}}, raw_data[15:0]}; // LH
                                3'b010: final_data = raw_data; // LW
                                3'b100: final_data = {24'b0, raw_data[7:0]}; // LBU
                                3'b101: final_data = {16'b0, raw_data[15:0]}; // LHU
                                default: final_data = raw_data;
                            endcase
                            load_result <= final_data;
                            state <= WAIT_CDB;
                        end else begin
                            // Store done
                            // We can retire this instruction from LSB (Store does not write to CDB usually, 
                            // but for ROB to commit, it needs notification. 
                            // In this design, does ROB wait for Store completion signals?
                            // Yes, ROB commits upon completion.
                            // We should broadcast 'value' (maybe 0 or address?) to CDB/ROB
                            // or just signal completion.
                            
                            // Let's send completion. Value doesn't matter for store?
                            lsb_out_valid <= 1;
                            lsb_out_rob_id <= dest_buf[head];
                            lsb_out_value <= 0; // No register update
                            
                            // Done
                            valid[head] <= 0;
                            head <= (head + 1) % SIZE;
                            state <= IDLE;
                        end
                    end
                end
                
                WAIT_CDB: begin
                    // LOAD only
                    lsb_out_valid <= 1;
                    lsb_out_rob_id <= dest_buf[head];
                    lsb_out_value <= load_result;
                    
                    if (cdb_grant) begin
                        lsb_out_valid <= 0; 
                        valid[head] <= 0;
                        head <= (head + 1) % SIZE;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end


    always @(posedge clk) begin
         if (we && full) $display("LSB DROP! Time=%t", $time);
         // $display("LSB State: count=%d head=%d tail=%d full=%b push=%b pop=%b Time=%t", count, head, tail, full, push, pop, $time);
    end
    always @(posedge clk) begin 
         if (mem_req && mem_ready) begin 
             if (mem_we) 
                 $display("[LSB] STORE COMPL: Time=%0t, Addr=%h, Data=%h, Mask=%b", $time, mem_addr, mem_wdata, mem_mask); 
             else 
                 $display("[LSB] LOAD COMPL: Time=%0t, Addr=%h, Data=%h (Raw)", $time, mem_addr, mem_data); 
         end 
    end
endmodule

