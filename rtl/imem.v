// imem.v — synchronous-read instruction memory (infers BRAM).
// Word-addressed internally; `addr` is a byte address (PC). One-cycle read
// latency: address presented on cycle N, instruction valid on cycle N+1 —
// this IS the IF/ID pipeline register for the fetch stage.
// Unwritten locations default to NOP (addi x0,x0,0) so runaway fetch is safe.
`default_nettype none

module imem #(
    parameter ADDR_WIDTH = 12,          // words = 2^ADDR_WIDTH (default 4K words = 16KB)
    parameter INIT_FILE  = ""
)(
    input  wire        clk,
    input  wire        en,
    input  wire [31:0] addr,            // byte address
    output reg  [31:0] rdata
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    (* ram_style = "block" *)
    reg [31:0] mem [0:DEPTH-1];

    wire [ADDR_WIDTH-1:0] widx = addr[ADDR_WIDTH+1:2];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h0000_0013;      // NOP
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (en)
            rdata <= mem[widx];
    end
endmodule

`default_nettype wire
