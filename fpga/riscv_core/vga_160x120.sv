// 640x480@60-style VGA timing from a 25 MHz pixel clock.
// Reads a 160x120 RGB565 framebuffer and scales each source pixel 4x.
module vga_160x120 (
    input  logic        clk,
    input  logic        rst_n,
    output logic [14:0] fb_raddr,
    input  logic [15:0] fb_pixel,
    output logic [7:0]  VGA_R,
    output logic [7:0]  VGA_G,
    output logic [7:0]  VGA_B,
    output logic        VGA_HS,
    output logic        VGA_VS,
    output logic        VGA_BLANK_N,
    output logic        VGA_SYNC_N,
    output logic        VGA_CLK
);
    localparam int H_ACTIVE = 640;
    localparam int H_FRONT  = 16;
    localparam int H_SYNC   = 96;
    localparam int H_BACK   = 48;
    localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam int V_ACTIVE = 480;
    localparam int V_FRONT  = 10;
    localparam int V_SYNC   = 2;
    localparam int V_BACK   = 33;
    localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    logic [9:0] h_count, v_count;
    logic active;
    logic [7:0] src_x;
    logic [6:0] src_y;

    assign VGA_CLK = clk;
    assign VGA_SYNC_N = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 10'd0;
            if (v_count == V_TOTAL - 1) v_count <= 10'd0;
            else                        v_count <= v_count + 10'd1;
        end else begin
            h_count <= h_count + 10'd1;
        end
    end

    assign active = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign src_x = h_count[9:2];
    assign src_y = v_count[8:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fb_raddr <= 15'd0;
        end else if (active) begin
            fb_raddr <= (src_y * 15'd160) + src_x;
        end
    end

    always_comb begin
        VGA_HS = ~((h_count >= H_ACTIVE + H_FRONT) &&
                   (h_count <  H_ACTIVE + H_FRONT + H_SYNC));
        VGA_VS = ~((v_count >= V_ACTIVE + V_FRONT) &&
                   (v_count <  V_ACTIVE + V_FRONT + V_SYNC));
        VGA_BLANK_N = active;

        if (active) begin
            VGA_R = {fb_pixel[15:11], fb_pixel[15:13]};
            VGA_G = {fb_pixel[10:5],  fb_pixel[10:9]};
            VGA_B = {fb_pixel[4:0],   fb_pixel[4:2]};
        end else begin
            VGA_R = 8'd0;
            VGA_G = 8'd0;
            VGA_B = 8'd0;
        end
    end
endmodule
