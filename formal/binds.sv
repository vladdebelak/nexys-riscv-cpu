// binds.sv — attach the SVA property modules to the RTL without touching it.
// Compiled alongside the design + a testbench so the assertions are active
// during simulation (and are `sby`-ready for true BMC elsewhere).

// Register file has its own clock -> bind directly.
bind regfile sva_regfile_props u_sva_rf (
    .clk(clk),
    .rs1_addr(rs1_addr), .rs1_data(rs1_data),
    .rs2_addr(rs2_addr), .rs2_data(rs2_data)
);

// ALU is combinational -> bind at the core, borrowing the core's clock and
// the nets wired to u_alu (zero is unconnected in the core, so reach into it).
bind rv32i_core sva_alu_props u_sva_alu (
    .clk(clk), .rst_n(rst_n),
    .a(alu_a), .b(alu_b), .op(alu_op), .y(alu_y),
    .zero(u_alu.zero)
);

// Core control/pipeline invariants -> bind at the core, internal signals.
bind rv32i_core sva_core_props u_sva_core (
    .clk(clk), .rst_n(rst_n),
    .halted(halted), .redirect(redirect), .flush_ex(flush_ex),
    .do_reg_write(do_reg_write), .do_mem_write(do_mem_write),
    .is_led(is_led), .dmem_be(dmem_be), .led(led)
);
