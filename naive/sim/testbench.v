`timescale 1ns / 1ps
`include "defines.v"

module testbench;

    reg clk;
    reg rst;
    
    // Instruction Memory
    reg [`InstBus] inst_mem [0:1023];
    wire [`InstAddrBus] inst_addr;
    wire inst_ce;
    reg [`InstBus] inst_i;
    
    // Data Memory
    reg [`DataBus] data_mem [0:1023];
    wire [`DataBus] mem_addr;
    wire [`DataBus] mem_data_o;
    wire mem_we;
    wire mem_ce;
    wire [3:0] mem_sel;
    reg [`DataBus] mem_data_i;

    naive_cpu u_naive_cpu(
        .clk(clk),
        .rst(rst),
        
        .inst_i(inst_i),
        .inst_addr_o(inst_addr),
        .inst_ce_o(inst_ce),
        
        .mem_data_i(mem_data_i),
        .mem_addr_o(mem_addr),
        .mem_data_o(mem_data_o),
        .mem_we_o(mem_we),
        .mem_ce_o(mem_ce),
        .mem_sel_o(mem_sel)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = `RstEnable;
        #20;
        rst = `RstDisable;
        #5000000; // Increased timeout
        $display("Timeout!");
        $finish;
    end

    initial begin
        $readmemh("naive/sim/inst_rom.data", inst_mem);
        // Initialize data memory to 0
        for (integer i = 0; i < 1024; i = i + 1) begin
            data_mem[i] = 0;
        end
    end
    
    // Instruction Fetch Logic
    always @(*) begin
        if (inst_ce == `ReadEnable) begin
            inst_i = inst_mem[inst_addr[11:2]]; 
        end else begin
            inst_i = `ZeroWord;
        end
    end
    
    // Data Memory Logic
    always @(posedge clk) begin
        if (mem_ce == `ReadEnable && mem_we == `WriteEnable) begin
            data_mem[mem_addr[11:2]] <= mem_data_o;
        end
    end
    
    always @(*) begin
        if (mem_ce == `ReadEnable && mem_we == `WriteDisable) begin
            mem_data_i = data_mem[mem_addr[11:2]];
        end else begin
            mem_data_i = `ZeroWord;
        end
    end

    initial begin
        $dumpfile("naive_cpu.vcd");
        $dumpvars(0, testbench);
    end

    // Monitor
    always @(posedge clk) begin
        if (rst == `RstDisable) begin
             $display("Time: %t, PC: %h, Inst: %h, x1: %d, x2: %d, x3: %d", $time, u_naive_cpu.pc, u_naive_cpu.u_id_stage.inst_i, u_naive_cpu.u_regfile.regs[1], u_naive_cpu.u_regfile.regs[2], u_naive_cpu.u_regfile.regs[3]);
        end

        if (u_naive_cpu.u_id_stage.inst_i == 32'h00000073) begin // ECALL
            $display("ECALL encountered at time %t", $time);
            $display("Result in x1: %d", u_naive_cpu.u_regfile.regs[1]);
            $finish;
        end
    end

endmodule
