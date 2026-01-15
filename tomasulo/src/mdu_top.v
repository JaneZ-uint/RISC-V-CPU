`include "defines.v"
`include "params.v"

module mdu_top (
    input wire clk,
    input wire rst,
    input wire flush,
    
    // Issue Interface
    input wire start_i,           // Request valid
    input wire [4:0] op_i,        // ALU Opcode (M-Ext)
    input wire [31:0] rs1_i, 
    input wire [31:0] rs2_i,
    input wire [`ROB_ID_WIDTH-1:0] rob_id_i,    // Input Tag
    
    // Handshake
    output wire ready_o,          // 1=Ready, 0=Busy
    
    // CDB Interface
    output wire done_o,            // Request CDB
    output wire [31:0] result_o,   // Result
    output wire [`ROB_ID_WIDTH-1:0] rob_id_o,     // Output Tag
    input wire cdb_grant_i         // CDB Granted
);

    // Decode Operation (ALU Op -> Funct3)
    reg [2:0] sub_op;
    always @(*) begin
        case(op_i)
            `ALU_OP_MUL:    sub_op = 3'b000;
            `ALU_OP_MULH:   sub_op = 3'b001;
            `ALU_OP_MULHSU: sub_op = 3'b010;
            `ALU_OP_MULHU:  sub_op = 3'b011;
            `ALU_OP_DIV:    sub_op = 3'b100;
            `ALU_OP_DIVU:   sub_op = 3'b101;
            `ALU_OP_REM:    sub_op = 3'b110;
            `ALU_OP_REMU:   sub_op = 3'b111;
            default:        sub_op = 3'b000;
        endcase
    end

    wire is_mul = ~sub_op[2]; // 0xx
    wire is_div = sub_op[2];  // 1xx

    // ---------------------------------------------------------------
    // Multiplier Instantiation
    // ---------------------------------------------------------------
    wire mul_start = start_i && is_mul && !flush;
    wire mul_valid_out;
    wire [31:0] mul_result;
    
    // Multiplier Pipeline Tag Propagation (Latency = 4)
    reg [`ROB_ID_WIDTH-1:0] mul_tag_p1, mul_tag_p2, mul_tag_p3, mul_tag_p4;
    reg       mul_val_p1, mul_val_p2, mul_val_p3; 
    
    always @(posedge clk) begin
        if (rst || flush) begin
            mul_tag_p1 <= 0; mul_tag_p2 <= 0; mul_tag_p3 <= 0; mul_tag_p4 <= 0;
            mul_val_p1 <= 0; mul_val_p2 <= 0; mul_val_p3 <= 0;
        end else begin
            // Shift Register for Tags
            mul_tag_p1 <= rob_id_i;
            mul_tag_p2 <= mul_tag_p1;
            mul_tag_p3 <= mul_tag_p2;
            mul_tag_p4 <= mul_tag_p3;
            
            // Valid bits
            mul_val_p1 <= mul_start;
            mul_val_p2 <= mul_val_p1;
            mul_val_p3 <= mul_val_p2;
        end
    end

    multiplier u_multiplier (
        .clk(clk),
        .rst(rst || flush), 
        .valid_i(mul_start),
        .op1(rs1_i),
        .op2(rs2_i),
        .mode(sub_op[1:0]),
        .valid_o(mul_valid_out),
        .result_o(mul_result)
    );


    // ---------------------------------------------------------------
    // Divider Instantiation
    // ---------------------------------------------------------------
    wire div_start = start_i && is_div && !flush;
    wire div_ready;
    wire div_valid_out;
    wire [31:0] div_result;
    
    reg [`ROB_ID_WIDTH-1:0] div_tag_reg;
    reg       div_active;

    always @(posedge clk) begin
        if (rst || flush) begin
            div_active <= 0;
            div_tag_reg <= 0;
        end else begin
            if (div_start && div_ready) begin
                div_tag_reg <= rob_id_i;
                div_active <= 1'b1;
            end else if (div_valid_out) begin
                div_active <= 1'b0;
            end
        end
    end

    divider u_divider (
        .clk(clk),
        .rst(rst || flush), 
        .start_i(div_start),
        .sub_op(sub_op),
        .op1(rs1_i),
        .op2(rs2_i),
        .ready_o(div_ready),
        .valid_o(div_valid_out),
        .result_o(div_result)
    );

    // ---------------------------------------------------------------
    // Output Arbitration & Muxing
    // ---------------------------------------------------------------
    
    assign ready_o = div_ready; // Simplified backpressure

    reg [31:0] buf_result;
    reg [`ROB_ID_WIDTH-1:0]  buf_tag;
    reg        buf_valid;

    always @(posedge clk) begin
        if (rst || flush) begin
             buf_valid <= 0;
             buf_result <= 0;
             buf_tag <= 0;
        end else begin
             if (div_valid_out) begin
                 buf_result <= div_result;
                 buf_tag <= div_tag_reg;
                 buf_valid <= 1;
             end else if (mul_valid_out) begin
                 buf_result <= mul_result;
                 buf_tag <= mul_tag_p4;
                 buf_valid <= 1;
             end else if (buf_valid && cdb_grant_i) begin
                 buf_valid <= 0;
             end
        end
    end
    
    assign result_o = buf_result;
    assign rob_id_o = buf_tag;
    assign done_o = buf_valid;

endmodule
