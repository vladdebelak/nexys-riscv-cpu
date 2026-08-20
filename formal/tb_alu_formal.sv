// tb_alu_formal.sv — constrained-random driver for the ALU with the SVA
// properties attached. Without a formal engine on this host, this exercises
// the full ALU op set against a large random-vector stream; any property
// violation prints "ASSERT-FAIL ..." (caught by run_formal.sh).
`timescale 1ns/1ps

module tb_alu_formal;
    reg         clk = 0;
    reg         rst_n = 1'b1;   // no reset needed for a pure-combinational DUT
    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] y;
    wire        zero;

    localparam integer N = 200000;

    alu dut (.a(a), .b(b), .op(op), .y(y), .zero(zero));
    sva_alu_props chk (.clk(clk), .rst_n(rst_n), .a(a), .b(b), .op(op), .y(y), .zero(zero));

    always #5 clk = ~clk;

    integer i;
    reg [31:0] r;
    initial begin
        a = 0; b = 0; op = 0;
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            a = $random;
            b = $random;
            r = $random;
            op = r % 11;                 // 0..10 -> all defined ALU ops
            // bias toward shift edge cases (shamt boundaries) sometimes
            if (r[31]) b[4:0] = r[4:0];
        end
        @(posedge clk); #1;
        $display("FORMAL-ALU-DONE checked %0d random vectors", N);
        $finish;
    end
endmodule
