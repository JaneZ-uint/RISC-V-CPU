module multiplier (
    input wire clk,
    input wire rst,
    input wire valid_i,          // Input valid
    input wire [31:0] op1,
    input wire [31:0] op2,
    input wire [1:0] mode,       // 00: MUL, 01: MULH, 10: MULHSU, 11: MULHU
    
    output reg valid_o,          // Output valid
    output reg [31:0] result_o   // Final Result
);

    // ====================================================================
    // Stage 1: Pre-processing & Booth Encoding
    // ====================================================================
    
    // Operand Extension (Unified to 33-bit signed)
    wire op1_signed = (mode == 2'b00) || (mode == 2'b01) || (mode == 2'b10); // MUL, MULH, MULHSU treat op1 as signed
    wire op2_signed = (mode == 2'b00) || (mode == 2'b01);                   // MUL, MULH treat op2 as signed
    
    wire [32:0] a_ext = { op1_signed & op1[31], op1 };
    wire [32:0] b_ext = { op2_signed & op2[31], op2 };

    wire [34:0] b_scan = {b_ext[32], b_ext, 1'b0};

    
    reg [65:0] pp [0:16];
    reg [16:0] neg; // carry bits for "negative" operation (+1)

    integer i;
    reg [2:0] code;
    reg [65:0] term;
    
    always @(*) begin
        for (i=0; i<17; i=i+1) begin
            code = b_scan[2*i +: 3];
            
            // Default 0
            term = 66'd0;
            neg[i] = 1'b0;

            case (code)
                3'b000: term = 66'd0;                // 0
                3'b001: term = { {33{a_ext[32]}}, a_ext }; // +A
                3'b010: term = { {33{a_ext[32]}}, a_ext }; // +A
                3'b011: term = { {32{a_ext[32]}}, a_ext, 1'b0 }; // +2A
                3'b100: begin term = ~{ {32{a_ext[32]}}, a_ext, 1'b0 }; neg[i] = 1'b1; end // -2A
                3'b101: begin term = ~{ {33{a_ext[32]}}, a_ext }; neg[i] = 1'b1; end // -A
                3'b110: begin term = ~{ {33{a_ext[32]}}, a_ext }; neg[i] = 1'b1; end // -A
                3'b111: term = 66'd0;                // 0
            endcase

            pp[i] = term << (2*i);
        end
    end

    // Pipeline Register 1
    reg [65:0] s1_pp [0:16];
    reg [16:0] s1_neg;
    reg [1:0]  s1_mode;
    reg        s1_valid;

    always @(posedge clk) begin
        if (rst) begin
            s1_valid <= 1'b0;
        end else begin
            s1_valid <= valid_i;
            s1_mode <= mode;
            for(i=0; i<17; i=i+1) s1_pp[i] <= pp[i];
            s1_neg <= neg;
        end
    end

    // ====================================================================
    // Stage 2: Wallace Tree Compression (Layer 1 & 2)
    // ====================================================================
    
    // CSA Unit
    function [65:0] csa_sum;
        input [65:0] x, y, z;
        begin
            csa_sum = x ^ y ^ z;
        end
    endfunction

    function [65:0] csa_carry;
        input [65:0] x, y, z;
        begin
            csa_carry = (x & y) | (y & z) | (z & x);
        end
    endfunction

    // Layer 1: 17 PPs -> Group of 3
    // Group 0: 0,1,2
    // Group 1: 3,4,5
    // Group 2: 6,7,8
    // Group 3: 9,10,11
    // Group 4: 12,13,14
    // Group 5: 15,16, neg_vector (constructed from s1_neg)

    reg [65:0] l1_sum [0:5];
    reg [65:0] l1_carry [0:5];
    
    // Construct neg vector: bit 0 is neg[0], bit 2 is neg[1]... bit 2*i is neg[i]
    reg [65:0] neg_vec;
    integer j;
    always @(*) begin
        neg_vec = 66'd0;
        for(j=0; j<17; j=j+1) neg_vec[2*j] = s1_neg[j];
    end

    always @(*) begin
        // G0
        l1_sum[0]   = csa_sum(s1_pp[0], s1_pp[1], s1_pp[2]);
        l1_carry[0] = csa_carry(s1_pp[0], s1_pp[1], s1_pp[2]) << 1;
        // G1
        l1_sum[1]   = csa_sum(s1_pp[3], s1_pp[4], s1_pp[5]);
        l1_carry[1] = csa_carry(s1_pp[3], s1_pp[4], s1_pp[5]) << 1;
        // G2
        l1_sum[2]   = csa_sum(s1_pp[6], s1_pp[7], s1_pp[8]);
        l1_carry[2] = csa_carry(s1_pp[6], s1_pp[7], s1_pp[8]) << 1;
        // G3
        l1_sum[3]   = csa_sum(s1_pp[9], s1_pp[10], s1_pp[11]);
        l1_carry[3] = csa_carry(s1_pp[9], s1_pp[10], s1_pp[11]) << 1;
        // G4
        l1_sum[4]   = csa_sum(s1_pp[12], s1_pp[13], s1_pp[14]);
        l1_carry[4] = csa_carry(s1_pp[12], s1_pp[13], s1_pp[14]) << 1;
        // G5 (15, 16, neg_vec)
        l1_sum[5]   = csa_sum(s1_pp[15], s1_pp[16], neg_vec);
        l1_carry[5] = csa_carry(s1_pp[15], s1_pp[16], neg_vec) << 1;
    end

    // Pipeline Register 2
    reg [65:0] s2_sum [0:5];
    reg [65:0] s2_carry [0:5];
    reg [1:0]  s2_mode;
    reg        s2_valid;

    always @(posedge clk) begin
        if (rst) begin
            s2_valid <= 1'b0;
        end else begin
            s2_valid <= s1_valid;
            s2_mode  <= s1_mode;
            for(i=0; i<6; i=i+1) begin
                s2_sum[i]   <= l1_sum[i];
                s2_carry[i] <= l1_carry[i];
            end
        end
    end

    // ====================================================================
    // Stage 3: Wallace Tree Compression (Layer 2, 3, 4 -> Final Two)
    // ====================================================================
    
    // Input: 12 vectors (6 sums, 6 carries)
    // Layer 2: 4 groups of 3
    reg [65:0] l2_sum [0:3];
    reg [65:0] l2_carry [0:3];

    always @(*) begin
        l2_sum[0]   = csa_sum(s2_sum[0], s2_carry[0], s2_sum[1]);
        l2_carry[0] = csa_carry(s2_sum[0], s2_carry[0], s2_sum[1]) << 1;
        
        l2_sum[1]   = csa_sum(s2_carry[1], s2_sum[2], s2_carry[2]);
        l2_carry[1] = csa_carry(s2_carry[1], s2_sum[2], s2_carry[2]) << 1;

        l2_sum[2]   = csa_sum(s2_sum[3], s2_carry[3], s2_sum[4]);
        l2_carry[2] = csa_carry(s2_sum[3], s2_carry[3], s2_sum[4]) << 1;

        l2_sum[3]   = csa_sum(s2_carry[4], s2_sum[5], s2_carry[5]);
        l2_carry[3] = csa_carry(s2_carry[4], s2_sum[5], s2_carry[5]) << 1;
    end
    
    // Layer 3: 8 inputs -> Compress to ...
    // Inputs: l2_sum[0..3], l2_carry[0..3]
    reg [65:0] l3_sum [0:1], l3_carry[0:1];
    reg [65:0] l3_remain_sum, l3_remain_carry;

    always @(*) begin
        l3_sum[0]   = csa_sum(l2_sum[0], l2_carry[0], l2_sum[1]);
        l3_carry[0] = csa_carry(l2_sum[0], l2_carry[0], l2_sum[1]) << 1;
        
        l3_sum[1]   = csa_sum(l2_carry[1], l2_sum[2], l2_carry[2]);
        l3_carry[1] = csa_carry(l2_carry[1], l2_sum[2], l2_carry[2]) << 1;
        
        l3_remain_sum = l2_sum[3];
        l3_remain_carry = l2_carry[3];
    end
    
    // Layer 4: 6 inputs -> 2 outputs + ...
    reg [65:0] l4_sum [0:1], l4_carry[0:1];
    
    always @(*) begin
        l4_sum[0] = csa_sum(l3_sum[0], l3_carry[0], l3_sum[1]);
        l4_carry[0] = csa_carry(l3_sum[0], l3_carry[0], l3_sum[1]) << 1;
        
        l4_sum[1] = csa_sum(l3_carry[1], l3_remain_sum, l3_remain_carry);
        l4_carry[1] = csa_carry(l3_carry[1], l3_remain_sum, l3_remain_carry) << 1;
    end
    
    // Layer 5 (Final compression): 4 inputs -> 2 final vectors
    reg [65:0] final_vec_a, final_vec_b;
    reg [65:0] l5_sum, l5_carry;

    always @(*) begin
       l5_sum = csa_sum(l4_sum[0], l4_carry[0], l4_sum[1]);
       l5_carry = csa_carry(l4_sum[0], l4_carry[0], l4_sum[1]) << 1;
       
       // Remaining: l4_carry[1]
       // Final CS
       final_vec_a = csa_sum(l5_sum, l5_carry, l4_carry[1]);
       final_vec_b = csa_carry(l5_sum, l5_carry, l4_carry[1]) << 1;
    end

    // Pipeline Register 3
    reg [65:0] s3_a, s3_b;
    reg [1:0]  s3_mode;
    reg        s3_valid;

    always @(posedge clk) begin
        if (rst) begin
            s3_valid <= 1'b0;
        end else begin
            s3_valid <= s2_valid;
            s3_mode  <= s2_mode;
            s3_a     <= final_vec_a;
            s3_b     <= final_vec_b;
        end
    end

    // ====================================================================
    // Stage 4: Final Adder & Result Selection
    // ====================================================================
    
    wire [65:0] final_sum = s3_a + s3_b; // Standard adder (synthesizer will map to fast adder)

    always @(posedge clk) begin
        if (rst) begin
            valid_o <= 1'b0;
            result_o <= 32'b0;
        end else begin
            valid_o <= s3_valid;
            if (s3_mode == 2'b00) begin // MUL
                result_o <= final_sum[31:0];
            end else begin              // MULH*
                result_o <= final_sum[63:32];
            end
        end
    end

endmodule
