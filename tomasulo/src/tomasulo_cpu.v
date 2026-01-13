`include "defines.v"
`include "params.v"

module tomasulo_cpu(
    input wire clk,
    input wire rst,
    
    // Instruction Memory Interface
    input wire [`InstBus] inst_i,
    output wire [`InstAddrBus] inst_addr_o,
    output wire inst_ce_o,
    
    // Data Memory Interface
    input wire [`DataBus] mem_data_i,
    output wire [`DataBus] mem_addr_o,
    output wire [`DataBus] mem_data_o,
    output wire mem_we_o,
    output wire mem_ce_o,
    output wire [3:0] mem_sel_o
);

    // Internal Signals (To be interconnected as modules are implemented)
    
    // PC Signals
    wire [`InstAddrBus] pc;
    wire [`InstAddrBus] next_pc;
    wire branch_taken;
    wire [`InstAddrBus] branch_target;

    assign inst_addr_o = pc;
    assign inst_ce_o = (rst == `RstDisable) ? `ReadEnable : `ReadDisable;

    // --- Module Instantiation Scope ---
    
    // 1. PC Register
    // pc_reg u_pc_reg(...);

    // 2. Fetch Unit (Instruction Queue)
    // fetch_unit u_fetch_unit(...);

    // 3. Issue Unit (Decoder & RAT)
    // issue_unit u_issue_unit(...);

    // 4. ROB
    // reorder_buffer u_rob(...);

    // 5. Reservation Stations
    // reservation_station_alu u_rs_alu(...);

    // 6. ALU Units
    // alu_common u_alu(...);

    // 7. CDB Arbiter
    // cdb_arbiter u_cdb(...);

    // 8. Register File
    // regfile u_regfile(...);

endmodule
