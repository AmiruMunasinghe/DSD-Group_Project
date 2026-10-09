`timescale 1ns/1ps
module tb_cpu;
    logic clk = 0, rst_n = 0;
    logic [17:0] ledr; logic [8:0] ledg; logic [31:0] hex, pc;
    logic [14:0] vga_raddr = 15'd0;
    logic [15:0] vga_pixel;
    logic acc_start;
    logic [31:0] acc_src_addr, acc_dst_addr, acc_weight_addr;
    logic [15:0] acc_width, acc_height;
    logic [7:0] acc_in_ch, acc_out_ch;
    wire [15:0] sram_dq;
    logic [19:0] sram_addr;
    logic sram_lb_n, sram_ub_n, sram_ce_n, sram_oe_n, sram_we_n;

    cpu #(.IMEM_FILE("tests/selftest.hex")) dut (
        .clk(clk), .rst_n(rst_n), .io_sw(18'h0), .io_key(4'h0),
        .io_ledr(ledr), .io_ledg(ledg), .io_hex(hex), .pc_out(pc),
        .vga_raddr(vga_raddr), .vga_pixel(vga_pixel),
        .acc_start(acc_start),
        .acc_src_addr(acc_src_addr),
        .acc_dst_addr(acc_dst_addr),
        .acc_weight_addr(acc_weight_addr),
        .acc_width(acc_width),
        .acc_height(acc_height),
        .acc_in_ch(acc_in_ch),
        .acc_out_ch(acc_out_ch),
        .acc_busy(1'b0),
        .acc_done(acc_start),
        .SRAM_DQ(sram_dq),
        .SRAM_ADDR(sram_addr),
        .SRAM_LB_N(sram_lb_n),
        .SRAM_UB_N(sram_ub_n),
        .SRAM_CE_N(sram_ce_n),
        .SRAM_OE_N(sram_oe_n),
        .SRAM_WE_N(sram_we_n));

    always #5 clk = ~clk;

    initial begin
        #23 rst_n = 1;
        repeat (2000) @(posedge clk);
        if (hex === 32'h600D0001) $display("PASS");
        else $display("FAIL hex=%h pc=%h", hex, pc);
        $finish;
    end
endmodule
