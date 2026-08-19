#!/bin/bash
# Run a Vivado Tcl script in batch mode and surface just the signal:
# errors, critical warnings, and (if present) a timing summary line --
# instead of dumping the full multi-thousand-line log.
#
# The full log is archived under build/vivado_logs/ regardless, so nothing
# is lost -- this just keeps what lands in the agent's/your terminal small
# enough to actually read.
#
# Usage:
#   scripts/run_vivado.sh build/synth.tcl
#   scripts/run_vivado.sh build/impl.tcl
#
# Prereq: `vivado` on PATH (source Xilinx's settings64.sh first, e.g.
#   source /tools/Xilinx/Vivado/2024.1/settings64.sh
# ), and TCL scripts should write their reports with `-file` so
# parse_vivado_reports.py has something to read afterward.
set -uo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <script.tcl>" >&2
  exit 1
fi

if ! command -v vivado >/dev/null 2>&1; then
  echo "vivado not on PATH -- source Xilinx's settings64.sh first" >&2
  exit 1
fi

tcl_script="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
log_dir="$root/build/vivado_logs"
mkdir -p "$log_dir"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
name="$(basename "$tcl_script" .tcl)"
log_file="$log_dir/${stamp}_${name}.log"
journal_file="$log_dir/${stamp}_${name}.jou"

echo "running: vivado -mode batch -source $tcl_script"
echo "full log: $log_file"

vivado -mode batch -nolog -nojournal \
  -source "$tcl_script" \
  -log "$log_file" -journal "$journal_file"
status=$?

echo
echo "=== summary (full log: $log_file) ==="
grep -nE '^(ERROR|CRITICAL WARNING):' "$log_file" || echo "no ERROR / CRITICAL WARNING lines"

if grep -q 'Timing constraints are not met' "$log_file"; then
  echo
  echo "TIMING NOT MET -- see report_timing_summary output in the log/rpt files"
fi

echo
if [ $status -eq 0 ]; then
  echo "vivado exited 0"
else
  echo "vivado exited $status"
fi

exit $status
