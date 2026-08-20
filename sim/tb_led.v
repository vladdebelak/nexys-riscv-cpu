// tb_led.v — checks a free-running program that drives the LEDs (no halt).
// Loads a hex program (from +HEX, default program.hex), runs, and verifies the
// memory-mapped LED counter actually advances 0 -> 1 -> 2 -> ... Passes when
// the LEDs reach TARGET distinct increasing values before the timeout.
`timescale 1ns/1ps

module tb_led;
    reg clk = 0, rst_n = 0;
    wire [15:0] led;
    wire        halted;

    localparam integer TARGET  = 5;        // observe this many increments
    localparam integer TIMEOUT = 2000000;  // cycles

    rv32i_core #(.LED_ADDR(32'h0000_1000)) dut (
        .clk(clk), .rst_n(rst_n), .led(led), .halted(halted)
    );

    always #5 clk = ~clk;

    reg [8*256-1:0] hexfile;
    integer cyc = 0;
    integer seen = 0;
    reg [15:0] last = 16'hFFFF;

    initial begin
        if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "program.hex";
        #1; $readmemh(hexfile, dut.u_imem.mem);
        $display("loaded program: %0s", hexfile);
        rst_n = 0; repeat (4) @(posedge clk); rst_n = 1;
    end

    always @(posedge clk) if (rst_n) begin
        cyc = cyc + 1;
        // count monotonic increments of the LED counter
        if (led != last) begin
            if (last != 16'hFFFF && led == (last + 16'd1)) begin
                seen = seen + 1;
                $display("  led increment #%0d: 0x%h at cycle %0d", seen, led, cyc);
            end
            last = led;
        end
        if (seen >= TARGET) begin
            $display("LED counter advanced %0d times.", seen);
            $display("RESULT: PASS");
            $finish;
        end
        if (cyc > TIMEOUT) begin
            $display("TIMEOUT: led=0x%h seen=%0d", led, seen);
            $display("RESULT: FAIL");
            $finish;
        end
    end
endmodule
