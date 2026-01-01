`include "defines.v"

module mem_stage(
    input wire rst,
    
    // Inputs from EX
    input wire [`RegAddrBus] wd_i,
    input wire wreg_i,
    input wire [`DataBus] wdata_i, // ALU Result
    input wire [`DataBus] mem_addr_i,
    input wire [`DataBus] store_data_i,
    input wire [`InstBus] inst_i,
    
    // Memory Interface
    input wire [`DataBus] mem_data_i, // Read Data
    output reg [`DataBus] mem_addr_o,
    output reg [`DataBus] mem_data_o, // Write Data
    output reg mem_we_o,
    output reg mem_ce_o,
    output reg [3:0] mem_sel_o, // Byte Select
    
    // Outputs to WB
    output reg [`RegAddrBus] wd_o,
    output reg wreg_o,
    output reg [`DataBus] wdata_o
);

    wire [6:0] opcode = inst_i[6:0];
    wire [2:0] funct3 = inst_i[14:12];
    wire [1:0] addr_offset = mem_addr_i[1:0];

    always @(*) begin
        if (rst == `RstEnable) begin
            wd_o = 5'b00000;
            wreg_o = `WriteDisable;
            wdata_o = `ZeroWord;
            mem_addr_o = `ZeroWord;
            mem_data_o = `ZeroWord;
            mem_we_o = `WriteDisable;
            mem_ce_o = `ReadDisable;
            mem_sel_o = 4'b0000;
        end else begin
            wd_o = wd_i;
            wreg_o = wreg_i;
            wdata_o = wdata_i; // Default: Pass ALU result
            
            mem_addr_o = mem_addr_i;
            mem_data_o = `ZeroWord;
            mem_we_o = `WriteDisable;
            mem_ce_o = `ReadEnable; // Always enable? Or only for Load/Store?
            mem_sel_o = 4'b0000;

            case (opcode)
                `INST_LOAD: begin
                    mem_ce_o = `ReadEnable;
                    case (funct3)
                        `FUNCT3_LB: begin
                            case (addr_offset)
                                2'b00: wdata_o = {{24{mem_data_i[7]}}, mem_data_i[7:0]};
                                2'b01: wdata_o = {{24{mem_data_i[15]}}, mem_data_i[15:8]};
                                2'b10: wdata_o = {{24{mem_data_i[23]}}, mem_data_i[23:16]};
                                2'b11: wdata_o = {{24{mem_data_i[31]}}, mem_data_i[31:24]};
                            endcase
                        end
                        `FUNCT3_LBU: begin
                            case (addr_offset)
                                2'b00: wdata_o = {24'b0, mem_data_i[7:0]};
                                2'b01: wdata_o = {24'b0, mem_data_i[15:8]};
                                2'b10: wdata_o = {24'b0, mem_data_i[23:16]};
                                2'b11: wdata_o = {24'b0, mem_data_i[31:24]};
                            endcase
                        end
                        `FUNCT3_LH: begin
                            case (addr_offset)
                                2'b00: wdata_o = {{16{mem_data_i[15]}}, mem_data_i[15:0]};
                                2'b10: wdata_o = {{16{mem_data_i[31]}}, mem_data_i[31:16]};
                                default: wdata_o = `ZeroWord; // Unaligned
                            endcase
                        end
                        `FUNCT3_LHU: begin
                            case (addr_offset)
                                2'b00: wdata_o = {16'b0, mem_data_i[15:0]};
                                2'b10: wdata_o = {16'b0, mem_data_i[31:16]};
                                default: wdata_o = `ZeroWord; // Unaligned
                            endcase
                        end
                        `FUNCT3_LW: begin
                            wdata_o = mem_data_i;
                        end
                    endcase
                end
                `INST_STORE: begin
                    mem_ce_o = `ReadEnable; // Enable memory
                    mem_we_o = `WriteEnable;
                    case (funct3)
                        `FUNCT3_SB: begin
                            case (addr_offset)
                                2'b00: begin mem_sel_o = 4'b0001; mem_data_o = {24'b0, store_data_i[7:0]}; end
                                2'b01: begin mem_sel_o = 4'b0010; mem_data_o = {16'b0, store_data_i[7:0], 8'b0}; end
                                2'b10: begin mem_sel_o = 4'b0100; mem_data_o = {8'b0, store_data_i[7:0], 16'b0}; end
                                2'b11: begin mem_sel_o = 4'b1000; mem_data_o = {store_data_i[7:0], 24'b0}; end
                            endcase
                        end
                        `FUNCT3_SH: begin
                            case (addr_offset)
                                2'b00: begin mem_sel_o = 4'b0011; mem_data_o = {16'b0, store_data_i[15:0]}; end
                                2'b10: begin mem_sel_o = 4'b1100; mem_data_o = {store_data_i[15:0], 16'b0}; end
                                default: ; // Unaligned
                            endcase
                        end
                        `FUNCT3_SW: begin
                            mem_sel_o = 4'b1111;
                            mem_data_o = store_data_i;
                        end
                    endcase
                end
                default: begin
                    // Not Load/Store, just pass ALU result (wdata_i) to wdata_o
                    // mem_ce_o = `ReadDisable; // Disable memory if not needed?
                    // But we might be fetching instructions? No, this is Data Mem.
                    mem_ce_o = `ReadDisable;
                end
            endcase
        end
    end

endmodule
