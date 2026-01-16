`include "defines.v"
`include "params.v"

module alu_common(
    input wire clk,
    input wire rst,
    
    // Input from RS (Execution)
    input wire valid_i,
    input wire [`AluOpBus] op_i,
    input wire [`RegBus] vj_i,
    input wire [`RegBus] vk_i,
    input wire [`RegBus] imm_i,
    input wire [`InstAddrBus] pc_i,
    input wire [`ROB_ID_WIDTH-1:0] dest_i,
    input wire [`InstAddrBus] pred_target_i,
    
    // Output to CDB Arbiter
    output reg valid_o, // Request CDB
    output reg [`ROB_ID_WIDTH-1:0] rob_id_o,
    output reg [`RegBus] value_o,
    output reg [`InstAddrBus] target_addr_o, 
    output reg branch_outcome_o,             // 1=Taken
    
    input wire cdb_grant_i // Arbiter grants access
);

    reg [`RegBus] result;
    reg [`InstAddrBus] target;
    reg taken;
    
    always @(*) begin
        result = 0;
        target = 0;
        taken = 0;
        
        case (op_i) // 5-bit opcode
            // Arithmetic
            `ALU_OP_ADD: result = vj_i + vk_i;
            `ALU_OP_SUB: result = vj_i - vk_i;
            `ALU_OP_SLL: result = vj_i << vk_i[4:0];
            `ALU_OP_SRL: result = vj_i >> vk_i[4:0];
            `ALU_OP_SRA: result = $signed(vj_i) >>> vk_i[4:0];
            `ALU_OP_OR:  result = vj_i | vk_i;
            `ALU_OP_AND: result = vj_i & vk_i;
            `ALU_OP_XOR: result = vj_i ^ vk_i;
            `ALU_OP_SLT: result = ($signed(vj_i) < $signed(vk_i)) ? 1 : 0;
            `ALU_OP_SLTU: result = (vj_i < vk_i) ? 1 : 0;
            `ALU_OP_LUI: result = vk_i; // Vk contains Imm
            
            // Link / Jump
            `ALU_OP_JAL: begin
                result = pc_i + 4; // Return Address
                target = vj_i + vk_i; // Target Address
                taken = 1;
            end
            
            // Branches - Compare Vj and Vk
            `ALU_OP_BEQ:  begin taken = (vj_i == vk_i); target = pc_i + imm_i; end
            `ALU_OP_BNE:  begin taken = (vj_i != vk_i); target = pc_i + imm_i; end
            `ALU_OP_BLT:  begin taken = ($signed(vj_i) < $signed(vk_i)); target = pc_i + imm_i; end
            `ALU_OP_BGE:  begin taken = ($signed(vj_i) >= $signed(vk_i)); target = pc_i + imm_i; end
            `ALU_OP_BLTU: begin taken = (vj_i < vk_i); target = pc_i + imm_i; end
            `ALU_OP_BGEU: begin taken = (vj_i >= vk_i); target = pc_i + imm_i; end
            default: ;
        endcase
    end
    
    // Output Logic
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            valid_o <= 0;
            rob_id_o <= 0;
            value_o <= 0;
            target_addr_o <= 0;
            branch_outcome_o <= 0;
        end else begin
            if (valid_i) begin
                valid_o <= 1;
                rob_id_o <= dest_i;
                value_o <= result;
                target_addr_o <= target;
                branch_outcome_o <= taken;
            end else if (valid_o && cdb_grant_i) begin
                 // We broadcasted successfully.
                 valid_o <= 0;
            end
        end
    end

endmodule
