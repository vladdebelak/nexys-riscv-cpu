// tb_core.v — integration test: run a real program on the full core.
// Loads a hex program into the core's instruction memory (via hierarchical
// $readmemh; path from +HEX plusarg), releases reset, and runs until the core
// halts (ECALL) or a timeout. The program is self-checking and signals its
// verdict on the memory-mapped LEDs: 0x0ACE = pass, 0x0BAD = fail.
`timescale 1ns/1ps

module tb_core;
    reg clk = 0;
    reg rst_n = 0;
    wire [15:0] led;
    wire        halted;

    localparam integer TIMEOUT = 200000;   // cycles

    rv32i_core #(
        .IMEM_AW(12), .DMEM_AW(12),
        .IMEM_INIT(""), .DMEM_INIT(""),
        .RESET_PC(32'h0000_0000), .LED_ADDR(32'h0000_1000)
    ) dut (
        .clk(clk), .rst_n(rst_n), .led(led), .halted(halted)
    );

    always #5 clk = ~clk;   // 100 MHz

    reg [8*256-1:0] hexfile;
    integer cyc = 0;

    initial begin
        if (!$value$plusargs("HEX=%s", hexfile))
            hexfile = "program.hex";
        // Load program into imem (hierarchical); wait a delta so imem's own
        // initial (NOP fill) has completed first.
        #1;
        $readmemh(hexfile, dut.u_imem.mem);
        $display("loaded program: %0s", hexfile);

        // hold reset for a few cycles
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
    end

    // cycle counter + timeout guard
    always @(posedge clk) begin
        if (rst_n) cyc = cyc + 1;
        if (cyc > TIMEOUT) begin
            $display("TIMEOUT after %0d cycles (led=%h, halted=%b)", cyc, led, halted);
            $display("RESULT: FAIL");
            $finish;
        end
    end

    // finish shortly after halt so LED write settles
    initial begin
        wait (halted === 1'b1);
        @(posedge clk);
        $display("core halted at cycle %0d, led = 0x%h", cyc, led);
        if (led === 16'h0ACE)      $display("RESULT: PASS");
        else if (led === 16'h0BAD) $display("self-check FAILED in program (led=0x0BAD)");
        else                       $display("unexpected led value 0x%h", led);
        if (led !== 16'h0ACE)      $display("RESULT: FAIL");
        $finish;
    end
endmodule
