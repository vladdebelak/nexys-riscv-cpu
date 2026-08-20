// tb_regfile.v — self-checking unit test for the register file.
// Verifies: x0 reads zero and ignores writes, normal write/read, dual read
// ports, and read-during-write returns the OLD value (edge-committed write).
`timescale 1ns/1ps

module tb_regfile;
    reg         clk = 0;
    reg  [4:0]  rs1_addr = 0, rs2_addr = 0, rd_addr = 0;
    reg         we = 0;
    reg  [31:0] rd_data = 0;
    wire [31:0] rs1_data, rs2_data;

    integer errors = 0;
    integer checks = 0;

    regfile dut (
        .clk(clk),
        .rs1_addr(rs1_addr), .rs1_data(rs1_data),
        .rs2_addr(rs2_addr), .rs2_data(rs2_data),
        .we(we), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    always #5 clk = ~clk;

    // Synchronous write helper: drive inputs, pulse one clock.
    task wr;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            we = 1'b1; rd_addr = addr; rd_data = data;
            @(negedge clk);
            we = 1'b0;
        end
    endtask

    task expect1;
        input [255:0] name;
        input [4:0]  addr;
        input [31:0] exp;
        begin
            rs1_addr = addr; #1;
            checks = checks + 1;
            if (rs1_data !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s]: x%0d -> %h, expected %h", name, addr, rs1_data, exp);
            end
        end
    endtask

    initial begin
        // Write a few registers.
        wr(5'd1,  32'hDEAD_BEEF);
        wr(5'd2,  32'h0000_0042);
        wr(5'd31, 32'hFFFF_FFFF);

        expect1("x1",  5'd1,  32'hDEAD_BEEF);
        expect1("x2",  5'd2,  32'h0000_0042);
        expect1("x31", 5'd31, 32'hFFFF_FFFF);

        // x0 must stay zero even after an attempted write.
        wr(5'd0, 32'hAAAA_AAAA);
        expect1("x0-const-zero", 5'd0, 32'd0);

        // Dual read ports read independently.
        rs1_addr = 5'd1; rs2_addr = 5'd2; #1;
        checks = checks + 1;
        if (rs1_data !== 32'hDEAD_BEEF || rs2_data !== 32'h0000_0042) begin
            errors = errors + 1;
            $display("FAIL dual-port: rs1=%h rs2=%h", rs1_data, rs2_data);
        end

        // Read-during-write returns OLD value (write commits on edge).
        @(negedge clk);
        we = 1'b1; rd_addr = 5'd1; rd_data = 32'h1234_5678;
        rs1_addr = 5'd1; #1;
        checks = checks + 1;
        if (rs1_data !== 32'hDEAD_BEEF) begin
            errors = errors + 1;
            $display("FAIL read-during-write: got %h, expected old DEADBEEF", rs1_data);
        end
        @(negedge clk); we = 1'b0;
        expect1("x1-after-write", 5'd1, 32'h1234_5678);

        $display("REGFILE tests: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end
endmodule
