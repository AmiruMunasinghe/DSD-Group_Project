// 32x32 register file, write on posedge, async read with
// write-through bypass (WB -> ID in the same cycle). x0 is hard-wired to 0.
module regfile (
    input  logic        clk,
    input  logic        we,
    input  logic [4:0]  waddr,
    input  logic [31:0] wdata,
    input  logic [4:0]  raddr1,
    input  logic [4:0]  raddr2,
    output logic [31:0] rdata1,
    output logic [31:0] rdata2
);
    logic [31:0] regs [1:31];

    always_ff @(posedge clk)
        if (we && waddr != 5'd0) regs[waddr] <= wdata;

    always_comb begin
        if (raddr1 == 5'd0)                    rdata1 = 32'd0;
        else if (we && waddr == raddr1)        rdata1 = wdata;
        else                                   rdata1 = regs[raddr1];

        if (raddr2 == 5'd0)                    rdata2 = 32'd0;
        else if (we && waddr == raddr2)        rdata2 = wdata;
        else                                   rdata2 = regs[raddr2];
    end
endmodule
