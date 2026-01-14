`timescale 1ns / 1ps
`include "../src/defines.v"
`include "../src/params.v"

module testbench;

    reg clk;
    reg rst;
    
    // --- Memory ---
    // 256KB = 65536 words
    reg [31:0] ram [0:65535]; 
    
    // --- Interfaces ---
    wire [`InstBus] inst_i;
    wire [`InstAddrBus] inst_addr_o;
    wire inst_ce_o;
    
    wire [`DataBus] mem_data_i;
    reg mem_valid_i;
    reg mem_ready_i;
    wire [`DataBus] mem_addr_o;
    wire [`DataBus] mem_data_o;
    wire mem_we_o;
    wire mem_req_o;
    wire [3:0] mem_sel_o;

    // --- Instantiation ---
    tomasulo_cpu u_cpu(
        .clk(clk),
        .rst(rst),
        .inst_i(inst_i),
        .inst_addr_o(inst_addr_o),
        .inst_ce_o(inst_ce_o),
        .mem_data_i(mem_data_i),
        .mem_valid_i(mem_valid_i),
        .mem_ready_i(mem_ready_i),
        .mem_addr_o(mem_addr_o),
        .mem_data_o(mem_data_o),
        .mem_we_o(mem_we_o),
        .mem_req_o(mem_req_o),
        .mem_sel_o(mem_sel_o)
    );

    // --- Clock ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Utils ---
    integer i;

    // --- Memory Logic ---
    initial begin
        // Init RAM to 0
        for(i=0; i<65536; i=i+1) ram[i] = 32'b0;
        
        // Load Hex
        $readmemh("inst_rom.data", ram);
    end
    
    assign inst_i = (inst_ce_o == `ReadEnable) ? ram[inst_addr_o[31:2]] : `ZeroWord;
    
    wire [31:0] word_addr = mem_addr_o[31:2];
    assign mem_data_i = ram[word_addr]; 
    
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            mem_valid_i <= 0;
            mem_ready_i <= 0;
        end else begin
            mem_ready_i <= 1'b1;
            if (mem_req_o && !mem_we_o) begin
                mem_valid_i <= 1'b1;
            end else begin
                mem_valid_i <= 0;
            end
            
            if (mem_req_o && mem_we_o) begin
                // Check exit condition for array_test benchmarks (Write to 0x30004)
                if ({word_addr, 2'b00} == 32'h00030004) begin
                    $display("TOTAL_BRANCH: %d", u_cpu.u_rob.cnt_total_branch);
                    $display("CORRECT_BRANCH: %d", u_cpu.u_rob.cnt_correct_branch);
                    $finish;
                end

                 if (mem_sel_o == 4'b1111) begin
                      ram[word_addr] <= mem_data_o;
                 end else begin
                     if(mem_sel_o[0]) ram[word_addr][7:0]   <= mem_data_o[7:0];
                     if(mem_sel_o[1]) ram[word_addr][15:8]  <= mem_data_o[15:8];
                     if(mem_sel_o[2]) ram[word_addr][23:16] <= mem_data_o[23:16];
                     if(mem_sel_o[3]) ram[word_addr][31:24] <= mem_data_o[31:24];
                 end
            end
        end
    end

    // --- Control & Monitor ---
    initial begin
        rst = `RstEnable;
        #100;
        rst = `RstDisable;
        
        // Timeout
        #500000000;
        $display("TIMEOUT"); // Keep for safety
        $finish;
    end
    
    // Check for ECALL at Issue stage with Empty ROB to ensure completion
    always @(posedge clk) begin
         if (!u_cpu.u_issue_unit.iq_empty && 
             u_cpu.u_issue_unit.iq_inst[6:0] == 7'b1110011 && // ECALL
             u_cpu.u_rob.empty) begin
             
             // Wait one cycle to ensure stability if needed
             @(posedge clk);
             
             $display("Result in x1: %d", u_cpu.u_regfile.regs[1]);
             
             // Keep stats for benchmark script
             $display("TOTAL_BRANCH: %d", u_cpu.u_rob.cnt_total_branch);
             $display("CORRECT_BRANCH: %d", u_cpu.u_rob.cnt_correct_branch);
             $finish;
        end
    end

    initial begin
        $dumpfile("tomasulo_cpu.vcd");
        $dumpvars(0, testbench);
    end

endmodule
