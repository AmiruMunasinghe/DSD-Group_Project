module inc_alu (
    input  logic [31:0] pc_curr,
    output logic [31:0] pc_next
);
    assign pc_next = pc_curr + 32'd4;
endmodule
