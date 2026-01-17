`timescale 1ns / 1ps
`include "../src/defines.v"
`include "../src/params.v"

module testbench;

    reg clk;
    reg rst;
    
    // --- Memory ---
    // 256KB = 262144 bytes
    // Changed to 8-bit width to support standard GCC/Objcopy Verilog Hex format
    reg [7:0] ram [0:262143]; 
    
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

    // --- Benchmark Spy Logic ---
    reg [31:0] benchmark_result;
    reg benchmark_result_valid;

    initial begin
        benchmark_result = 0;
        benchmark_result_valid = 0;
    end

    // Capture a0 before it gets overwritten by the startup code at PC=0x8
    always @(posedge clk) begin
        if (u_cpu.commit_valid && u_cpu.commit_pc == 32'h00000008) begin
             benchmark_result <= u_cpu.u_regfile.regs[10];
             benchmark_result_valid <= 1'b1;
        end
    end

    // --- Clock ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Utils ---
    integer i;
    reg [1023:0] hex_filename;

    // --- Memory Logic ---
    initial begin
        // Init RAM to 0
        for(i=0; i<262144; i=i+1) ram[i] = 8'b0;
        
        // Load Hex (Byte oriented)
        if ($value$plusargs("HEX_FILE=%s", hex_filename)) 
            $readmemh(hex_filename, ram); 
        else 
            $readmemh("inst_rom.hex", ram);
    end
    
    // Fetch: Little Endian - Combine 4 bytes into 1 word
    assign inst_i = (inst_ce_o == `ReadEnable) ? 
                    {ram[inst_addr_o+3], ram[inst_addr_o+2], ram[inst_addr_o+1], ram[inst_addr_o]} : 
                    `ZeroWord;
    
    // Load: Little Endian - Combine 4 bytes into 1 word
    assign mem_data_i = {ram[mem_addr_o+3], ram[mem_addr_o+2], ram[mem_addr_o+1], ram[mem_addr_o]}; 
    
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
                // Check exit condition for array_test benchmarks
                if (mem_addr_o == 32'h00030004) begin
                    $display("Result in x1 (Unsigned): %d", u_cpu.u_regfile.regs[1]);
                    
                    if (benchmark_result_valid)
                        $display("Result in a0 (Unsigned): %d", benchmark_result);
                    else
                        $display("Result in a0 (Unsigned): %d", u_cpu.u_regfile.regs[10]);
                    
                    $display("TOTAL_BRANCH: %d", u_cpu.u_rob.cnt_total_branch);
                    $display("CORRECT_BRANCH: %d", u_cpu.u_rob.cnt_correct_branch);
                    $finish;
                end


                // Store - Little Endian
                if(mem_sel_o[0]) ram[mem_addr_o]   <= mem_data_o[7:0];
                if(mem_sel_o[1]) ram[mem_addr_o+1] <= mem_data_o[15:8];
                if(mem_sel_o[2]) ram[mem_addr_o+2] <= mem_data_o[23:16];
                if(mem_sel_o[3]) ram[mem_addr_o+3] <= mem_data_o[31:24];
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
             
             $display("Result in x1 (Unsigned): %d", u_cpu.u_regfile.regs[1]);
             $display("Result in x1 (Signed):   %d", $signed(u_cpu.u_regfile.regs[1]));
             
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
