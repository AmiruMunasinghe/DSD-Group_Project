// Simple DE2-115 async SRAM controller for CPU memory-mapped accesses.
// Address map is byte addressed; SRAM_ADDR is halfword addressed.
// 32-bit word reads/writes use two 16-bit SRAM cycles.
module ext_sram_ctrl (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        req,
    input  logic        we,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [2:0]  funct3,
    output logic [31:0] rdata,
    output logic        busy,

    inout  wire  [15:0] SRAM_DQ,
    output logic [19:0] SRAM_ADDR,
    output logic        SRAM_LB_N,
    output logic        SRAM_UB_N,
    output logic        SRAM_CE_N,
    output logic        SRAM_OE_N,
    output logic        SRAM_WE_N
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_RD_LO,
        S_RD_HI,
        S_WR_LO,
        S_WR_HI,
        S_DONE
    } state_t;

    state_t state;
    logic [31:0] addr_q, wdata_q;
    logic [2:0]  funct3_q;
    logic [15:0] rd_lo;
    logic [15:0] dq_out;
    logic        dq_oe;

    assign SRAM_DQ = dq_oe ? dq_out : 16'hzzzz;
    assign busy = (state != S_IDLE) && (state != S_DONE);

    wire [19:0] half_addr = addr_q[20:1];
    wire byte_access = (funct3_q[1:0] == 2'b00);
    wire half_access = (funct3_q[1:0] == 2'b01);
    wire word_access = (funct3_q[1:0] == 2'b10);

    always_comb begin
        SRAM_CE_N = 1'b0;
        SRAM_OE_N = 1'b1;
        SRAM_WE_N = 1'b1;
        SRAM_LB_N = 1'b0;
        SRAM_UB_N = 1'b0;
        SRAM_ADDR = half_addr;
        dq_out = wdata_q[15:0];
        dq_oe = 1'b0;

        unique case (state)
            S_IDLE, S_DONE: begin
                SRAM_CE_N = 1'b1;
                SRAM_LB_N = 1'b1;
                SRAM_UB_N = 1'b1;
            end
            S_RD_LO: begin
                SRAM_OE_N = 1'b0;
                if (byte_access) begin
                    SRAM_LB_N = addr_q[0];
                    SRAM_UB_N = ~addr_q[0];
                end
            end
            S_RD_HI: begin
                SRAM_ADDR = half_addr + 20'd1;
                SRAM_OE_N = 1'b0;
            end
            S_WR_LO: begin
                SRAM_WE_N = 1'b0;
                dq_oe = 1'b1;
                if (byte_access) begin
                    dq_out = {2{wdata_q[7:0]}};
                    SRAM_LB_N = addr_q[0];
                    SRAM_UB_N = ~addr_q[0];
                end else begin
                    dq_out = wdata_q[15:0];
                end
            end
            S_WR_HI: begin
                SRAM_ADDR = half_addr + 20'd1;
                SRAM_WE_N = 1'b0;
                dq_oe = 1'b1;
                dq_out = wdata_q[31:16];
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rdata <= 32'd0;
            addr_q <= 32'd0;
            wdata_q <= 32'd0;
            funct3_q <= 3'd0;
            rd_lo <= 16'd0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    if (req) begin
                        addr_q <= addr;
                        wdata_q <= wdata;
                        funct3_q <= funct3;
                        state <= we ? S_WR_LO : S_RD_LO;
                    end
                end
                S_RD_LO: begin
                    rd_lo <= SRAM_DQ;
                    if (word_access) begin
                        state <= S_RD_HI;
                    end else begin
                        if (byte_access) begin
                            rdata <= addr_q[0] ?
                                (funct3_q[2] ? {24'd0, SRAM_DQ[15:8]} : {{24{SRAM_DQ[15]}}, SRAM_DQ[15:8]}) :
                                (funct3_q[2] ? {24'd0, SRAM_DQ[7:0]}  : {{24{SRAM_DQ[7]}},  SRAM_DQ[7:0]});
                        end else begin
                            rdata <= funct3_q[2] ? {16'd0, SRAM_DQ} : {{16{SRAM_DQ[15]}}, SRAM_DQ};
                        end
                        state <= S_DONE;
                    end
                end
                S_RD_HI: begin
                    rdata <= {SRAM_DQ, rd_lo};
                    state <= S_DONE;
                end
                S_WR_LO: begin
                    if (word_access) state <= S_WR_HI;
                    else             state <= S_DONE;
                end
                S_WR_HI: begin
                    state <= S_DONE;
                end
                S_DONE: begin
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
