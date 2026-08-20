// rv32i_core.v — 3-stage pipelined RV32I core.
//
// Pipeline stages:
//   IF     : PC register drives synchronous imem; instruction appears next cycle.
//   ID/EX  : decode, regfile read (+WB->EX forwarding), ALU, branch/jump
//            resolution, and memory address/store formatting.
//   MEM/WB : capture synchronous dmem read data, format loads, select and
//            write back the result.
//
// Hazards:
//   Data    : a single WB->EX forwarding path. In a 3-stage pipeline the only
//             RAW distance that races the regfile is 1 (producer in WB while
//             consumer is in EX); distance >=2 is already committed and read
//             normally. Load data is a registered dmem output, stable through
//             the whole MEM/WB cycle, so loads forward with NO stall.
//   Control : branch/jump resolved in EX -> exactly one shadow instruction is
//             squashed (1-cycle penalty), and PC is redirected.
//
// I/O: a memory-mapped 16-bit output register (LED_ADDR) drives board LEDs;
//      ECALL/EBREAK halts the core (freezes PC, squashes the pipeline).
`include "rv32i_defs.vh"
`default_nettype none

module rv32i_core #(
    parameter IMEM_AW   = 12,
    parameter DMEM_AW   = 12,
    parameter IMEM_INIT = "",
    parameter DMEM_INIT = "",
    parameter [31:0] RESET_PC = 32'h0000_0000,
    parameter [31:0] LED_ADDR = 32'h0000_1000
)(
    input  wire        clk,
    input  wire        rst_n,       // synchronous, active-low
    output reg  [15:0] led,
    output reg         halted
);
    // ======================= IF stage =======================
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] instr;               // registered imem output (this cycle's EX instr)

    imem #(.ADDR_WIDTH(IMEM_AW), .INIT_FILE(IMEM_INIT)) u_imem (
        .clk(clk), .en(1'b1), .addr(pc), .rdata(instr)
    );

    // id_pc: PC value that corresponds to `instr` currently in EX (PC delayed 1).
    reg [31:0] id_pc;

    // flush_ex: the instruction currently in EX is the shadow of a taken
    // branch/jump from the previous cycle and must be squashed.
    reg flush_ex;

    // ======================= ID/EX stage =======================
    wire [4:0]  rs1, rs2, rd;
    wire [2:0]  funct3;
    wire [31:0] imm;
    wire [3:0]  alu_op;
    wire        alu_src_a, alu_src_b;
    wire [1:0]  result_sel;
    wire        reg_write, mem_read, mem_write, is_branch, is_jal, is_jalr, is_halt;

    decoder u_decoder (
        .instr(instr),
        .rs1(rs1), .rs2(rs2), .rd(rd), .funct3(funct3),
        .imm(imm), .alu_op(alu_op), .alu_src_a(alu_src_a), .alu_src_b(alu_src_b),
        .result_sel(result_sel), .reg_write(reg_write),
        .mem_read(mem_read), .mem_write(mem_write),
        .is_branch(is_branch), .is_jal(is_jal), .is_jalr(is_jalr), .is_halt(is_halt)
    );

    // Squash EX when it holds a branch shadow, or once the core is halted.
    wire squash = flush_ex || halted;

    // ---- register file (write port lives in MEM/WB, below) ----
    wire [31:0] rs1_data, rs2_data;
    // WB-stage write signals (declared here, driven in MEM/WB section)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    regfile u_regfile (
        .clk(clk),
        .rs1_addr(rs1), .rs1_data(rs1_data),
        .rs2_addr(rs2), .rs2_data(rs2_data),
        .we(wb_reg_write), .rd_addr(wb_rd), .rd_data(wb_data)
    );

    // ---- WB->EX forwarding ----
    wire fwd_a = wb_reg_write && (wb_rd != 5'd0) && (wb_rd == rs1);
    wire fwd_b = wb_reg_write && (wb_rd != 5'd0) && (wb_rd == rs2);
    wire [31:0] rs1_fwd = fwd_a ? wb_data : rs1_data;
    wire [31:0] rs2_fwd = fwd_b ? wb_data : rs2_data;

    // ---- ALU ----
    wire [31:0] alu_a = (alu_src_a == `A_PC)  ? id_pc  : rs1_fwd;
    wire [31:0] alu_b = (alu_src_b == `B_IMM) ? imm    : rs2_fwd;
    wire [31:0] alu_y;
    alu u_alu (.a(alu_a), .b(alu_b), .op(alu_op), .y(alu_y), .zero());

    // ---- branch condition ----
    reg branch_cond;
    always @(*) begin
        case (funct3)
            `F3_BEQ : branch_cond = (rs1_fwd == rs2_fwd);
            `F3_BNE : branch_cond = (rs1_fwd != rs2_fwd);
            `F3_BLT : branch_cond = ($signed(rs1_fwd) <  $signed(rs2_fwd));
            `F3_BGE : branch_cond = ($signed(rs1_fwd) >= $signed(rs2_fwd));
            `F3_BLTU: branch_cond = (rs1_fwd <  rs2_fwd);
            `F3_BGEU: branch_cond = (rs1_fwd >= rs2_fwd);
            default : branch_cond = 1'b0;
        endcase
    end

    wire take_branch = is_branch && branch_cond;
    wire redirect    = (~squash) && (take_branch || is_jal || is_jalr);

    wire [31:0] jalr_target   = (rs1_fwd + imm) & 32'hFFFF_FFFE;
    wire [31:0] pcrel_target  = id_pc + imm;             // branch / JAL
    wire [31:0] redirect_target = is_jalr ? jalr_target : pcrel_target;

    // ---- data memory address + store formatting (EX drives dmem) ----
    wire [31:0] mem_addr = alu_y;
    wire [1:0]  byte_off = mem_addr[1:0];
    wire        is_led   = (mem_addr == LED_ADDR);

    // Replicate store data across lanes; byte-enables pick the target lane(s).
    reg  [3:0]  store_be;
    reg  [31:0] store_wdata;
    always @(*) begin
        store_be    = 4'b0000;
        store_wdata = rs2_fwd;
        case (funct3)
            `F3_B: begin
                store_wdata = {4{rs2_fwd[7:0]}};
                store_be    = 4'b0001 << byte_off;
            end
            `F3_H: begin
                store_wdata = {2{rs2_fwd[15:0]}};
                store_be    = byte_off[1] ? 4'b1100 : 4'b0011;
            end
            `F3_W: begin
                store_wdata = rs2_fwd;
                store_be    = 4'b1111;
            end
            default: begin
                store_wdata = rs2_fwd;
                store_be    = 4'b1111;
            end
        endcase
    end

    // Effective control after squash/halt gating.
    wire do_reg_write = reg_write && ~squash;
    wire do_mem_write = mem_write && ~squash;
    wire [3:0] dmem_be = (do_mem_write && ~is_led) ? store_be : 4'b0000;

    wire [31:0] dmem_rdata;
    dmem #(.ADDR_WIDTH(DMEM_AW), .INIT_FILE(DMEM_INIT)) u_dmem (
        .clk(clk), .en(1'b1), .we(dmem_be),
        .addr(mem_addr), .wdata(store_wdata), .rdata(dmem_rdata)
    );

    // ======================= MEM/WB pipeline register =======================
    reg        wb_reg_write_r;
    reg [4:0]  wb_rd_r;
    reg [1:0]  wb_result_sel_r;
    reg [31:0] wb_alu_result_r;
    reg [31:0] wb_pc4_r;
    reg [2:0]  wb_funct3_r;
    reg [1:0]  wb_byteoff_r;

    // ======================= sequential state =======================
    wire halted_next = halted || (is_halt && ~squash);

    always @(posedge clk) begin
        if (!rst_n) begin
            pc              <= RESET_PC;
            id_pc           <= 32'd0;
            flush_ex        <= 1'b0;
            halted          <= 1'b0;
            led             <= 16'd0;
            wb_reg_write_r  <= 1'b0;
            wb_rd_r         <= 5'd0;
            wb_result_sel_r <= `RES_ALU;
            wb_alu_result_r <= 32'd0;
            wb_pc4_r        <= 32'd0;
            wb_funct3_r     <= 3'd0;
            wb_byteoff_r    <= 2'd0;
        end else begin
            // PC update
            if (halted_next)      pc <= pc;
            else if (redirect)    pc <= redirect_target;
            else                  pc <= pc_plus4;

            id_pc    <= pc;
            flush_ex <= redirect;          // next cycle's EX instr is the shadow
            halted   <= halted_next;

            // memory-mapped LED write
            if (do_mem_write && is_led)
                led <= store_wdata[15:0];

            // latch EX results into MEM/WB
            wb_reg_write_r  <= do_reg_write;
            wb_rd_r         <= rd;
            wb_result_sel_r <= result_sel;
            wb_alu_result_r <= alu_y;
            wb_pc4_r        <= id_pc + 32'd4;
            wb_funct3_r     <= funct3;
            wb_byteoff_r    <= byte_off;
        end
    end

    // ======================= MEM/WB combinational =======================
    // Load extraction/extension from the (registered) dmem word.
    reg [31:0] load_ext;
    reg [7:0]  lb;
    reg [15:0] lh;
    always @(*) begin
        lb = dmem_rdata[8*wb_byteoff_r +: 8];
        lh = wb_byteoff_r[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
        case (wb_funct3_r)
            `F3_B:  load_ext = {{24{lb[7]}},  lb};      // LB
            `F3_H:  load_ext = {{16{lh[15]}}, lh};      // LH
            `F3_W:  load_ext = dmem_rdata;              // LW
            `F3_BU: load_ext = {24'd0, lb};             // LBU
            `F3_HU: load_ext = {16'd0, lh};             // LHU
            default: load_ext = dmem_rdata;
        endcase
    end

    reg [31:0] wb_data_r;
    always @(*) begin
        case (wb_result_sel_r)
            `RES_MEM: wb_data_r = load_ext;
            `RES_PC4: wb_data_r = wb_pc4_r;
            default : wb_data_r = wb_alu_result_r;
        endcase
    end

    assign wb_reg_write = wb_reg_write_r;
    assign wb_rd        = wb_rd_r;
    assign wb_data      = wb_data_r;

endmodule

`default_nettype wire
