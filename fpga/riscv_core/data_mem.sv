// Data memory + memory-mapped DE2-115 I/O.
//   0x0000_0000 - 0x0000_0FFF : CPU RAM by default
//   0x1000_0000 - 0x1000_00FF : LED/HEX/SW/KEY I/O
//   0x2000_0000 - 0x2000_00FF : CNN accelerator control/status registers
//   0x2001_0000 - 0x2001_3FFF : CNN weight RAM, 16 KB by default
//   0x3000_0000 - 0x3000_95FF : VGA 160x120 RGB565 framebuffer, 38.4 KB
//   0x4000_0000 - 0x401F_FFFF : external 2 MB SRAM window
// Reads are synchronous: data for an address presented in the MEM stage
// is valid (already sign/zero-extended) during the WB stage.
module data_mem #(
    parameter WORDS = 1024,
    parameter WEIGHT_WORDS = 4096,
    parameter VGA_WORDS = 9600,
    parameter FILE  = ""
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        re,
    input  logic        we,
    input  logic [2:0]  funct3,     // 000 b, 001 h, 010 w, 100 bu, 101 hu
    output logic [31:0] rdata,
    input  logic [17:0] io_sw,
    input  logic [3:0]  io_key,
    output logic [17:0] io_ledr,
    output logic [8:0]  io_ledg,
    output logic [31:0] io_hex,
    input  logic [14:0] vga_raddr,
    output logic [15:0] vga_pixel,
    output logic        acc_start,
    output logic [31:0] acc_src_addr,
    output logic [31:0] acc_dst_addr,
    output logic [31:0] acc_weight_addr,
    output logic [15:0] acc_width,
    output logic [15:0] acc_height,
    output logic [7:0]  acc_in_ch,
    output logic [7:0]  acc_out_ch,
    input  logic        acc_busy,
    input  logic        acc_done,
    output logic        mem_busy,
    inout  wire  [15:0] SRAM_DQ,
    output logic [19:0] SRAM_ADDR,
    output logic        SRAM_LB_N,
    output logic        SRAM_UB_N,
    output logic        SRAM_CE_N,
    output logic        SRAM_OE_N,
    output logic        SRAM_WE_N
);
    (* ramstyle = "M9K" *) logic [31:0] ram [0:WORDS-1];
    (* ramstyle = "M9K" *) logic [31:0] weight_ram [0:WEIGHT_WORDS-1];
    (* ramstyle = "M9K" *) logic [31:0] vga_ram [0:VGA_WORDS-1];
    initial if (FILE != "") $readmemh(FILE, ram);

    wire is_ram       = (addr[31:28] == 4'h0);
    wire is_io        = (addr[31:28] == 4'h1);
    wire is_acc_regs  = (addr[31:16] == 16'h2000);
    wire is_weight    = (addr[31:16] == 16'h2001);
    wire is_vga       = (addr[31:16] == 16'h3000);
    wire is_sram      = (addr[31:21] == 11'b0100_0000_000);
    wire [$clog2(WORDS)-1:0] widx = addr[$clog2(WORDS)+1:2];
    wire [$clog2(WEIGHT_WORDS)-1:0] weight_widx = addr[$clog2(WEIGHT_WORDS)+1:2];
    wire [$clog2(VGA_WORDS)-1:0] vga_widx = addr[$clog2(VGA_WORDS)+1:2];

    // byte enables / data lane alignment for stores
    logic [3:0]  be;
    logic [31:0] wshift;
    always_comb begin
        case (funct3[1:0])
            2'b00:   begin be = 4'b0001 << addr[1:0];
                           wshift = {4{wdata[7:0]}}; end
            2'b01:   begin be = addr[1] ? 4'b1100 : 4'b0011;
                           wshift = {2{wdata[15:0]}}; end
            default: begin be = 4'b1111; wshift = wdata; end
        endcase
    end

    // RAM regions
    logic [31:0] ram_q, weight_q, vga_q;
    always_ff @(posedge clk) begin
        if (we && is_ram) begin
            if (be[0]) ram[widx][7:0]   <= wshift[7:0];
            if (be[1]) ram[widx][15:8]  <= wshift[15:8];
            if (be[2]) ram[widx][23:16] <= wshift[23:16];
            if (be[3]) ram[widx][31:24] <= wshift[31:24];
        end
        if (we && is_weight) begin
            if (be[0]) weight_ram[weight_widx][7:0]   <= wshift[7:0];
            if (be[1]) weight_ram[weight_widx][15:8]  <= wshift[15:8];
            if (be[2]) weight_ram[weight_widx][23:16] <= wshift[23:16];
            if (be[3]) weight_ram[weight_widx][31:24] <= wshift[31:24];
        end
        if (we && is_vga) begin
            if (be[0]) vga_ram[vga_widx][7:0]   <= wshift[7:0];
            if (be[1]) vga_ram[vga_widx][15:8]  <= wshift[15:8];
            if (be[2]) vga_ram[vga_widx][23:16] <= wshift[23:16];
            if (be[3]) vga_ram[vga_widx][31:24] <= wshift[31:24];
        end
        ram_q <= ram[widx];
        weight_q <= weight_ram[weight_widx];
        vga_q <= vga_ram[vga_widx];
    end

    // VGA read port: two RGB565 pixels packed per 32-bit word.
    logic [31:0] vga_rd_word;
    always_ff @(posedge clk) begin
        vga_rd_word <= vga_ram[vga_raddr[14:1]];
        vga_pixel <= vga_raddr[0] ? vga_rd_word[31:16] : vga_rd_word[15:0];
    end

    // I/O and accelerator control registers
    logic acc_start_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            io_ledr <= '0; io_ledg <= '0; io_hex <= '0;
            acc_start_q <= 1'b0;
            acc_src_addr <= 32'd0;
            acc_dst_addr <= 32'd0;
            acc_weight_addr <= 32'h2001_0000;
            acc_width <= 16'd160;
            acc_height <= 16'd120;
            acc_in_ch <= 8'd3;
            acc_out_ch <= 8'd4;
        end else begin
            acc_start_q <= 1'b0;

            if (we && is_io) begin
                case (addr[4:2])
                    3'd0: io_ledr <= wdata[17:0];
                    3'd1: io_ledg <= wdata[8:0];
                    3'd2: io_hex  <= wdata;
                    default: ;
                endcase
            end

            if (we && is_acc_regs) begin
                case (addr[5:2])
                    4'd0: acc_start_q <= wdata[0];
                    4'd2: acc_src_addr <= wdata;
                    4'd3: acc_dst_addr <= wdata;
                    4'd4: acc_weight_addr <= wdata;
                    4'd5: begin acc_width <= wdata[15:0]; acc_height <= wdata[31:16]; end
                    4'd6: begin acc_in_ch <= wdata[7:0]; acc_out_ch <= wdata[15:8]; end
                    default: ;
                endcase
            end
        end
    end
    assign acc_start = acc_start_q;

    logic [31:0] sram_rdata;
    logic        sram_busy;
    ext_sram_ctrl u_sram_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .req((re || we) && is_sram && !sram_busy),
        .we(we),
        .addr(addr),
        .wdata(wdata),
        .funct3(funct3),
        .rdata(sram_rdata),
        .busy(sram_busy),
        .SRAM_DQ(SRAM_DQ),
        .SRAM_ADDR(SRAM_ADDR),
        .SRAM_LB_N(SRAM_LB_N),
        .SRAM_UB_N(SRAM_UB_N),
        .SRAM_CE_N(SRAM_CE_N),
        .SRAM_OE_N(SRAM_OE_N),
        .SRAM_WE_N(SRAM_WE_N)
    );
    assign mem_busy = sram_busy;

    // read path (registered -> available in WB)
    logic [31:0] io_q, acc_q;
    logic [2:0]  region_q;
    logic [1:0]  off_q;
    logic [2:0]  f3_q;
    always_ff @(posedge clk) begin
        if (is_io)             region_q <= 3'd1;
        else if (is_acc_regs)  region_q <= 3'd2;
        else if (is_weight)    region_q <= 3'd3;
        else if (is_vga)       region_q <= 3'd4;
        else if (is_sram)      region_q <= 3'd5;
        else                   region_q <= 3'd0;
        off_q    <= addr[1:0];
        f3_q     <= funct3;
        case (addr[4:2])
            3'd0:    io_q <= {14'b0, io_ledr};
            3'd1:    io_q <= {23'b0, io_ledg};
            3'd2:    io_q <= io_hex;
            3'd3:    io_q <= {14'b0, io_sw};
            3'd4:    io_q <= {28'b0, io_key};
            default: io_q <= 32'b0;
        endcase
        case (addr[5:2])
            4'd0:    acc_q <= {29'd0, acc_done, acc_busy, 1'b0};
            4'd2:    acc_q <= acc_src_addr;
            4'd3:    acc_q <= acc_dst_addr;
            4'd4:    acc_q <= acc_weight_addr;
            4'd5:    acc_q <= {acc_height, acc_width};
            4'd6:    acc_q <= {16'd0, acc_out_ch, acc_in_ch};
            default: acc_q <= 32'd0;
        endcase
    end

    logic [31:0] raw;
    always_comb begin
        case (region_q)
            3'd1:    raw = io_q;
            3'd2:    raw = acc_q;
            3'd3:    raw = weight_q;
            3'd4:    raw = vga_q;
            3'd5:    raw = sram_rdata;
            default: raw = ram_q;
        endcase
    end
    wire [31:0] shift = raw >> {off_q, 3'b000};
    always_comb begin
        case (f3_q)
            3'b000:  rdata = {{24{shift[7]}},  shift[7:0]};
            3'b001:  rdata = {{16{shift[15]}}, shift[15:0]};
            3'b100:  rdata = {24'b0, shift[7:0]};
            3'b101:  rdata = {16'b0, shift[15:0]};
            default: rdata = raw;
        endcase
    end
endmodule
