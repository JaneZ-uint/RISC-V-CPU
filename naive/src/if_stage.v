`include "defines.v"

module if_stage(
    input wire [`InstAddrBus] pc,
    input wire ce,
    input wire [`InstBus] inst_i, // From Mem
    
    output wire [`InstAddrBus] inst_addr_o,
    output wire ce_o,
    output wire [`InstBus] inst_o // To IF/ID
);

    assign inst_addr_o = pc;
    assign ce_o = ce;
    assign inst_o = inst_i;

endmodule
