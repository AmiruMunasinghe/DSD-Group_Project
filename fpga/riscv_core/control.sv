// Main decoder
module control (
    input  logic [31:0] instr,
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        branch,
    output logic        jal,
    output logic        jalr,
    output logic [1:0]  a_sel,     // 0 = rs1, 1 = pc, 2 = zero
    output logic        b_sel,     // 0 = rs2, 1 = imm
    output logic [3:0]  alu_op
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] f3     = instr[14:12];
    wire       f7_5   = instr[30];

    logic [3:0] alu_f;  // operation implied by funct3/funct7
    always_comb begin
        case (f3)
            3'b000: alu_f = (opcode == 7'b0110011 && f7_5) ? 4'd1 : 4'd0; // SUB/ADD
            3'b001: alu_f = 4'd2;                                          // SLL
            3'b010: alu_f = 4'd3;                                          // SLT
            3'b011: alu_f = 4'd4;                                          // SLTU
            3'b100: alu_f = 4'd5;                                          // XOR
            3'b101: alu_f = f7_5 ? 4'd7 : 4'd6;                            // SRA/SRL
            3'b110: alu_f = 4'd8;                                          // OR
            default: alu_f = 4'd9;                                         // AND
        endcase
    end

    always_comb begin
        reg_write = 0; mem_read = 0; mem_write = 0;
        branch = 0; jal = 0; jalr = 0;
        a_sel = 2'd0; b_sel = 1'b0; alu_op = 4'd0;
        case (opcode)
            7'b0110011: begin reg_write = 1; alu_op = alu_f; end             // R
            7'b0010011: begin reg_write = 1; b_sel = 1; alu_op = alu_f; end  // I-ALU
            7'b0000011: begin reg_write = 1; mem_read = 1; b_sel = 1; end    // LOAD
            7'b0100011: begin mem_write = 1; b_sel = 1; end                  // STORE
            7'b1100011: begin branch = 1; end                                // BRANCH
            7'b1101111: begin reg_write = 1; jal = 1; end                    // JAL
            7'b1100111: begin reg_write = 1; jalr = 1; b_sel = 1; end        // JALR
            7'b0110111: begin reg_write = 1; a_sel = 2'd2; b_sel = 1; end    // LUI
            7'b0010111: begin reg_write = 1; a_sel = 2'd1; b_sel = 1; end    // AUIPC
            default: ;
        endcase
    end
endmodule
