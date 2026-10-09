// Program counter. pc_nxt is the combinational next-PC; it is also used as
// the (synchronous) instruction memory address so that the fetched
// instruction arrives in the same cycle as pc_curr.
module pc (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,      // hold PC (load-use hazard)
    input  logic        mux_pc,     // 1 = take branch/jump target
    input  logic [31:0] pc_branch,
    input  logic [31:0] pc_next,    // pc_curr + 4
    output logic [31:0] pc_nxt,
    output logic [31:0] pc_curr
);
    always_comb begin
        if (mux_pc)      pc_nxt = pc_branch;
        else if (stall)  pc_nxt = pc_curr;
        else             pc_nxt = pc_next;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_curr <= 32'b0;
        else        pc_curr <= pc_nxt;
    end
endmodule
