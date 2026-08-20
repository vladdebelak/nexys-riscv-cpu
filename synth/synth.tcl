# synth/synth.tcl — out-of-context-free synthesis of rv32i_top for the
# Nexys A7-100T. Run via:  scripts/run_vivado.sh synth/synth.tcl
# (from the repo root). Reports land in build/synth/ (git-ignored).

set part   xc7a100tcsg324-1
set topmod rv32i_top
set outdir build/synth
# Program image loaded into the instruction BRAM. Without a real workload the
# LEDs are constant and synthesis prunes the whole core, so we bake in the
# LED-counter demo (override on the command line if desired).
set prog   sim/programs/led_counter.hex
file mkdir $outdir

# ---- read design ----
read_verilog rtl/alu.v
read_verilog rtl/regfile.v
read_verilog rtl/decoder.v
read_verilog rtl/imem.v
read_verilog rtl/dmem.v
read_verilog rtl/rv32i_core.v
read_verilog rtl/rv32i_top.v
read_xdc     constraints/nexys_a7_100t.xdc

# ---- synthesize ----
# -include_dirs rtl so `include "rv32i_defs.vh"` resolves.
synth_design -top $topmod -part $part -include_dirs rtl \
    -generic PROG_HEX=$prog -flatten_hierarchy rebuilt

# ---- reports ----
report_utilization      -file $outdir/utilization.rpt
report_timing_summary   -file $outdir/timing_summary.rpt -max_paths 10
report_clocks           -file $outdir/clocks.rpt
write_checkpoint -force  $outdir/post_synth.dcp

puts "SYNTH_DONE utilization+timing written to $outdir"
