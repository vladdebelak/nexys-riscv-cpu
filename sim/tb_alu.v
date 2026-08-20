// tb_alu.v — self-checking unit test for the ALU.
// Exercises every op with directed vectors incl. sign/overflow/shift edges.
`include "rv32i_defs.vh"
`timescale 1ns/1ps

module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] y;
    wire        zero;

    integer errors = 0;
    integer checks = 0;

    alu dut (.a(a), .b(b), .op(op), .y(y), .zero(zero));

    task check;
        input [255:0] name;
        input [31:0]  exp;
        begin
            #1; // let combinational logic settle
            checks = checks + 1;
            if (y !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: a=%h b=%h op=%0d -> y=%h, expected %h",
                          name, a, b, op, y, exp);
            end
        end
    endtask

    initial begin
        // ADD / SUB
        a=32'd10;            b=32'd15;            op=`ALU_ADD;  check("add",  32'd25);
        a=32'hFFFFFFFF;      b=32'd1;             op=`ALU_ADD;  check("add-wrap", 32'd0);
        a=32'd15;            b=32'd40;            op=`ALU_SUB;  check("sub-neg", -32'sd25);
        // SLL / SRL / SRA
        a=32'h0000_0001;     b=32'd31;            op=`ALU_SLL;  check("sll", 32'h8000_0000);
        a=32'h8000_0000;     b=32'd4;             op=`ALU_SRL;  check("srl", 32'h0800_0000);
        a=32'h8000_0000;     b=32'd4;             op=`ALU_SRA;  check("sra", 32'hF800_0000);
        a=32'hFFFF_FFFF;     b=32'd35;            op=`ALU_SLL;  check("sll-shamt-mask", 32'hFFFF_FFF8); // shamt=3
        // SLT / SLTU
        a=-32'sd1;           b=32'd1;             op=`ALU_SLT;  check("slt-signed", 32'd1);
        a=32'hFFFF_FFFF;     b=32'd1;             op=`ALU_SLTU; check("sltu-unsigned", 32'd0);
        a=32'd5;             b=32'd5;             op=`ALU_SLT;  check("slt-eq", 32'd0);
        // Logical
        a=32'hF0F0_F0F0;     b=32'h0FF0_0FF0;     op=`ALU_XOR;  check("xor", 32'hFF00_FF00);
        a=32'hF0F0_0000;     b=32'h0000_0F0F;     op=`ALU_OR;   check("or",  32'hF0F0_0F0F);
        a=32'hFF00_FF00;     b=32'h0F0F_0F0F;     op=`ALU_AND;  check("and", 32'h0F00_0F00);
        // BSEL (LUI)
        a=32'hDEAD_BEEF;     b=32'h1234_5000;     op=`ALU_BSEL; check("bsel", 32'h1234_5000);
        // zero flag
        a=32'd7;             b=32'd7;             op=`ALU_SUB;  check("sub-zero", 32'd0);
        #1;
        if (zero !== 1'b1) begin
            errors = errors + 1; $display("FAIL: zero flag not set on y==0");
        end

        $display("ALU tests: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end
endmodule
