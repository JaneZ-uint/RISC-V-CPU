`timescale 1ns / 1ps
`include "../src/defines.v"

module testbench;

    reg clk;
    reg rst;
    
    wire [`InstBus] inst;
    wire [`InstAddrBus] inst_addr;
    wire inst_ce;
    
    wire [`DataBus] mem_data_i;
    wire [`DataBus] mem_addr_o;
    wire [`DataBus] mem_data_o;
    wire mem_we_o;
    wire mem_ce_o;
    wire [3:0] mem_sel_o;
    
    // Instantiate CPU
    naive_cpu u_cpu(
        .clk(clk),
        .rst(rst),
        .inst_i(inst),
        .inst_addr_o(inst_addr),
        .inst_ce_o(inst_ce),
        .mem_data_i(mem_data_i),
        .mem_addr_o(mem_addr_o),
        .mem_data_o(mem_data_o),
        .mem_we_o(mem_we_o),
        .mem_ce_o(mem_ce_o),
        .mem_sel_o(mem_sel_o)
    );
    
    // Instruction Memory (ROM)
    reg [31:0] inst_mem[0:1023];
    
    initial begin
        $readmemh("inst_rom.data", inst_mem);
    end
    
    assign inst = (inst_ce == `ReadEnable) ? inst_mem[inst_addr[11:2]] : `ZeroWord;
    
    // Data Memory (RAM)
    reg [7:0] data_mem[0:4095]; // 4KB
    
    // Read Logic
    // Assume 0x80000000 base. Map to 0.
    wire [31:0] data_addr_masked = mem_addr_o & 32'h00000FFF;
    
    assign mem_data_i = (mem_ce_o == `ReadEnable) ? 
                        {data_mem[data_addr_masked+3], data_mem[data_addr_masked+2], data_mem[data_addr_masked+1], data_mem[data_addr_masked]} : 
                        `ZeroWord;
                        
    // Write Logic
    always @(posedge clk) begin
        if (mem_ce_o == `ReadEnable && mem_we_o == `WriteEnable) begin
            if (mem_sel_o[0]) data_mem[data_addr_masked]   <= mem_data_o[7:0];
            if (mem_sel_o[1]) data_mem[data_addr_masked+1] <= mem_data_o[15:8];
            if (mem_sel_o[2]) data_mem[data_addr_masked+2] <= mem_data_o[23:16];
            if (mem_sel_o[3]) data_mem[data_addr_masked+3] <= mem_data_o[31:24];
        end
    end
    
    // Clock Generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // Reset and Run
    initial begin
        rst = `RstEnable;
        #50;
        rst = `RstDisable;
        #1000;
        $finish;
    end
    
    // Dump Waveform
    initial begin
        $dumpfile("naive_cpu.vcd");
        $dumpvars(0, testbench);
    end

endmodule
