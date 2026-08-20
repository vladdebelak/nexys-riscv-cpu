// sva_regfile.sv — x0 invariant for the register file.
// x0 must always read as zero regardless of any write to address 0.
module sva_regfile_props (
    input wire        clk,
    input wire [4:0]  rs1_addr,
    input wire [31:0] rs1_data,
    input wire [4:0]  rs2_addr,
    input wire [31:0] rs2_data
);
    X0_RS1: assert property (@(posedge clk) rs1_addr==5'd0 |-> rs1_data==32'd0)
        else $display("ASSERT-FAIL X0_RS1 data=%h", rs1_data);
    X0_RS2: assert property (@(posedge clk) rs2_addr==5'd0 |-> rs2_data==32'd0)
        else $display("ASSERT-FAIL X0_RS2 data=%h", rs2_data);
endmodule
