# synth/impl.tcl — place & route + bitstream for rv32i_top on the Nexys A7-100T.
# Picks up the post-synthesis checkpoint from synth/synth.tcl and runs the full
# implementation flow. Run via:  scripts/run_vivado.sh synth/impl.tcl
# (from the repo root, after synth/synth.tcl). Outputs land in build/impl/.

set outdir build/impl
file mkdir $outdir

# ---- load the synthesized netlist ----
open_checkpoint build/synth/post_synth.dcp

# ---- implementation ----
opt_design
place_design
phys_opt_design
route_design

# ---- post-route reports (this is the *real*, routed timing) ----
report_utilization     -file $outdir/utilization.rpt
report_timing_summary  -file $outdir/timing_summary.rpt -max_paths 10
report_power           -file $outdir/power.rpt
report_drc             -file $outdir/drc.rpt
write_checkpoint -force $outdir/post_route.dcp

# ---- bitstream ----
write_bitstream -force $outdir/rv32i_top.bit

puts "IMPL_DONE bitstream + reports written to $outdir"
