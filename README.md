# nexys-riscv-cpu

A 3-stage pipelined **RV32I** CPU for the Digilent **Nexys A7-100T**
(Xilinx Artix-7 `XC7A100T`). Written in portable Verilog-2001, verified with
Vivado `xsim`, and synthesized clean for the board.

This repo also **logs its own design process** — every RTL edit, test run,
bug, and synthesis run — as data for an academic write-up on agentic
LLM-assisted FPGA/CPU design. See [Design log](#design-log).

## Status

| Milestone | State |
|---|---|
| ALU + register file (unit tests) | ✅ pass under xsim |
| 3-stage pipelined core | ✅ integration test passes |
| Full RV32I base integer ISA | ✅ (see [ISA support](#isa-support)) |
| Nexys A7 top (MMCM + reset sync) + XDC | ✅ synthesizes, timing met |
| Place & route + **bitstream** | ✅ routed, DRC clean, `.bit` built |
| SVA assertion-based verification | ✅ 19 properties pass |
| On-hardware bring-up | ⏳ not yet run |

**Latest synthesis** (Vivado 2020.2, `xc7a100tcsg324-1`, LED-counter workload):
819 LUTs (1.3%), 159 FF, 6.5 BRAM tiles, 0 DSP. All timing met at the 25 MHz
CPU clock (post-synth WNS +26.8 ns → ~76 MHz Fmax headroom).

## Architecture at a glance

```
        IF                    ID / EX                        MEM / WB
   ┌───────────┐        ┌────────────────────┐        ┌────────────────────┐
   │  PC  ─► imem(sync) │ decode + regfile RD │        │  dmem(sync) read   │
   │           │──instr─►│ +WB→EX forwarding  │──────► │  load format       │
   │  +4 / redirect ◄────│ ALU / branch / addr│  reg   │  result mux → RF WR │
   └───────────┘  target └────────────────────┘  write └────────────────────┘
```

- **Data hazards**: a single **WB→EX forwarding** path. In a 3-stage pipeline
  the only RAW distance that races the register file is 1; distance ≥2 is
  already committed. Because load data is a registered BRAM output that is
  stable for the whole MEM/WB cycle, **loads forward with no stall**.
- **Control hazards**: branches/jumps resolve in EX → exactly **one** shadow
  instruction is squashed (1-cycle penalty) and the PC is redirected.
- **I/O**: a memory-mapped 16-bit LED register (`0x0000_1000`) drives LD0–LD15;
  `ECALL`/`EBREAK` halt the core.

Full details, timing diagrams, and the memory map are in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Repository layout

```
rtl/                 synthesizable Verilog
  rv32i_defs.vh        opcode/ALU/control constants
  alu.v regfile.v      datapath leaf modules
  decoder.v            instruction decode + immediate generation
  imem.v dmem.v        synchronous BRAM models (byte-enabled dmem)
  rv32i_core.v         the 3-stage pipeline
  rv32i_top.v          Nexys A7 wrapper (MMCM 100→25 MHz, reset sync, LEDs)
constraints/
  nexys_a7_100t.xdc    pin + timing constraints
sim/
  tb_alu.v tb_regfile.v   self-checking unit tests
  tb_core.v tb_led.v      integration tests (run a program, check LEDs)
  programs/*.s / *.hex    test programs + assembled images
synth/
  synth.tcl            non-project synthesis flow
  impl.tcl             place & route + bitstream
formal/
  sva_*.sv             SVA property modules (ALU, regfile, core invariants)
  binds.sv             bind the properties onto the RTL
  tb_alu_formal.sv     constrained-random ALU driver
  run_formal.sh        run the assertion-based verification under xsim
scripts/
  asm.py               tiny two-pass RV32I assembler (.s → .hex)
  run_sim.sh           compile+run one testbench under xsim
  run_vivado.sh        run a Vivado tcl, summarize errors/timing
  labjournal.py        append-only process logger  (see logs/)
logs/                  the design-process dataset (JSONL) + SCHEMA.md
```

## Building & testing

Prerequisites: **Vivado 2020.2+** (provides `xvlog`/`xelab`/`xsim` and
`vivado`) and **Python 3**. On this Windows host the working interpreter is
`python` (the `python3` alias is a Store stub); adjust to taste.

### Simulate

```bash
# unit tests
scripts/run_sim.sh sim/tb_alu.v
scripts/run_sim.sh sim/tb_regfile.v

# integration: assemble a program and run it on the full core
scripts/run_sim.sh sim/tb_core.v sim/programs/test1.s      # self-check → led=0x0ACE
scripts/run_sim.sh sim/tb_led.v  sim/programs/led_counter.s
```

`test1.s` is a self-checking exerciser: every check branches to `fail` on
mismatch, and the program writes `0x0ACE` to the LEDs only if **all** checks
pass (`0x0BAD` otherwise) — so the CPU proves its own correctness and the
testbench just reads the LEDs.

### Assemble a program

```bash
python scripts/asm.py sim/programs/test1.s -o build/test1.hex
```

The assembler covers the RV32I base set plus pseudo-ops (`li`, `mv`, `j`,
`ret`, `beqz`, `nop`, …). See its header for syntax.

### Formal / assertion-based verification

```bash
formal/run_formal.sh      # 19 SVA properties: ALU ops, regfile x0, core invariants
```

The properties (`formal/sva_*.sv`) are attached to the RTL with `bind`
(`formal/binds.sv`), so the RTL stays pure Verilog. They cover every ALU
operation (checked against 200k random vectors), `x0` reading zero, and the
core's control invariants (halt is sticky, a taken branch squashes its shadow,
a squashed slot has no side effects, and the memory-mapped LED decode).

They are written in the SymbiYosys-supported SVA subset, so they run as **true
BMC** wherever `sby` is installed. This host has no SymbiYosys, so `run_formal.sh`
runs them under Vivado `xsim` as **assertion-based verification** — bounded,
stimulus-driven checks (strong regression coverage, not exhaustive proofs).

### Synthesize for the board

```bash
scripts/run_vivado.sh synth/synth.tcl      # → build/synth/*.rpt
```

By default it bakes `sim/programs/led_counter.hex` into the instruction BRAM
(an all-NOP image would let synthesis prune the whole core). To run on
hardware you would continue to place-and-route and generate a bitstream, then
program the Nexys A7.

### On the board

`synth/impl.tcl` runs place & route and writes `build/impl/rv32i_top.bit`;
`scripts/program.tcl` flashes it to a connected board over JTAG. For what the
LEDs mean once it's running — the memory-mapped LED trick, the self-test's
frozen `0x0ACE` pass pattern vs. the counter's live display, and how to swap
the program — see **[`docs/HARDWARE_DEMOS.md`](docs/HARDWARE_DEMOS.md)**.

## ISA support

All of **RV32I base integer**:

- `LUI`, `AUIPC`
- `JAL`, `JALR`
- `BEQ` `BNE` `BLT` `BGE` `BLTU` `BGEU`
- `LB` `LH` `LW` `LBU` `LHU`, `SB` `SH` `SW`
- `ADDI` `SLTI` `SLTIU` `XORI` `ORI` `ANDI` `SLLI` `SRLI` `SRAI`
- `ADD` `SUB` `SLL` `SLT` `SLTU` `XOR` `SRL` `SRA` `OR` `AND`
- `FENCE` (NOP on this single-hart core), `ECALL`/`EBREAK` (halt)

No CSRs, traps, or M/A/F extensions (out of scope for the base target).

## Design log

`logs/*.jsonl` records the build process — iterations, bugs, formal runs, and
synth/impl metrics — appended by `scripts/labjournal.py`. `logs/SCHEMA.md`
documents every field. This is the dataset for the paper, not just changelog
noise; see `CLAUDE.md` for the (self-applied) logging conventions.
