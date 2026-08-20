// regfile.v — 32x32 RV32I register file.
// Two combinational read ports, one synchronous write port.
// x0 is hardwired to zero (writes to it are ignored).
// Read-during-write returns the OLD value (write commits on the clock edge);
// the pipeline covers the same-cycle case with WB->EX forwarding upstream.
`default_nettype none

module regfile (
    input  wire        clk,
    // read port 1
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,
    // read port 2
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,
    // write port
    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);
    reg [31:0] xreg [1:31];   // x0 not stored; it is a constant zero

    // Combinational reads; x0 forced to zero.
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : xreg[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : xreg[rs2_addr];

    always @(posedge clk) begin
        if (we && (rd_addr != 5'd0))
            xreg[rd_addr] <= rd_data;
    end
endmodule

`default_nettype wire
