// 5-stage pipelined RV32I core:  IF | ID | EX | MEM | WB
// Four pipeline registers: IF/ID, ID/EX, EX/MEM, MEM/WB.
// - Forwarding EX/MEM->EX and MEM/WB->EX
// - Load-use hazard: 2-cycle stall (data memory has a synchronous read)
// - Branches/jumps resolved in EX (2-cycle flush penalty, predict not-taken)
module cpu #(
    parameter IMEM_FILE = "program.hex",
    parameter DMEM_FILE = "",
    parameter IMEM_WORDS = 1024,
    parameter DMEM_WORDS = 1024
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [17:0] io_sw,
    input  logic [3:0]  io_key,
    output logic [17:0] io_ledr,
    output logic [8:0]  io_ledg,
    output logic [31:0] io_hex,
    output logic [31:0] pc_out,
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
    inout  wire  [15:0] SRAM_DQ,
    output logic [19:0] SRAM_ADDR,
    output logic        SRAM_LB_N,
    output logic        SRAM_UB_N,
    output logic        SRAM_CE_N,
    output logic        SRAM_OE_N,
    output logic        SRAM_WE_N
);
    localparam [31:0] NOP = 32'h0000_0013;

    // ------------------------------------------------------------ IF
    logic [31:0] pc_curr, pc_plus4, pc_nxt, if_instr, imem_addr;
    logic        stall, load_stall, mem_stall, redirect;
    logic [31:0] ex_target;

    inc_alu u_inc (.pc_curr(pc_curr), .pc_next(pc_plus4));

    pc u_pc (
        .clk(clk), .rst_n(rst_n),
        .stall(stall), .mux_pc(redirect),
        .pc_branch(ex_target), .pc_next(pc_plus4),
        .pc_nxt(pc_nxt), .pc_curr(pc_curr)
    );
    assign pc_out = pc_curr;

    assign imem_addr = rst_n ? pc_nxt : 32'd0;
    ins_mem #(.FILE(IMEM_FILE), .WORDS(IMEM_WORDS)) u_imem (
        .clk(clk), .addr(imem_addr), .instr(if_instr)
    );

    // ------------------------------------------------- IF/ID register
    logic [31:0] id_pc, id_instr;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc <= 32'd0; id_instr <= NOP;
        end else if (redirect) begin
            id_pc <= 32'd0; id_instr <= NOP;
        end else if (!stall) begin
            id_pc <= pc_curr; id_instr <= if_instr;
        end
    end

    // ------------------------------------------------------------ ID
    wire [4:0] id_rs1 = id_instr[19:15];
    wire [4:0] id_rs2 = id_instr[24:20];
    wire [4:0] id_rd  = id_instr[11:7];

    logic        c_reg_write, c_mem_read, c_mem_write, c_branch, c_jal, c_jalr, c_b_sel;
    logic [1:0]  c_a_sel;
    logic [3:0]  c_alu_op;
    control u_ctrl (
        .instr(id_instr), .reg_write(c_reg_write), .mem_read(c_mem_read),
        .mem_write(c_mem_write), .branch(c_branch), .jal(c_jal), .jalr(c_jalr),
        .a_sel(c_a_sel), .b_sel(c_b_sel), .alu_op(c_alu_op)
    );

    logic [31:0] id_imm, id_rs1v, id_rs2v;
    imm_gen u_imm (.instr(id_instr), .imm(id_imm));

    logic        wb_we;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;
    regfile u_rf (
        .clk(clk), .we(wb_we), .waddr(wb_rd), .wdata(wb_data),
        .raddr1(id_rs1), .raddr2(id_rs2), .rdata1(id_rs1v), .rdata2(id_rs2v)
    );

    // Hazard detection (load in EX or MEM, consumer in ID)
    logic        ex_mem_read, m_mem_read;
    logic [4:0]  ex_rd, m_rd;
    assign load_stall = ((ex_mem_read && ex_rd != 0 && (ex_rd == id_rs1 || ex_rd == id_rs2)) ||
                         (m_mem_read  && m_rd  != 0 && (m_rd  == id_rs1 || m_rd  == id_rs2)))
                        && !redirect;
    assign stall = load_stall || mem_stall;

    // ------------------------------------------------ ID/EX register
    logic [31:0] ex_pc, ex_rs1v, ex_rs2v, ex_imm;
    logic [4:0]  ex_rs1, ex_rs2;
    logic [2:0]  ex_funct3;
    logic        ex_reg_write, ex_mem_write, ex_branch, ex_jal, ex_jalr, ex_b_sel;
    logic [1:0]  ex_a_sel;
    logic [3:0]  ex_alu_op;

    // synchronous reset/bubble (rst_n is already synchronised in the top level)
    always_ff @(posedge clk) begin
        if (!rst_n || redirect || load_stall) begin
            // bubble
            ex_reg_write <= 0; ex_mem_read <= 0; ex_mem_write <= 0;
            ex_branch <= 0; ex_jal <= 0; ex_jalr <= 0;
            ex_rd <= 0; ex_rs1 <= 0; ex_rs2 <= 0;
            ex_pc <= 0; ex_rs1v <= 0; ex_rs2v <= 0; ex_imm <= 0;
            ex_funct3 <= 0; ex_a_sel <= 0; ex_b_sel <= 0; ex_alu_op <= 0;
        end else if (!mem_stall) begin
            ex_reg_write <= c_reg_write; ex_mem_read <= c_mem_read;
            ex_mem_write <= c_mem_write; ex_branch <= c_branch;
            ex_jal <= c_jal; ex_jalr <= c_jalr;
            ex_rd <= id_rd; ex_rs1 <= id_rs1; ex_rs2 <= id_rs2;
            ex_pc <= id_pc; ex_rs1v <= id_rs1v; ex_rs2v <= id_rs2v; ex_imm <= id_imm;
            ex_funct3 <= id_instr[14:12];
            ex_a_sel <= c_a_sel; ex_b_sel <= c_b_sel; ex_alu_op <= c_alu_op;
        end
    end

    // ------------------------------------------------------------ EX
    logic        m_reg_write, m_mem_write;
    logic [31:0] m_result, m_wdata;
    logic [2:0]  m_funct3;
    logic        w_reg_write, w_mem_read;
    logic [31:0] w_result;
    logic [4:0]  w_rd;

    // forwarding
    logic [31:0] fwd_a, fwd_b;
    always_comb begin
        if (m_reg_write && m_rd != 0 && m_rd == ex_rs1)         fwd_a = m_result;
        else if (wb_we && wb_rd != 0 && wb_rd == ex_rs1)        fwd_a = wb_data;
        else                                                    fwd_a = ex_rs1v;

        if (m_reg_write && m_rd != 0 && m_rd == ex_rs2)         fwd_b = m_result;
        else if (wb_we && wb_rd != 0 && wb_rd == ex_rs2)        fwd_b = wb_data;
        else                                                    fwd_b = ex_rs2v;
    end

    logic [31:0] alu_a, alu_b, alu_res;
    logic        alu_zero;
    always_comb begin
        case (ex_a_sel)
            2'd0:    alu_a = fwd_a;
            2'd1:    alu_a = ex_pc;
            default: alu_a = 32'd0;
        endcase
        alu_b = ex_b_sel ? ex_imm : fwd_b;
    end
    alu u_alu (.a(alu_a), .b(alu_b), .op(ex_alu_op), .result(alu_res), .zero(alu_zero));

    // branch condition
    logic br_taken;
    always_comb begin
        case (ex_funct3)
            3'b000:  br_taken = (fwd_a == fwd_b);
            3'b001:  br_taken = (fwd_a != fwd_b);
            3'b100:  br_taken = ($signed(fwd_a) <  $signed(fwd_b));
            3'b101:  br_taken = ($signed(fwd_a) >= $signed(fwd_b));
            3'b110:  br_taken = (fwd_a <  fwd_b);
            3'b111:  br_taken = (fwd_a >= fwd_b);
            default: br_taken = 1'b0;
        endcase
        br_taken = br_taken & ex_branch;
    end

    logic [31:0] br_target;
    branch_alu u_bra (.pc_curr(ex_pc), .offset(ex_imm), .pc_branch(br_target));
    wire [31:0] jalr_target = (fwd_a + ex_imm) & 32'hFFFF_FFFE;

    assign ex_target = ex_jalr ? jalr_target : br_target;
    assign redirect  = br_taken | ex_jal | ex_jalr;

    wire [31:0] ex_result = (ex_jal | ex_jalr) ? (ex_pc + 32'd4) : alu_res;

    // ----------------------------------------------- EX/MEM register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_reg_write <= 0; m_mem_read <= 0; m_mem_write <= 0;
            m_result <= 0; m_wdata <= 0; m_rd <= 0; m_funct3 <= 0;
        end else if (!mem_stall) begin
            m_reg_write <= ex_reg_write; m_mem_read <= ex_mem_read;
            m_mem_write <= ex_mem_write;
            m_result <= ex_result; m_wdata <= fwd_b;
            m_rd <= ex_rd; m_funct3 <= ex_funct3;
        end
    end

    // ----------------------------------------------------------- MEM
    logic [31:0] dm_rdata;
    data_mem #(.FILE(DMEM_FILE), .WORDS(DMEM_WORDS)) u_dmem (
        .clk(clk), .rst_n(rst_n),
        .addr(m_result), .wdata(m_wdata), .re(m_mem_read), .we(m_mem_write), .funct3(m_funct3),
        .rdata(dm_rdata),
        .io_sw(io_sw), .io_key(io_key),
        .io_ledr(io_ledr), .io_ledg(io_ledg), .io_hex(io_hex),
        .vga_raddr(vga_raddr), .vga_pixel(vga_pixel),
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
        .mem_busy(mem_stall),
        .SRAM_DQ(SRAM_DQ),
        .SRAM_ADDR(SRAM_ADDR),
        .SRAM_LB_N(SRAM_LB_N),
        .SRAM_UB_N(SRAM_UB_N),
        .SRAM_CE_N(SRAM_CE_N),
        .SRAM_OE_N(SRAM_OE_N),
        .SRAM_WE_N(SRAM_WE_N)
    );

    // ----------------------------------------------- MEM/WB register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_reg_write <= 0; w_mem_read <= 0; w_result <= 0; w_rd <= 0;
        end else if (!mem_stall) begin
            w_reg_write <= m_reg_write; w_mem_read <= m_mem_read;
            w_result <= m_result; w_rd <= m_rd;
        end
    end

    // ------------------------------------------------------------ WB
    assign wb_we   = w_reg_write;
    assign wb_rd   = w_rd;
    assign wb_data = w_mem_read ? dm_rdata : w_result;
endmodule
