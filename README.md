# nexys-riscv-cpu

A 3-stage pipelined RV32I CPU, targeting the Digilent Nexys A7-100T
(Xilinx Artix-7 XC7A100T) FPGA board.

## Target spec

- **ISA**: RV32I (base integer, 32-bit registers/instructions/datapath)
- **Pipeline**: 3 stages (fetch, decode/execute, memory/writeback — exact
  split TBD as the design progresses)
- **Board**: Nexys A7-100T

## Process logging

This project logs its own design process (iterations, bugs, formal runs,
synth/impl metrics, session cost) for an academic write-up on agentic
LLM-assisted FPGA/CPU design. See `CLAUDE.md` for the logging conventions
and `logs/SCHEMA.md` for the field reference.
