module branch_alu (
    input  logic [31:0] pc_curr,
    input  logic [31:0] offset,
    output logic [31:0] pc_branch
);
    assign pc_branch = pc_curr + offset;
endmodule
