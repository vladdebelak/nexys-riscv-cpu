#!/bin/bash
# run_sim.sh — compile + run one testbench under Vivado xsim (batch).
#
# Usage:
#   scripts/run_sim.sh sim/tb_alu.v
#   scripts/run_sim.sh sim/tb_core.v sim/programs/test1.s
#   scripts/run_sim.sh sim/tb_led.v  sim/programs/led_counter.s
#
# If a .s program is given it is assembled to build/sim/program.hex, which the
# core testbenches load by default ($readmemh of "program.hex" from the run
# dir). All xsim artifacts stay under build/sim/ (git-ignored).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tb="${1:?usage: run_sim.sh <tb.v> [program.s]}"
prog="${2:-}"

# Locate the Vivado xsim tools.
if ! command -v xvlog >/dev/null 2>&1; then
  for d in /c/Xilinx/Vivado/*/bin /tools/Xilinx/Vivado/*/bin; do
    [ -x "$d/xvlog" ] && export PATH="$d:$PATH" && break
  done
fi
command -v xvlog >/dev/null 2>&1 || { echo "xvlog not found — add Vivado bin to PATH" >&2; exit 1; }

builddir="$root/build/sim"
mkdir -p "$builddir"

if [ -n "$prog" ]; then
  python "$root/scripts/asm.py" "$root/$prog" -o "$builddir/program.hex" || exit 1
fi

tbmod="$(basename "$tb" .v)"
cd "$builddir"

xvlog -i "$root/rtl" \
  "$root"/rtl/alu.v "$root"/rtl/regfile.v "$root"/rtl/decoder.v \
  "$root"/rtl/imem.v "$root"/rtl/dmem.v "$root"/rtl/rv32i_core.v \
  "$root/$tb" 2>&1 | grep -iE "error" | grep -vi webtalk
xelab "$tbmod" -s sim_snap --timescale 1ns/1ps 2>&1 | grep -iE "error" | grep -vi webtalk
xsim sim_snap -R 2>&1 | grep -E "loaded|RESULT|FAIL|PASS|halted|increment|tests|TIMEOUT|checks"
