// Instruction memory: synchronous-read ROM (maps to Cyclone IV M9K blocks).
// 'addr' is the NEXT pc, so 'instr' lines up with pc_curr.
module ins_mem #(
    parameter FILE  = "program.hex",
    parameter WORDS = 1024            // 4 KB
)(
    input  logic        clk,
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    (* ramstyle = "M9K" *) logic [31:0] rom [0:WORDS-1];

    initial $readmemh(FILE, rom);

    always_ff @(posedge clk)
        instr <= rom[addr[$clog2(WORDS)+1:2]];
endmodule
