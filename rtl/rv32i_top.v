// rv32i_top.v — Nexys A7-100T board wrapper for the RV32I core.
//
// Clocking: the 100 MHz board oscillator is divided to a 25 MHz CPU clock by
// an MMCM (MMCME2_BASE primitive, VCO = 1000 MHz). Running the CPU at 25 MHz
// gives the long IF->decode->regfile->ALU->dmem combinational path generous
// timing margin without needing to pipeline it further (a deliberate area/
// simplicity trade for this teaching core).
//
// Reset: CPU_RESETN is an active-low pushbutton. It is combined with MMCM
// `locked` and passed through a reset synchronizer (async assert, sync
// release) so the core leaves reset cleanly aligned to the CPU clock.
//
// Output: the core's memory-mapped LED register drives LD0..LD15.
`default_nettype none

module rv32i_top #(
    parameter PROG_HEX = ""      // optional $readmemh image for the instruction BRAM
)(
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN, // active-low pushbutton
    output wire [15:0] LED
);
    // ---------------- clock generation (100 MHz -> 25 MHz) ----------------
    wire clk_fb, clk_fb_bufg;
    wire clk_cpu_unbuf, clk_cpu;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(10.000),      // 100 MHz
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.000),    // VCO = 100 * 10 / 1 = 1000 MHz
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(40.000),   // 1000 / 40 = 25 MHz
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE(0.000),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(CLK100MHZ),
        .CLKFBIN(clk_fb_bufg),
        .CLKFBOUT(clk_fb),
        .CLKFBOUTB(),
        .CLKOUT0(clk_cpu_unbuf),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(mmcm_locked),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    BUFG u_bufg_fb  (.I(clk_fb),        .O(clk_fb_bufg));
    BUFG u_bufg_cpu (.I(clk_cpu_unbuf), .O(clk_cpu));

    // ---------------- reset synchronizer (async assert, sync release) -----
    wire rst_n_async = CPU_RESETN & mmcm_locked;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync;

    always @(posedge clk_cpu or negedge rst_n_async) begin
        if (!rst_n_async) rst_sync <= 2'b00;
        else              rst_sync <= {rst_sync[0], 1'b1};
    end
    wire rst_n = rst_sync[1];

    // ---------------- core ----------------
    wire [15:0] led_core;
    wire        halted;

    rv32i_core #(
        .IMEM_AW(12), .DMEM_AW(12),
        .IMEM_INIT(PROG_HEX), .DMEM_INIT(""),
        .RESET_PC(32'h0000_0000), .LED_ADDR(32'h0000_1000)
    ) u_core (
        .clk(clk_cpu),
        .rst_n(rst_n),
        .led(led_core),
        .halted(halted)
    );

    assign LED = led_core;
endmodule

`default_nettype wire
