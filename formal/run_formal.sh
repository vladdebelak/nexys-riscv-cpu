#!/bin/bash
# run_formal.sh — assertion-based verification of the RV32I core under xsim.
#
# Runs the SVA property modules (formal/sva_*.sv) two ways:
#   1) constrained-random ALU stream (formal/tb_alu_formal.sv)
#   2) the full core executing test1.s, with the properties bound in
#      (formal/binds.sv)
# Any property violation prints "ASSERT-FAIL ..."; this script fails if it sees
# one (or if a run doesn't reach its DONE marker).
#
# NOTE: this host has no SymbiYosys, so these are simulation-checked (bounded,
# stimulus-driven) — strong regression checks, but not exhaustive proofs. The
# SVA is written in the sby-supported subset so `make`-ing it under SymbiYosys
# elsewhere yields true BMC with no changes.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v xvlog >/dev/null 2>&1; then
  for d in /c/Xilinx/Vivado/*/bin /tools/Xilinx/Vivado/*/bin; do
    [ -x "$d/xvlog" ] && export PATH="$d:$PATH" && break
  done
fi
command -v xvlog >/dev/null 2>&1 || { echo "xvlog not found — add Vivado bin to PATH" >&2; exit 1; }

bd="$root/build/formal"; mkdir -p "$bd"; cd "$bd"
rc=0

echo "=== [1/2] random ALU + SVA ==="
xvlog -i "$root/rtl" -sv "$root/rtl/alu.v" "$root/formal/sva_alu.sv" "$root/formal/tb_alu_formal.sv" \
    2>&1 | grep -iE "error" | grep -vi webtalk
xelab tb_alu_formal -s f_alu --timescale 1ns/1ps 2>&1 | grep -iE "error" | grep -vi webtalk
alu_out="$(xsim f_alu -R 2>&1)"
echo "$alu_out" | grep -E "FORMAL-ALU-DONE|ASSERT-FAIL"
echo "$alu_out" | grep -q "FORMAL-ALU-DONE" || { echo "  [!] ALU run did not complete"; rc=1; }
echo "$alu_out" | grep -q "ASSERT-FAIL"     && { echo "  [!] ALU assertion(s) failed"; rc=1; }

echo "=== [2/2] core + bound SVA on test1.s ==="
python "$root/scripts/asm.py" "$root/sim/programs/test1.s" -o "$bd/program.hex" >/dev/null
xvlog -i "$root/rtl" -sv \
    "$root"/rtl/alu.v "$root"/rtl/regfile.v "$root"/rtl/decoder.v \
    "$root"/rtl/imem.v "$root"/rtl/dmem.v "$root"/rtl/rv32i_core.v \
    "$root"/formal/sva_alu.sv "$root"/formal/sva_regfile.sv "$root"/formal/sva_core.sv \
    "$root"/formal/binds.sv "$root"/sim/tb_core.v \
    2>&1 | grep -iE "error" | grep -vi webtalk
xelab tb_core -s f_core --timescale 1ns/1ps 2>&1 | grep -iE "error" | grep -vi webtalk
core_out="$(xsim f_core -R 2>&1)"
echo "$core_out" | grep -E "RESULT|ASSERT-FAIL|halted"
echo "$core_out" | grep -q "RESULT: PASS" || { echo "  [!] core program did not pass"; rc=1; }
echo "$core_out" | grep -q "ASSERT-FAIL"  && { echo "  [!] core assertion(s) failed"; rc=1; }

echo
if [ $rc -eq 0 ]; then echo "FORMAL: PASS (no assertion violations)"; else echo "FORMAL: FAIL"; fi
exit $rc
