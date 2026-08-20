// dmem.v — synchronous single-port data memory (infers BRAM).
// Word-addressed with per-byte write enables (for SB/SH/SW). One-cycle read
// latency: address presented in EX, data valid in MEM/WB. Read-first on a
// simultaneous R/W to the same word (only ever one memory op is in flight).
`default_nettype none

module dmem #(
    parameter ADDR_WIDTH = 12,
    parameter INIT_FILE  = ""
)(
    input  wire        clk,
    input  wire        en,
    input  wire [3:0]  we,              // per-byte write strobe
    input  wire [31:0] addr,            // byte address
    input  wire [31:0] wdata,           // pre-aligned (data replicated across lanes)
    output reg  [31:0] rdata
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    (* ram_style = "block" *)
    reg [31:0] mem [0:DEPTH-1];

    wire [ADDR_WIDTH-1:0] widx = addr[ADDR_WIDTH+1:2];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h0000_0000;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (en) begin
            if (we[0]) mem[widx][7:0]   <= wdata[7:0];
            if (we[1]) mem[widx][15:8]  <= wdata[15:8];
            if (we[2]) mem[widx][23:16] <= wdata[23:16];
            if (we[3]) mem[widx][31:24] <= wdata[31:24];
            rdata <= mem[widx];         // read-first
        end
    end
endmodule

`default_nettype wire
