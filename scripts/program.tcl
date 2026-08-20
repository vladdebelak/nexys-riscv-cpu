# program.tcl — flash the built bitstream to a connected Nexys A7-100T over JTAG.
# Volatile SRAM configuration (lost on power-cycle). Run via:
#   scripts/run_vivado.sh scripts/program.tcl
# (from the repo root, after synth/impl.tcl has produced the .bit).

set bit build/impl/rv32i_top.bit
if {![file exists $bit]} {
    error "bitstream not found: $bit — run synth/synth.tcl then synth/impl.tcl first"
}

open_hw_manager
connect_hw_server
open_hw_target

set devs [get_hw_devices]
puts "JTAG_CHAIN: $devs"

# Pick the Artix-7 device (xc7a100t_0 on the Nexys A7-100T).
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { set dev [lindex $devs 0] }
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev

puts "PROGRAM_DONE device=$dev file=$bit"
close_hw_target
disconnect_hw_server
