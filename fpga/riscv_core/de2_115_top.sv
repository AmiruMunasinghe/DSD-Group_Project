// DE2-115 top level.
//   KEY[0]  : reset (active low)
//   SW[17]  : 1 = HEX shows PC, 0 = HEX shows value written by program to 0x1000_0008
//   SW[16:0]: readable by software at 0x1000_000C
//   LEDR/LEDG driven by software (0x1000_0000 / 0x1000_0004)
module de2_115_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,
    input  logic [17:0] SW,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    output logic [7:0]  VGA_R,
    output logic [7:0]  VGA_G,
    output logic [7:0]  VGA_B,
    output logic        VGA_HS,
    output logic        VGA_VS,
    output logic        VGA_BLANK_N,
    output logic        VGA_SYNC_N,
    output logic        VGA_CLK,
    inout  wire  [15:0] SRAM_DQ,
    output logic [19:0] SRAM_ADDR,
    output logic        SRAM_LB_N,
    output logic        SRAM_UB_N,
    output logic        SRAM_CE_N,
    output logic        SRAM_OE_N,
    output logic        SRAM_WE_N
);
    // 50 MHz -> 25 MHz core clock
    logic clk_div = 1'b0;
    always_ff @(posedge CLOCK_50) clk_div <= ~clk_div;
    wire clk = clk_div;

    // reset synchroniser
    logic [1:0] rst_sync;
    always_ff @(posedge clk or negedge KEY[0])
        if (!KEY[0]) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};
    wire rst_n = rst_sync[1];

    logic [31:0] io_hex, pc_out, disp;
    logic [14:0] vga_raddr;
    logic [15:0] vga_pixel;

    logic        acc_start;
    logic [31:0] acc_src_addr, acc_dst_addr, acc_weight_addr;
    logic [15:0] acc_width, acc_height;
    logic [7:0]  acc_in_ch, acc_out_ch;
    logic        acc_busy, acc_done;

    assign acc_busy = 1'b0;
    assign acc_done = acc_start;

    cpu #(.IMEM_FILE("program.hex")) u_cpu (
        .clk(clk), .rst_n(rst_n),
        .io_sw(SW), .io_key(KEY),
        .io_ledr(LEDR), .io_ledg(LEDG), .io_hex(io_hex),
        .pc_out(pc_out),
        .vga_raddr(vga_raddr),
        .vga_pixel(vga_pixel),
        .acc_start(acc_start),
        .acc_src_addr(acc_src_addr),
        .acc_dst_addr(acc_dst_addr),
        .acc_weight_addr(acc_weight_addr),
        .acc_width(acc_width),
        .acc_height(acc_height),
        .acc_in_ch(acc_in_ch),
        .acc_out_ch(acc_out_ch),
        .acc_busy(acc_busy),
        .acc_done(acc_done),
        .SRAM_DQ(SRAM_DQ),
        .SRAM_ADDR(SRAM_ADDR),
        .SRAM_LB_N(SRAM_LB_N),
        .SRAM_UB_N(SRAM_UB_N),
        .SRAM_CE_N(SRAM_CE_N),
        .SRAM_OE_N(SRAM_OE_N),
        .SRAM_WE_N(SRAM_WE_N)
    );

    vga_160x120 u_vga (
        .clk(clk),
        .rst_n(rst_n),
        .fb_raddr(vga_raddr),
        .fb_pixel(vga_pixel),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_CLK(VGA_CLK)
    );

    assign disp = SW[17] ? pc_out : io_hex;

    hex7seg h0 (.d(disp[3:0]),   .seg(HEX0));
    hex7seg h1 (.d(disp[7:4]),   .seg(HEX1));
    hex7seg h2 (.d(disp[11:8]),  .seg(HEX2));
    hex7seg h3 (.d(disp[15:12]), .seg(HEX3));
    hex7seg h4 (.d(disp[19:16]), .seg(HEX4));
    hex7seg h5 (.d(disp[23:20]), .seg(HEX5));
    hex7seg h6 (.d(disp[27:24]), .seg(HEX6));
    hex7seg h7 (.d(disp[31:28]), .seg(HEX7));
endmodule
