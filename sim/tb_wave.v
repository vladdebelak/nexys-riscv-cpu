// tb_wave.v — runs a short program and dumps a VCD of the key pipeline signals,
// for turning into a waveform figure (scripts/vcd2svg.py). Not a pass/fail test.
`timescale 1ns/1ps

module tb_wave;
    reg clk = 0, rst_n = 0;
    wire [15:0] led;
    wire        halted;

    rv32i_core #(.LED_ADDR(32'h0000_1000)) dut (
        .clk(clk), .rst_n(rst_n), .led(led), .halted(halted)
    );

    always #5 clk = ~clk;   // 10 ns period

    integer cyc = 0;
    reg [8*256-1:0] hexfile;

    initial begin
        if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "program.hex";
        #1; $readmemh(hexfile, dut.u_imem.mem);

        // Dump only the interesting scalars/buses (not the memory arrays).
        $dumpfile("wave.vcd");
        $dumpvars(0, clk, rst_n);
        $dumpvars(0, dut.pc, dut.id_pc, dut.instr,
                     dut.alu_a, dut.alu_b, dut.alu_y,
                     dut.redirect, dut.flush_ex,
                     dut.wb_reg_write, dut.wb_rd, dut.wb_data,
                     dut.halted, dut.led);

        rst_n = 0; repeat (3) @(posedge clk); rst_n = 1;
    end

    always @(posedge clk) begin
        if (rst_n) cyc = cyc + 1;
        if (halted || cyc > 40) begin
            @(posedge clk);
            $display("wavedemo done: cyc=%0d led=0x%h", cyc, led);
            $finish;
        end
    end
endmodule
