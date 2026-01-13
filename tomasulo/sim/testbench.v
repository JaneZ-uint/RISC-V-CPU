`timescale 1ns / 1ps
`include "../src/defines.v"
`include "../src/params.v"

module testbench;

    reg clk;
    reg rst;
    
    // Unified Memory (64KB words = 256KB)
    reg [`DataBus] ram [0:65535];
    
    // Instantiate your CPU here (To be implemented)
    // tomasulo_cpu u_cpu (
    //     .clk(clk),
    //     .rst(rst)
    // );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = `RstEnable;
        #20;
        rst = `RstDisable;
        #5000000;
        $display("Timeout!");
        $finish;
    end
   
    initial begin
        $dumpfile("tomasulo_cpu.vcd");
        $dumpvars(0, testbench);
    end

endmodule
