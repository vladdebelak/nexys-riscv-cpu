// alu.v — RV32I arithmetic/logic unit (pure combinational).
// One 4-bit op select drives all base-integer datapath operations.
`include "rv32i_defs.vh"
`default_nettype none

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] y,
    output wire        zero    // y == 0, handy for reuse
);
    // Shift amount is the low 5 bits of b (RV32I: SLL/SRL/SRA by reg or imm).
    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (op)
            `ALU_ADD : y = a + b;
            `ALU_SUB : y = a - b;
            `ALU_SLL : y = a << shamt;
            `ALU_SLT : y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            `ALU_SLTU: y = (a < b) ? 32'd1 : 32'd0;
            `ALU_XOR : y = a ^ b;
            `ALU_SRL : y = a >> shamt;
            `ALU_SRA : y = $signed(a) >>> shamt;
            `ALU_OR  : y = a | b;
            `ALU_AND : y = a & b;
            `ALU_BSEL: y = b;               // LUI: forward the U-immediate
            default  : y = 32'd0;           // safe default, avoids latch
        endcase
    end

    assign zero = (y == 32'd0);
endmodule

`default_nettype wire
