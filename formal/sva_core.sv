// sva_core.sv — pipeline/control invariants for the 3-stage core.
// These are structural safety properties (hold for all inputs, not just the
// test programs): halt latching, branch-shadow squashing, and the
// memory-mapped-LED decode. Bound into rv32i_core (internal-signal access).
module sva_core_props (
    input wire        clk,
    input wire        rst_n,
    input wire        halted,
    input wire        redirect,
    input wire        flush_ex,
    input wire        do_reg_write,
    input wire        do_mem_write,
    input wire        is_led,
    input wire [3:0]  dmem_be,
    input wire [15:0] led
);
    // Halt is sticky: once halted, stays halted.
    HALT_STICKY: assert property (@(posedge clk) disable iff (!rst_n)
        halted |=> halted)
        else $display("ASSERT-FAIL HALT_STICKY");

    // A taken branch/jump this cycle squashes the shadow next cycle.
    REDIR_FLUSH: assert property (@(posedge clk) disable iff (!rst_n)
        redirect |=> flush_ex)
        else $display("ASSERT-FAIL REDIR_FLUSH");

    // A squashed EX slot (flushed shadow or halted) has no architectural effect.
    SQUASH_NOWR: assert property (@(posedge clk) disable iff (!rst_n)
        (flush_ex || halted) |-> (!do_reg_write && !do_mem_write))
        else $display("ASSERT-FAIL SQUASH_NOWR");

    // Memory-map exclusivity: a store to the LED address never writes dmem.
    LED_EXCL: assert property (@(posedge clk) disable iff (!rst_n)
        is_led |-> (dmem_be == 4'b0000))
        else $display("ASSERT-FAIL LED_EXCL be=%b", dmem_be);

    // The LED register changes only as a result of a store to LED_ADDR.
    LED_ONLY_ON_STORE: assert property (@(posedge clk) disable iff (!rst_n)
        (led != $past(led)) |-> $past(do_mem_write && is_led))
        else $display("ASSERT-FAIL LED_ONLY_ON_STORE led=%h", led);
endmodule
