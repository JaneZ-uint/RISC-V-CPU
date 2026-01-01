`include "defines.v"

module naive_cpu(
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

    // Wires
    
    // Ctrl
    wire [5:0] stall;
    wire [5:0] flush;
    wire stall_req_id;
    wire branch_flag;
    wire [`InstAddrBus] branch_target_address;
    
    // PC
    wire [`InstAddrBus] pc;
    wire ce;
    
    // IF
    wire [`InstAddrBus] if_pc;
    wire [`InstBus] if_inst;
    
    // IF/ID
    wire [`InstAddrBus] id_pc_i;
    wire [`InstBus] id_inst_i;
    
    // ID
    wire [`AluOpBus] id_aluop_o;
    wire [`AluSelBus] id_alusel_o;
    wire [`DataBus] id_reg1_o;
    wire [`DataBus] id_reg2_o;
    wire [`RegAddrBus] id_wd_o;
    wire id_wreg_o;
    wire [`InstAddrBus] id_pc_o;
    wire [`DataBus] id_imm_o;
    wire [`DataBus] id_reg2_data_o;
    wire [`InstBus] id_inst_o; // Passed through
    
    wire reg1_read;
    wire reg2_read;
    wire [`DataBus] reg1_data;
    wire [`DataBus] reg2_data;
    wire [`RegAddrBus] reg1_addr;
    wire [`RegAddrBus] reg2_addr;
    
    // ID/EX
    wire [`AluOpBus] ex_aluop_i;
    wire [`DataBus] ex_reg1_i;
    wire [`DataBus] ex_reg2_i;
    wire [`RegAddrBus] ex_wd_i;
    wire ex_wreg_i;
    wire [`InstAddrBus] ex_pc_i;
    wire [`DataBus] ex_imm_i;
    wire [`DataBus] ex_reg2_data_i;
    wire [`InstBus] ex_inst_i;
    
    // EX
    wire [`RegAddrBus] ex_wd_o;
    wire ex_wreg_o;
    wire [`DataBus] ex_wdata_o;
    wire [`DataBus] ex_mem_addr_o;
    wire [`DataBus] ex_store_data_o;
    wire [`InstBus] ex_inst_o;
    
    // EX/MEM
    wire [`RegAddrBus] mem_wd_i;
    wire mem_wreg_i;
    wire [`DataBus] mem_wdata_i;
    wire [`DataBus] mem_mem_addr_i;
    wire [`DataBus] mem_store_data_i;
    wire [`InstBus] mem_inst_i;
    
    // MEM
    wire [`RegAddrBus] mem_wd_o;
    wire mem_wreg_o;
    wire [`DataBus] mem_wdata_o;
    
    // MEM/WB
    wire [`RegAddrBus] wb_wd_i;
    wire wb_wreg_i;
    wire [`DataBus] wb_wdata_i;
    
    // Instantiations
    
    ctrl u_ctrl(
        .rst(rst),
        .stall_req_id(stall_req_id),
        .branch_flag(branch_flag),
        .stall(stall),
        .flush(flush)
    );
    
    pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .branch_flag(branch_flag),
        .branch_target_address(branch_target_address),
        .pc(pc),
        .ce(ce)
    );
    
    if_stage u_if_stage(
        .pc(pc),
        .ce(ce),
        .inst_i(inst_i),
        .inst_addr_o(inst_addr_o),
        .ce_o(inst_ce_o),
        .inst_o(if_inst)
    );
    
    if_id_reg u_if_id_reg(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .if_pc(pc), // Pass PC from IF stage (which is just pc_reg output)
        .if_inst(if_inst),
        .id_pc(id_pc_i),
        .id_inst(id_inst_i)
    );
    
    id_stage u_id_stage(
        .rst(rst),
        .pc_i(id_pc_i),
        .inst_i(id_inst_i),
        
        .reg1_data_i(reg1_data),
        .reg2_data_i(reg2_data),
        .reg1_read_o(reg1_read),
        .reg2_read_o(reg2_read),
        .reg1_addr_o(reg1_addr),
        .reg2_addr_o(reg2_addr),
        
        .ex_wreg_i(ex_wreg_o), // Check EX stage output (before EX/MEM reg)
        .ex_wd_i(ex_wd_o),
        .mem_wreg_i(mem_wreg_o), // Check MEM stage output (before MEM/WB reg)
        .mem_wd_i(mem_wd_o),
        
        .aluop_o(id_aluop_o),
        .alusel_o(id_alusel_o),
        .reg1_o(id_reg1_o),
        .reg2_o(id_reg2_o),
        .wd_o(id_wd_o),
        .wreg_o(id_wreg_o),
        .pc_o(id_pc_o),
        .imm_o(id_imm_o),
        .reg2_data_o(id_reg2_data_o),
        .inst_o(id_inst_o), // Pass instruction
        
        .stall_req(stall_req_id)
    );
    
    regfile u_regfile(
        .clk(clk),
        .rst(rst),
        .we(wb_wreg_i),
        .waddr(wb_wd_i),
        .wdata(wb_wdata_i),
        .re1(reg1_read),
        .raddr1(reg1_addr),
        .rdata1(reg1_data),
        .re2(reg2_read),
        .raddr2(reg2_addr),
        .rdata2(reg2_data)
    );
    
    id_ex_reg u_id_ex_reg(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .id_aluop(id_aluop_o),
        .id_reg1(id_reg1_o),
        .id_reg2(id_reg2_o),
        .id_wd(id_wd_o),
        .id_wreg(id_wreg_o),
        .id_pc(id_pc_o),
        .id_imm(id_imm_o),
        .id_reg2_data(id_reg2_data_o),
        .id_inst(id_inst_o),
        
        .ex_aluop(ex_aluop_i),
        .ex_reg1(ex_reg1_i),
        .ex_reg2(ex_reg2_i),
        .ex_wd(ex_wd_i),
        .ex_wreg(ex_wreg_i),
        .ex_pc(ex_pc_i),
        .ex_imm(ex_imm_i),
        .ex_reg2_data(ex_reg2_data_i),
        .ex_inst(ex_inst_i)
    );
    
    ex_stage u_ex_stage(
        .rst(rst),
        .aluop_i(ex_aluop_i),
        .reg1_i(ex_reg1_i),
        .reg2_i(ex_reg2_i),
        .wd_i(ex_wd_i),
        .wreg_i(ex_wreg_i),
        .pc_i(ex_pc_i),
        .imm_i(ex_imm_i),
        .reg2_data_i(ex_reg2_data_i),
        .inst_i(ex_inst_i),
        
        .wd_o(ex_wd_o),
        .wreg_o(ex_wreg_o),
        .wdata_o(ex_wdata_o),
        .mem_addr_o(ex_mem_addr_o),
        .store_data_o(ex_store_data_o),
        .inst_o(ex_inst_o),
        
        .branch_flag_o(branch_flag),
        .branch_target_address_o(branch_target_address)
    );
    
    ex_mem_reg u_ex_mem_reg(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .ex_wd(ex_wd_o),
        .ex_wreg(ex_wreg_o),
        .ex_wdata(ex_wdata_o),
        .ex_mem_addr(ex_mem_addr_o),
        .ex_store_data(ex_store_data_o),
        .ex_inst(ex_inst_o),
        
        .mem_wd(mem_wd_i),
        .mem_wreg(mem_wreg_i),
        .mem_wdata(mem_wdata_i),
        .mem_mem_addr(mem_mem_addr_i),
        .mem_store_data(mem_store_data_i),
        .mem_inst(mem_inst_i)
    );
    
    mem_stage u_mem_stage(
        .rst(rst),
        .wd_i(mem_wd_i),
        .wreg_i(mem_wreg_i),
        .wdata_i(mem_wdata_i),
        .mem_addr_i(mem_mem_addr_i),
        .store_data_i(mem_store_data_i),
        .inst_i(mem_inst_i),
        
        .mem_data_i(mem_data_i),
        .mem_addr_o(mem_addr_o),
        .mem_data_o(mem_data_o),
        .mem_we_o(mem_we_o),
        .mem_ce_o(mem_ce_o),
        .mem_sel_o(mem_sel_o),
        
        .wd_o(mem_wd_o),
        .wreg_o(mem_wreg_o),
        .wdata_o(mem_wdata_o)
    );
    
    mem_wb_reg u_mem_wb_reg(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .mem_wd(mem_wd_o),
        .mem_wreg(mem_wreg_o),
        .mem_wdata(mem_wdata_o),
        
        .wb_wd(wb_wd_i),
        .wb_wreg(wb_wreg_i),
        .wb_wdata(wb_wdata_i)
    );

endmodule
