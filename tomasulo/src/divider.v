/*
 * Iterative Divider for RISC-V M-Extension
 * Implementation: Radix-2 Non-Restoring Division
 * Latency: 34 Cycles (approx)
 */
module divider (
    input wire clk,
    input wire rst,
    input wire start_i,
    input wire [2:0] sub_op,     // 100:DIV, 101:DIVU, 110:REM, 111:REMU
    input wire [31:0] op1,
    input wire [31:0] op2,

    output reg ready_o,          // Can accept new instruction
    output reg valid_o,          // Result valid
    output reg [31:0] result_o
);

    // States
    localparam IDLE  = 3'd0;
    localparam INIT  = 3'd1;
    localparam CALC  = 3'd2; // Iteration
    localparam FIX   = 3'd3; // Correction
    localparam DONE  = 3'd4;

    reg [2:0] state, next_state;
    reg [5:0] count;

    // Data Registers
    // [64:32] = Remainder (33 bits), [31:0] = Quotient (32 bits)
    reg [64:0] reg_rem_quo; 
    reg [32:0] reg_div;     // Divisor (extended)
    
    // Control Registers
    reg is_signed_div;
    reg op1_sign, op2_sign;
    reg is_rem;
    reg div_by_zero;
    reg overflow;

    // Decode Op
    wire is_div   = (sub_op == 3'b100);
    wire is_divu  = (sub_op == 3'b101);
    wire is_rem_op = (sub_op == 3'b110);
    wire is_remu  = (sub_op == 3'b111);
    wire signed_op = is_div || is_rem_op;

    // ---------------------------------------------
    // Datapath Components
    // ---------------------------------------------
    
    // Absolute values
    wire [31:0] abs_op1 = (signed_op && op1[31]) ? -op1 : op1;
    wire [31:0] abs_op2 = (signed_op && op2[31]) ? -op2 : op2;
    
    // Iteration Logic (Radix-2 Non-Restoring)
    // Partial Remainder is reg_rem_quo[64:32]
    // Shifted Remainder = {R[32:0], Q[31]}
    wire [33:0] rem_tmp = {reg_rem_quo[64:32], reg_rem_quo[31]};
    
    // ALU Operation
    // reg_div is 33 bits. Extend to 34 bits.
    wire [33:0] div_ext = {1'b0, reg_div};
    
    // If sign bit (64) is 1 (negative), ADD. Else SUB.
    wire [33:0] alu_out = reg_rem_quo[64] ? (rem_tmp + div_ext) : (rem_tmp - div_ext);
    
    // If alu_out is negative (MSB=1), q_bit is 0. Else 1.
    wire q_bit = ~alu_out[33];


    // ---------------------------------------------
    // State Machine
    // ---------------------------------------------
    
    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (start_i) next_state = INIT;
            INIT: next_state = CALC;
            CALC: if (count == 6'd31) next_state = FIX;
            FIX:  next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end

    // ---------------------------------------------
    // Logic
    // ---------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            ready_o <= 1'b1;
            valid_o <= 1'b0;
            result_o <= 32'b0;
            count <= 0;
            reg_rem_quo <= 0;
            reg_div <= 0;
            is_signed_div <= 0;
            op1_sign <= 0;
            op2_sign <= 0;
            is_rem <= 0;
            div_by_zero <= 0;
            overflow <= 0;
        end else begin
            case (state)
                IDLE: begin
                    valid_o <= 1'b0;
                    if (start_i) begin
                        ready_o <= 1'b0;
                        is_signed_div <= signed_op;
                        is_rem <= is_rem_op || is_remu;
                        
                        // Check Corner Cases
                        if (op2 == 0) div_by_zero <= 1'b1;
                        else div_by_zero <= 1'b0;

                        // Check Overflow: -2^31 / -1
                        if (signed_op && (op1 == 32'h80000000) && (op2 == 32'hFFFFFFFF)) 
                            overflow <= 1'b1;
                        else
                            overflow <= 1'b0;
                        
                        op1_sign <= op1[31];
                        op2_sign <= op2[31];
                    end else begin
                        ready_o <= 1'b1;
                    end
                end

                INIT: begin
                    // Load absolute values
                    // R=0 (33 bits), Q=abs_op1 (32 bits)
                    reg_rem_quo <= {33'b0, abs_op1};
                    reg_div <= {1'b0, abs_op2};
                    count <= 0;
                end

                CALC: begin
                    count <= count + 1;
                    // Update Remainder with ALU result (33 bits stored in [64:32])
                    reg_rem_quo[64:32] <= alu_out[32:0];
                    // Shift Quotient and Shift in q_bit
                    reg_rem_quo[31:1] <= reg_rem_quo[30:0];
                    reg_rem_quo[0] <= q_bit;
                end

                FIX: begin
                    // Correction step for Non-Restoring
                    // If Remainder is negative, add Divisor
                    if (reg_rem_quo[64]) begin
                        reg_rem_quo[64:32] <= reg_rem_quo[64:32] + reg_div;
                    end
                end

                DONE: begin
                    valid_o <= 1'b1;
                    ready_o <= 1'b1;

                    if (div_by_zero) begin
                        if (is_rem) result_o <= op1; // REM by 0 = op1
                        else result_o <= 32'hFFFFFFFF; // DIV by 0 = -1
                    end else if (overflow) begin
                        if (is_rem) result_o <= 32'b0;
                        else result_o <= 32'h80000000;
                    end else begin
                        // Normal Result
                        if (is_rem) begin
                            // Remainder Sign Rule: matches Dividend (op1)
                            if (is_signed_div && op1_sign)
                                result_o <= -reg_rem_quo[63:32];
                            else
                                result_o <= reg_rem_quo[63:32];
                        end else begin
                            // Quotient Sign Rule: op1_sign ^ op2_sign
                            if (is_signed_div && (op1_sign ^ op2_sign))
                                result_o <= -reg_rem_quo[31:0];
                            else
                                result_o <= reg_rem_quo[31:0];
                        end
                    end
                end
            endcase
        end
    end

endmodule
