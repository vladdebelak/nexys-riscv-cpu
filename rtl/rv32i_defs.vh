// rv32i_defs.vh — shared constants for the RV32I core
// Verilog-2001 header (include with `include "rv32i_defs.vh"`).
// Kept as localparam-style `define constants so leaf modules stay standalone.
`ifndef RV32I_DEFS_VH
`define RV32I_DEFS_VH

// ---- Opcodes (instr[6:0]) ----
`define OPC_LUI     7'b0110111
`define OPC_AUIPC   7'b0010111
`define OPC_JAL     7'b1101111
`define OPC_JALR    7'b1100111
`define OPC_BRANCH  7'b1100011
`define OPC_LOAD    7'b0000011
`define OPC_STORE   7'b0100011
`define OPC_OPIMM   7'b0010011
`define OPC_OP      7'b0110011
`define OPC_MISCMEM 7'b0001111  // FENCE (treated as NOP)
`define OPC_SYSTEM  7'b1110011  // ECALL/EBREAK (treated as HALT)

// ---- ALU operation select (alu_op) ----
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_SLL   4'd2
`define ALU_SLT   4'd3
`define ALU_SLTU  4'd4
`define ALU_XOR   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_OR    4'd8
`define ALU_AND   4'd9
`define ALU_BSEL  4'd10  // pass operand B unchanged (for LUI)

// ---- Writeback result select (result_sel) ----
`define RES_ALU   2'b00
`define RES_MEM   2'b01
`define RES_PC4   2'b10  // PC+4 for JAL/JALR link

// ---- ALU operand-A select ----
`define A_RS1     1'b0
`define A_PC      1'b1   // for AUIPC

// ---- ALU operand-B select ----
`define B_RS2     1'b0
`define B_IMM     1'b1

// ---- funct3: branches ----
`define F3_BEQ    3'b000
`define F3_BNE    3'b001
`define F3_BLT    3'b100
`define F3_BGE    3'b101
`define F3_BLTU   3'b110
`define F3_BGEU   3'b111

// ---- funct3: loads/stores (width/sign) ----
`define F3_B      3'b000  // byte  (signed load)
`define F3_H      3'b001  // half  (signed load)
`define F3_W      3'b010  // word
`define F3_BU     3'b100  // byte  (unsigned load)
`define F3_HU     3'b101  // half  (unsigned load)

`endif // RV32I_DEFS_VH
