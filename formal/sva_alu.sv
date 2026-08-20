// sva_alu.sv — SVA correctness properties for the ALU.
// The ALU is combinational, so each property is a same-cycle implication
// sampled on the clock supplied by the bind/parent (skill pitfall #1). A
// reset input gates evaluation so reset-time X inputs don't trip assertions.
// Written in the SymbiYosys-supported SVA subset (|->, no s_eventually) so it
// can also run as true BMC where `sby` is available; here it runs under xsim.
`include "rv32i_defs.vh"

module sva_alu_props (
    input wire        clk,
    input wire        rst_n,
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0]  op,
    input wire [31:0] y,
    input wire        zero
);
    // Expected SRA in a *signed* context so `>>>` stays arithmetic. Computing
    // it inline against the unsigned `y` would make Verilog treat the whole
    // expression as unsigned and turn `>>>` into a logical shift.
    wire signed [31:0] sra_exp = $signed(a) >>> b[4:0];

    A_ADD : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_ADD  |-> y == (a + b))
        else $display("ASSERT-FAIL A_ADD  a=%h b=%h y=%h", a, b, y);
    A_SUB : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_SUB  |-> y == (a - b))
        else $display("ASSERT-FAIL A_SUB  a=%h b=%h y=%h", a, b, y);
    A_SLL : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_SLL  |-> y == (a << b[4:0]))
        else $display("ASSERT-FAIL A_SLL  a=%h b=%h y=%h", a, b, y);
    A_SLT : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_SLT  |-> y == (($signed(a) <  $signed(b)) ? 32'd1 : 32'd0))
        else $display("ASSERT-FAIL A_SLT  a=%h b=%h y=%h", a, b, y);
    A_SLTU: assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_SLTU |-> y == ((a < b) ? 32'd1 : 32'd0))
        else $display("ASSERT-FAIL A_SLTU a=%h b=%h y=%h", a, b, y);
    A_XOR : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_XOR  |-> y == (a ^ b))
        else $display("ASSERT-FAIL A_XOR  a=%h b=%h y=%h", a, b, y);
    A_SRL : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_SRL  |-> y == (a >> b[4:0]))
        else $display("ASSERT-FAIL A_SRL  a=%h b=%h y=%h", a, b, y);
    A_SRA : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_SRA  |-> y == sra_exp)
        else $display("ASSERT-FAIL A_SRA  a=%h b=%h y=%h exp=%h", a, b, y, sra_exp);
    A_OR  : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_OR   |-> y == (a | b))
        else $display("ASSERT-FAIL A_OR   a=%h b=%h y=%h", a, b, y);
    A_AND : assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_AND  |-> y == (a & b))
        else $display("ASSERT-FAIL A_AND  a=%h b=%h y=%h", a, b, y);
    A_BSEL: assert property (@(posedge clk) disable iff (!rst_n) op==`ALU_BSEL |-> y == b)
        else $display("ASSERT-FAIL A_BSEL a=%h b=%h y=%h", a, b, y);
    A_ZERO: assert property (@(posedge clk) disable iff (!rst_n) zero == (y == 32'd0))
        else $display("ASSERT-FAIL A_ZERO y=%h zero=%b", y, zero);
endmodule
