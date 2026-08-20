# Microarchitecture

A 3-stage in-order pipeline implementing the RV32I base integer ISA. The
design goal is a small, correct, teaching-grade core — clarity over peak
frequency — that fits comfortably on an Artix-7 and is easy to reason about
formally.

## Pipeline stages

| Stage | Work |
|---|---|
| **IF** | PC register drives the synchronous instruction BRAM (`imem`). The instruction appears one cycle later — the BRAM output register *is* the IF/ID pipeline register. |
| **ID / EX** | Decode, register-file read (with WB→EX forwarding), immediate generation, the ALU, branch/jump resolution, and data-memory address + store formatting. |
| **MEM / WB** | Capture the synchronous `dmem` read data, extract/extend loads, select the writeback value, and write the register file. |

The register file writes on the clock edge that ends MEM/WB and reads
combinationally in ID/EX.

## Cycle timing

Three instructions `I0, I1, I2` fetched back-to-back:

```
cycle:     C0     C1     C2     C3     C4
I0        IF     EX     WB
I1               IF     EX     WB
I2                      IF     EX     WB
```

- `id_pc` is the PC delayed one cycle so it lines up with the instruction that
  emerged from `imem`.
- `dmem` is addressed combinationally from the EX-stage ALU result, so a load's
  data is registered and available in the very next cycle (MEM/WB).

## Data hazards — one forwarding path, no stalls

The producer immediately ahead of the instruction in EX is in WB. It has
already computed its writeback value (`wb_data`) but has not yet committed it
to the register file (that happens on the edge ending this cycle). So EX reads
a stale register value and must be **forwarded** from WB:

```
fwd = wb_reg_write && wb_rd != x0 && wb_rd == ex_rsN
ex_operandN = fwd ? wb_data : regfile[rsN]
```

Why this single path is sufficient in a 3-stage pipeline:

- **Distance 1** (producer in WB, consumer in EX): handled by forwarding above.
- **Distance ≥2**: the producer already wrote the register file on an earlier
  edge; the combinational read returns the new value. No forwarding needed.

**Loads need no stall.** In a classic 5-stage pipeline a load-use hazard costs
a bubble because the load result isn't ready when the dependent reaches EX.
Here the load result is a *registered* BRAM output that is stable for the whole
MEM/WB cycle, and `wb_data` (including the formatted load) is combinationally
available that same cycle — exactly when the dependent instruction is in EX.
So the WB→EX path forwards load results too, at zero penalty.

## Control hazards — 1-cycle branch shadow

Branches and jumps resolve in EX. By then the sequential next instruction has
already been fetched (it is one stage behind). When EX asserts `redirect`:

1. `pc` is loaded with the target on the current edge.
2. `flush_ex` is registered so that next cycle the (wrong) shadow instruction
   in EX is squashed to a NOP — no register or memory write, no further
   redirect.

Net penalty: exactly one bubble per taken branch / jump. Targets:

- branch / `JAL`: `id_pc + imm`
- `JALR`: `(rs1 + imm) & ~1`

## Halt

`ECALL`/`EBREAK` set a sticky `halted` flag in EX. Once halted, the PC freezes
and the pipeline is squashed, so no further architectural state changes. The
`halted` output lets a testbench end cleanly. (There are no CSRs in this base
core, so system instructions are used purely as a stop signal.)

## Memory map

| Region | Address | Notes |
|---|---|---|
| Instruction memory | `0x0000_0000 …` | `imem`, 4K words (16 KB), synchronous read, NOP-filled. |
| Data memory | BRAM, byte-addressed | `dmem`, 4K words, per-byte write enables. |
| **LED register** | `0x0000_1000` | Memory-mapped 16-bit output. A store here writes LD0–LD15 (and is *not* written to `dmem`). |

The LED address is a parameter (`LED_ADDR`) on the core, as are the memory
sizes and the reset PC.

## Decode & immediates

`decoder.v` cracks the instruction into register indices, a sign-extended
immediate (I/S/B/U/J variants), and a control word: `alu_op`, operand selects,
`result_sel` (ALU / MEM / PC+4), and the write/branch/jump/halt flags. Unknown
opcodes decode to a NOP (all control de-asserted), which also prevents latch
inference. The ALU is a single 4-bit-op combinational block covering
ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND plus a "pass-B" mode for `LUI`.

## Clocking & reset (board)

`rv32i_top.v` uses an `MMCME2_BASE` primitive (VCO 1000 MHz) to derive a
**25 MHz** CPU clock from the 100 MHz board oscillator. Running the CPU slower
than the fabric gives the long
`imem → decode → regfile → forward → ALU → dmem` combinational path generous
timing margin without pipelining it further — a deliberate simplicity/area
trade for a teaching core. Reset is the active-low `CPU_RESETN` pushbutton
ANDed with MMCM `locked`, passed through a 2-FF reset synchronizer
(asynchronous assert, synchronous release) so the core leaves reset cleanly
aligned to the CPU clock.

## Toolchain notes

- **Verilog-2001** throughout (no SystemVerilog) for maximum compatibility with
  Vivado 2020.2 `xsim` and synthesis.
- Memories use `(* ram_style = "block" *)` and the standard synchronous
  read/write inference patterns, so they map to Artix-7 block RAM (no
  distributed-RAM blowup).
- `scripts/asm.py` is a minimal two-pass assembler used to produce test-program
  images; its pass-1 is size-aware because `li` can expand to two words
  (`lui`+`addi`).

## Verification

- **Unit**: `tb_alu` (15 directed vectors incl. sign/shift/overflow edges) and
  `tb_regfile` (x0 constant, dual read, read-during-write).
- **Integration**: `tb_core` runs `test1.s`, a self-checking exerciser that
  covers reg/imm ALU, shifts, SLT(U), every branch condition, `JAL`/`JALR`
  call+return, `AUIPC`, and byte/half/word load+store with sign/zero extension
  — including back-to-back dependencies and load-use (forwarding). It signals
  pass/fail on the LEDs.
- **Board demo**: `tb_led` runs `led_counter.s` and checks the LED counter
  advances.
- **Assertion-based / formal** (`formal/`): 19 SVA properties `bind`-attached to
  the RTL — every ALU op + zero flag (vs 200k random vectors), `x0` reads zero,
  and core control invariants (halt sticky, `redirect ⇒ flush` next cycle, a
  squashed EX slot performs no register/memory write, `is_led ⇒ dmem_be==0`, and
  the LED register only changes on a store to `LED_ADDR`). Written in the
  SymbiYosys SVA subset so they double as BMC where `sby` exists; run here as
  bounded simulation checks under `xsim`.

See `logs/` for the full per-iteration record, including a bug found during
bring-up (an assembler label-address off-by that a far `jal` exposed).
