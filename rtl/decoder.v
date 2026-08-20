// decoder.v — RV32I instruction decoder (pure combinational).
// Cracks a 32-bit instruction into register addresses, a sign-extended
// immediate, and the datapath control word consumed by the EX stage.
// Illegal/unknown opcodes decode to a NOP (no arch state change).
`include "rv32i_defs.vh"
`default_nettype none

module decoder (
    input  wire [31:0] instr,

    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,

    output reg  [31:0] imm,
    output reg  [3:0]  alu_op,
    output reg         alu_src_a,   // A_RS1 / A_PC
    output reg         alu_src_b,   // B_RS2 / B_IMM
    output reg  [1:0]  result_sel,  // RES_ALU / RES_MEM / RES_PC4
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         is_halt      // ECALL/EBREAK -> stop the CPU
);
    wire [6:0] opcode = instr[6:0];
    wire [6:0] funct7 = instr[31:25];

    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];

    // ---- Immediate variants (RV32I) ----
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                         instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                         instr[20], instr[30:21], 1'b0};

    // ---- ALU op for OP / OP-IMM from funct3 (+ funct7[5] for SUB/SRA) ----
    // instr[30] selects SUB (from ADD) and SRA (from SRL). For OP-IMM only
    // the shift-right form (funct3==101) consults instr[30]; ADDI never subs.
    reg [3:0] alu_op_arith;
    always @(*) begin
        case (funct3)
            3'b000: alu_op_arith = (opcode == `OPC_OP && instr[30]) ? `ALU_SUB : `ALU_ADD;
            3'b001: alu_op_arith = `ALU_SLL;
            3'b010: alu_op_arith = `ALU_SLT;
            3'b011: alu_op_arith = `ALU_SLTU;
            3'b100: alu_op_arith = `ALU_XOR;
            3'b101: alu_op_arith = instr[30] ? `ALU_SRA : `ALU_SRL;
            3'b110: alu_op_arith = `ALU_OR;
            3'b111: alu_op_arith = `ALU_AND;
            default: alu_op_arith = `ALU_ADD;
        endcase
    end

    always @(*) begin
        // Safe NOP defaults (prevents latch inference; unknown opcodes are NOPs).
        imm        = 32'd0;
        alu_op     = `ALU_ADD;
        alu_src_a  = `A_RS1;
        alu_src_b  = `B_IMM;
        result_sel = `RES_ALU;
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        is_branch  = 1'b0;
        is_jal     = 1'b0;
        is_jalr    = 1'b0;
        is_halt    = 1'b0;

        case (opcode)
            `OPC_LUI: begin
                imm = imm_u; alu_op = `ALU_BSEL; alu_src_b = `B_IMM;
                reg_write = 1'b1;
            end
            `OPC_AUIPC: begin
                imm = imm_u; alu_op = `ALU_ADD;
                alu_src_a = `A_PC; alu_src_b = `B_IMM;
                reg_write = 1'b1;
            end
            `OPC_JAL: begin
                imm = imm_j; result_sel = `RES_PC4;
                reg_write = 1'b1; is_jal = 1'b1;
            end
            `OPC_JALR: begin
                imm = imm_i; result_sel = `RES_PC4;
                reg_write = 1'b1; is_jalr = 1'b1;
            end
            `OPC_BRANCH: begin
                imm = imm_b; is_branch = 1'b1;
                alu_src_b = `B_RS2;   // comparison is on rs1 vs rs2
            end
            `OPC_LOAD: begin
                imm = imm_i; alu_op = `ALU_ADD; alu_src_b = `B_IMM;
                result_sel = `RES_MEM; reg_write = 1'b1; mem_read = 1'b1;
            end
            `OPC_STORE: begin
                imm = imm_s; alu_op = `ALU_ADD; alu_src_b = `B_IMM;
                mem_write = 1'b1;
            end
            `OPC_OPIMM: begin
                imm = imm_i; alu_op = alu_op_arith;
                alu_src_b = `B_IMM; reg_write = 1'b1;
            end
            `OPC_OP: begin
                alu_op = alu_op_arith;
                alu_src_b = `B_RS2; reg_write = 1'b1;
            end
            `OPC_MISCMEM: begin
                // FENCE / FENCE.I -> NOP on this single-hart in-order core.
            end
            `OPC_SYSTEM: begin
                // ECALL/EBREAK -> halt. (No CSRs implemented in base RV32I here.)
                is_halt = 1'b1;
            end
            default: begin
                // Unknown opcode: NOP (defaults already set).
            end
        endcase
    end
endmodule

`default_nettype wire
