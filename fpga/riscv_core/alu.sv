// RV32I ALU
module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  op,
    output logic [31:0] result,
    output logic        zero
);
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_SLL  = 4'd2;
    localparam ALU_SLT  = 4'd3;
    localparam ALU_SLTU = 4'd4;
    localparam ALU_XOR  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_OR   = 4'd8;
    localparam ALU_AND  = 4'd9;

    always_comb begin
        case (op)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_SLL:  result = a << b[4:0];
            ALU_SLT:  result = {31'b0, $signed(a) < $signed(b)};
            ALU_SLTU: result = {31'b0, a < b};
            ALU_XOR:  result = a ^ b;
            ALU_SRL:  result = a >> b[4:0];
            ALU_SRA:  result = $unsigned($signed(a) >>> b[4:0]);
            ALU_OR:   result = a | b;
            ALU_AND:  result = a & b;
            default:  result = 32'd0;
        endcase
        zero = (result == 32'd0);
    end
endmodule
