# Agentic LLM-Assisted Design of an RV32I CPU — A Process Case Study

This document is the methods-and-results narrative for the accompanying
academic article on agentic, LLM-assisted FPGA/CPU design. It reconstructs, in
detail, how a complete RV32I processor went from a one-line spec to a verified
bitstream running on hardware inside a single working session, driven by an
LLM agent (Claude, via the Claude Code CLI) with a human operator supervising.

Everything below is grounded in the machine-generated process log the project
keeps of itself (`logs/*.jsonl`, schema in `logs/SCHEMA.md`) and in the git
history. Where a number is an estimate rather than a measurement, it is marked.

- **Design under study**: a 3-stage in-order RV32I core (`rtl/`), documented in
  [`ARCHITECTURE.md`](ARCHITECTURE.md).
- **Target**: Digilent Nexys A7-100T, Xilinx Artix-7 `XC7A100TCSG324-1`.
- **Result**: simulated, formally asserted, synthesized, placed-and-routed,
  and confirmed running on silicon (LED self-test latches `0x0ACE`).

---

## 1. Experimental setup

| Element | Detail |
|---|---|
| Agent | Claude Code CLI. Session began on **Claude Sonnet 5** (initial setup/preflight), switched mid-session via `/model` to **Claude Opus 4.8**, which did essentially all of the design work. |
| Domain scaffolding | A repository "skill" (`/fpga`) injected domain guidance at invocation: RTL patterns, a *sharp-edges* catalogue (CDC, latch inference, reset-release, sim/synth mismatch), validation rules, and an SVA/formal reference. This is retrieval-augmented domain expertise supplied as system context, not learned in-session. |
| Live docs | **Context7 MCP** server used to fetch up-to-date RISC-V ISA encoding (immediate bit-layout for B/J types) and Vivado references, rather than relying on training-data recall. |
| EDA tools | **Vivado 2020.2** — `xvlog`/`xelab`/`xsim` (simulation), `synth_design`, `opt/place/phys_opt/route`, `write_bitstream`, and the JTAG hardware manager. |
| Formal tools | **None installed.** SymbiYosys/Yosys/SMT solvers were absent on the host (probed and confirmed), which shaped the verification strategy (§8). |
| Language | Verilog-2001 for all RTL (2020.2 has SystemVerilog gaps); SVA (SystemVerilog) only in the non-synthesizable `formal/` collateral. |
| Host | Windows 11; Git Bash + PowerShell. Interpreter quirk: `python3` is a Microsoft Store stub, so `python` was used throughout — the kind of environment detail an agent must discover, not assume. |
| Version control | Git, auto-pushed to GitHub after every commit (a standing instruction), so the process log and the code advanced together. |

---

## 2. The agentic design loop

The session ran a **closed, self-instrumenting loop**. Each unit of work
followed the same cycle:

```
   ┌─────────────────────────────────────────────────────────────┐
   │  prompt / sub-goal                                           │
   │      │                                                       │
   │      ▼                                                       │
   │  edit RTL / testbench / script  ──►  simulate (xsim, seconds)│
   │      ▲                                   │                   │
   │      │            fail                   ▼                   │
   │      └──────────────────────────  pass? ──► commit + push    │
   │                                          │                   │
   │                                          ▼                   │
   │                          labjournal.py  (append JSONL row)   │
   │                                          │                   │
   │                     (periodically) synth → impl → bitstream  │
   │                                          │                   │
   │                                          ▼                   │
   │                          parse reports → metrics row         │
   └─────────────────────────────────────────────────────────────┘
```

Two design decisions from the skill shaped this loop:

1. **Simulation-first (mandatory).** No synthesis or board programming before
   the relevant simulation passes. Cheap, second-scale `xsim` feedback front-
   loads correctness so the slow Vivado stages (§9) are entered only when a run
   is *likely* to pass. Empirically this held: the RTL synthesized and routed
   with **zero** iterations of back-and-forth (§7).

2. **Self-logging (mandatory).** The repository logs its own construction. A
   small tool, `scripts/labjournal.py`, appends one JSON line per *iteration*,
   *bug*, *formal run*, and *synth/impl metric* into `logs/*.jsonl`. The agent
   runs it as part of finishing each unit of work, the same way it runs tests.
   This turns the design session into a dataset (the object of the paper) with
   no manual bookkeeping.

An **iteration** is one prompt → edit → test cycle that touches the design. The
log records phase, component, a one-line prompt summary, files changed,
diff-line counts (auto-filled from `git diff --numstat`), the commit SHA, an
agent-estimated duration, the outcome, and — crucially — a boolean plus note
for **human intervention**.

---

## 3. Iteration-by-iteration record

Thirteen iterations were logged (iteration 1 was a prior micro-session that set
the spec; iterations 2–13 are this session). "Wall-clock Δ" is the real elapsed
time between consecutive feature commits from the git history — a truer measure
than the agent's self-estimated `duration_seconds`, which it cannot actually
measure (see §11). LOC is net lines added per the log.

| It | Phase | Component | Prompt (summary) | Wall-clock Δ | LOC + | Outcome |
|---:|---|---|---|---:|---:|---|
| 1 | review | project-spec | Clarify spec (RV32I, 3-stage, Nexys A7), add README | — | 18 | pass |
| 2 | sim | alu | ALU + regfile + self-checking ALU unit test | ~9 min* | 193 | pass (15/15) |
| 3 | sim | regfile | Register-file unit test | ~1 min | 90 | pass (7/7) |
| 4 | sim | rv32i-core | 3-stage core + memories + mini-assembler + integration test | ~14 min | 835 | pass |
| 5 | synth | rv32i-top | Board top (MMCM+reset sync) + XDC + LED demo; synthesize | ~8 min | 235 | pass |
| 6 | review | docs | README + ARCHITECTURE + `run_sim.sh` | ~3 min | 308 | pass |
| 7 | bitstream | rv32i-top | Place & route + bitstream | ~4.5 min | 28 | pass |
| 8 | formal | sva-verification | SVA properties + binds; assertion-based verification | ~12 min | 220 | pass (19 props) |
| 9 | hw-test | rv32i-top | Program the board over JTAG | ~5.5 min | 30 | partial (config OK) |
| 10 | hw-test | rv32i-top | **Human** confirms LED counter increments | — | 0 | pass |
| 11 | hw-test | rv32i-top | Rebuild with `test1`, flash self-test | ~5.5 min | 104 | partial |
| 12 | hw-test | rv32i-top | **Human** confirms `0x0ACE` pass pattern | — | 0 | pass |
| 13 | review | docs | Document board LED behavior | (later) | 136 | pass |

\* Iteration 2 includes session preflight (Context7 verification, reading the
spec/logging conventions, planning) that preceded the first feature commit.

**Aggregate.** The full spec-to-silicon loop (iterations 2–12) spanned roughly
**66 minutes** of active work; ~2,082 net lines of RTL, testbenches, formal
collateral, scripts, and docs were produced. Distribution of effort by phase:
simulation and core construction dominated (iteration 4 alone, the pipeline +
assembler + integration test, was ~14 min and 835 LOC); formal verification was
the second-largest single block (~12 min).

### Prompts and how they decomposed

The human's actual prompts were coarse — e.g. *"continue working on making the
Nexys A7 board a RV32I CPU and don't forget to do the documentation"*, then
later *"run place-and-route and generate the bitstream"*, *"do the formal
verification next"*, *"run test1 on hardware so the pass pattern shows"*. The
agent decomposed each into the fine-grained sub-goals recorded as the prompt
summaries above, maintained its own task list, and chose the ordering (leaf
modules → integration → board → synth → formal → hardware). The human supplied
**direction and milestones**; the agent supplied **decomposition and
execution**.

---

## 4. Bugs: what broke and how it was fixed

Two bugs were logged. **Neither was in the CPU RTL.** Both were in *tooling or
verification collateral the agent also had to build* — which is itself a
finding (§10).

### Bug 1 — `asm-li-addr-size-01` (category: off-by-one; detected by: simulation; iterations-to-fix: 0)

The agent wrote a small two-pass assembler (`scripts/asm.py`) to turn readable
`.s` test programs into memory images. Its **pass 1 advanced the program
counter by 4 bytes per source line**, but the `li` pseudo-instruction expands to
**two** machine words (`lui`+`addi`) when the constant needs the upper
immediate. Every label defined after a wide `li` was therefore misplaced.

- **Why it hid**: not-taken branches don't depend on their offset, and the
  self-test's early checks all pass and fall through — so the wrong offsets were
  never exercised. The bug only surfaced at the first *taken far jump*,
  `jal ra, addfn`, which landed in the middle of the pass/fail block instead of
  the target function.
- **How it was found**: the integration test halted early with an unexpected
  LED value (`0xFFFB`). The agent added a per-cycle pipeline trace (a throwaway
  debug testbench dumping PC/instr/redirect/flush each cycle), saw the jump
  target decode as `lui t1,1` rather than `add a0,a0,a1`, and localized the
  fault to address computation — **in the assembler, not the CPU**.
- **Fix**: made pass 1 size-aware (`insn_words()`), so `li` contributes its true
  1-or-2-word length. Re-assembled; the test passed (`0x0ACE`).

### Bug 2 — `sva-sra-signed-context-01` (category: tool-usage; detected by: formal/ABV; iterations-to-fix: 0)

Writing SVA properties for the ALU, the agent specified arithmetic-shift-right
as `y == ($signed(a) >>> b[4:0])`. Because `y` is unsigned, **Verilog's
context-determined signedness makes the whole comparison unsigned, which
demotes `>>>` to a *logical* shift** — so the *property* disagreed with the
(correct) arithmetic-shift RTL.

- **Discriminating evidence**: across 200,000 random vectors, *only* SRA
  failed; all ten other ALU ops passed. That pattern pointed at the property,
  not the datapath.
- **Fix**: compute the expected value in a `wire signed [31:0]` so `>>>` stays
  arithmetic; additionally add `disable iff (!rst_n)` to skip reset-time `X`
  inputs that were tripping the bound assertions.

**Meta-observation.** Both defects were classic human-error hotspots too — an
assembler length table and a Verilog signedness corner — and both were caught
by the *next tool in the chain* (simulation caught the assembler; the ALU
assertions caught the SVA). The RTL of the processor itself passed each stage
on the first attempt. For a *well-specified, in-distribution* ISA like RV32I,
the LLM-authored datapath/control was reliable; the fragile surface was the
**bespoke, one-off collateral** around it.

---

## 5. Verification strategy and results

Three layers, in increasing scope:

1. **Unit tests** (`sim/tb_alu.v`, `sim/tb_regfile.v`): directed, self-checking.
   ALU = 15 vectors over sign/shift/overflow edges (15/15). Register file = 7
   checks incl. `x0`-constant and read-during-write (7/7).

2. **Integration self-test** (`sim/tb_core.v` + `sim/programs/test1.s`): a
   101-instruction program that exercises reg/imm ALU, shifts, signed/unsigned
   compares, **every** branch condition, `JAL`/`JALR` call+return, `AUIPC`, and
   byte/half/word load+store with sign/zero extension — including back-to-back
   dependencies and load-use (i.e., the forwarding path). The program is
   *self-checking*: every check branches to a fail path on mismatch, and it
   writes `0x0ACE` to the memory-mapped LEDs only if all checks pass. The CPU
   thus proves its own correctness and the testbench only reads a verdict. This
   same program later became the **on-hardware** self-test.

3. **Formal / assertion-based** (`formal/`): 19 SVA properties, `bind`-attached
   so the RTL stays pure Verilog — 12 ALU (every op + zero flag), 2 register
   file (`x0`), 5 core invariants (halt is sticky; a taken branch squashes its
   shadow the next cycle; a squashed slot performs no register/memory write; the
   LED-address decode is mutually exclusive with data memory; the LED register
   changes only on a LED store). Run under `xsim` against 200k random ALU
   vectors and the `test1` trajectory. All pass.

### How SymbiYosys would have changed this

The distinction matters for the paper, so it is worth stating precisely. With no
formal engine on the host, layer 3 ran as **assertion-based verification
(ABV)**: the properties are only checked on the states the stimulus actually
reaches. 200k random ALU vectors sample a vanishing fraction of the
2³²·2³²·(ops) input space, and the core invariants are checked only along
`test1`'s ~99-cycle path.

Had **SymbiYosys** (Yosys + an SMT solver such as Z3/Boolector) been available,
the *same* `formal/sva_*.sv` files — deliberately written in the sby-supported
subset (`|->`, `|=>`, `##N`; no `s_eventually`) and attached via `bind` — would
run as **true model checking with zero rewrite**:

- **Combinational ALU**: a bounded-model-check at depth 1 reasons over *all*
  inputs symbolically, converting *"200k random vectors passed"* into *"proven
  correct for every `(a,b,op)`."* The SRA property bug would have produced an
  immediate counterexample regardless of stimulus quality.
- **Pipeline/control invariants**: `prove` mode (k-induction) would establish
  them over *all reachable states for all time*, not just the test trajectory —
  the class of guarantee that catches rare hazards (e.g. a forwarding fault that
  needs a specific register-index collision) which directed/random simulation
  can miss.
- **Cost**: BMC risks state-space explosion on deep/wide datapaths, but this
  core is small (≈800 LUT, 5-property control surface), so proofs would likely
  be fast. Combinational modules are essentially free.

The takeaway is a reusable pattern: **author properties once, in the proof-ready
subset, run them as ABV immediately and as BMC wherever the engine exists.** The
`.sby` configs were left as the single remaining step to a full proof run.

---

## 6. Design quality metrics

Extracted by `scripts/parse_vivado_reports.py` from Vivado's reports and logged
to `logs/metrics.jsonl`. The programmed workload was the LED-counter demo (an
all-NOP image is optimized away — see §9). Device budgets are for the
`XC7A100T`.

| Metric | Post-synthesis | **Post-route (impl)** | Device budget | Impl % |
|---|---:|---:|---:|---:|
| Slice LUTs | 819 | **798** | 63,400 | 1.26 % |
| Slice Registers (FF) | 159 | **161** | 126,800 | 0.13 % |
| Block RAM tiles | 6.5 | **6.5** | 135 | 4.81 % |
| DSP slices | 0 | **0** | 240 | 0 % |
| Target period | 40.0 ns | 40.0 ns | (25 MHz) | — |
| WNS (setup slack) | +26.81 ns | **+19.76 ns** | — | met |
| WHS (hold slack) | +0.045 ns | **+0.102 ns** | — | met |
| Implied Fmax | 75.8 MHz | **49.4 MHz** | — | — |
| Total on-chip power | — | **0.213 W** | — | — |
| DRC violations | — | **0** | — | — |
| Bitstream size | — | 3.83 MB | — | — |

Reading these:

- The core is **tiny** — ~1.3 % of the fabric — with no DSPs (RV32I has no
  multiply) and BRAM only for the 16 KB instruction and data memories.
- The design meets timing with large margin at its 25 MHz operating point:
  routed WNS of +19.76 ns implies a real **Fmax ≈ 49 MHz**, ~2× headroom. The
  25 MHz clock (from an MMCM dividing the 100 MHz board oscillator) is a
  deliberate simplicity/area trade — the long
  `imem→decode→regfile→forward→ALU→dmem` combinational path is single-cycle, and
  slowing the clock avoids pipelining it further on a teaching core.
- Post-synth vs post-route: the estimated Fmax drops from 75.8 to 49.4 MHz once
  real routing delay is included — a good illustration for the article of why
  post-synthesis timing is optimistic and implementation timing is the number
  that counts.

---

## 7. Why the RTL "just worked" downstream

A notable process result: **the CPU RTL required zero rework at synthesis,
implementation, or DRC.** Synthesis reported 0 errors / 0 warnings; place &
route completed with 0 critical warnings; `write_bitstream` passed DRC with 0
violations — all on the first attempt. The only iteration cost downstream came
from *tooling* (the assembler bug) and *verification collateral* (the SVA bug),
never from the design. Contributing factors: the simulation-first discipline;
the skill's *sharp-edges* guidance (which pre-empted the classic latch/CDC/
reset-release/`initial`-block mistakes); synchronous, inference-friendly memory
patterns; and RV32I being a small, unambiguous, in-distribution target.

---

## 8. Tooling friction: Vivado does not fit an agentic loop — and the bridges built

An LLM agent works best with **fast, small, structured, non-interactive**
tool exchanges. Vivado is the opposite on every axis. The session bridged the
gap with a thin scripting layer; the mismatches and their mitigations are, we
argue, a transferable contribution.

| Vivado characteristic (anti-agentic) | Consequence for the loop | Bridge built |
|---|---|---|
| Multi-thousand-line human-oriented logs | Blows the agent's context window; signal buried in noise | `scripts/run_vivado.sh` archives the full log to disk and surfaces **only** `ERROR`/`CRITICAL WARNING` lines and a timing-not-met flag to the terminal (summarization at the tool boundary) |
| Reports are ASCII tables, not machine-readable | Metrics can't enter the dataset directly | `scripts/parse_vivado_reports.py` regex-extracts LUT/FF/BRAM/DSP/timing/power into the log schema and prints a ready-to-run `labjournal metrics` command |
| Long latencies (synth ~15 s, impl ~1–2 min, program ~15 s) | Slow feedback starves an iterative agent | Simulation-first: `xsim` closes correctness in seconds; Vivado is entered only when a pass is likely. Checkpoints (`.dcp`) make impl resume from synth instead of recompiling |
| GUI/JTAG interactivity for programming | No human at the console in a batch agent | `scripts/program.tcl` scripts the hardware manager (`connect_hw_server`/`program_hw_devices`) as non-interactive batch |
| Windows/`$readmemh` path fragility (`xsim -testplusarg` mis-parses a `C:` drive colon; `$readmemh` resolves relative to cwd) | Silent load failures | Testbenches load a relative `program.hex` from the run directory; the harness `cd`s there. Build artifacts confined to a git-ignored `build/` |
| Dead-code elimination surprise | Synthesizing with an all-NOP program pruned the **entire core** (constant LEDs ⇒ outputs independent of logic), yielding a misleading ~1-LUT result | Recognized as expected DCE, not a bug; a real workload is baked in via a `PROG_HEX` override so outputs depend on the datapath. Documented as an agent trap |
| No self-observability on hardware | The agent can configure the FPGA and verify `DONE=HIGH`, but **cannot see the LEDs** | The last-mile functional check is delegated to the human (§10); an on-chip ILA (JTAG readback) is the tool-only alternative, noted as future work |

Net effect: a handful of small, committed scripts (`run_vivado.sh`,
`parse_vivado_reports.py`, `run_sim.sh`, `program.tcl`, plus the domain-specific
`asm.py` and `labjournal.py`) converted a GUI-centric EDA flow into a
**headless, summarizing, structured, resumable** pipeline an agent can drive.

---

## 9. The human in the loop

Human intervention was logged explicitly (the `human_intervention` field). Over
13 iterations there were **exactly two** — iterations 10 and 12 — and both were
of the *same kind*: **visual confirmation of hardware behavior** (the LED
counter incrementing; the `0x0ACE` self-test pattern). Neither was a correction
or a design override. No human edited RTL, redirected the microarchitecture, or
diagnosed a bug.

This localizes the human's irreducible role precisely: at the **observability
boundary** the agent cannot cross (photons leaving the board), not in design or
debugging. Everything up to and including *configuring* the FPGA and verifying
`DONE=HIGH` was autonomous; only *seeing the lights* required a person. Coarse
milestone-setting ("do formal next", "run test1 on hardware") was also human,
but that is direction, not intervention.

---

## 10. Process metrics summary

| Quantity | Value | Source |
|---|---|---|
| Iterations (this session) | 12 (IDs 2–13) | `logs/iterations.jsonl` |
| Phases exercised | review, sim, synth, bitstream, formal, hw-test | log |
| Net lines added | ~2,082 (design+tests+formal+scripts+docs) | git diff |
| Bugs | 2, both fixed, both iterations-to-fix = 0 | `logs/bugs.jsonl` |
| Bugs in CPU RTL | **0** | — |
| Human interventions | 2 (both hardware visual confirmation) | log |
| Synth/impl metric records | 2 | `logs/metrics.jsonl` |
| Active wall-clock, spec→silicon | ~66 min | git timestamps |
| Simulation engine | Vivado `xsim` (batch) | — |
| Random ALU vectors checked | 200,000 | `formal/tb_alu_formal.sv` |
| SVA properties | 19 (12 ALU + 2 regfile + 5 core) | `formal/` |
| **Cost (provisional estimate)** | ≈ 1.8 M input tok, ≈ 90 k output tok, ≈ \$10 | `logs/cost.jsonl` (flagged) |

The cost row is explicitly **provisional and agent-estimated**: the agent has no
telemetry into its own token usage or billing (the authoritative figure is the
CLI's `/cost`). That an autonomous agent **cannot measure its own economic
cost** is itself a limitation worth reporting.

---

## 11. Threats to validity / limitations

- **Single run, single design, single operator.** No repetition, no baseline
  (e.g. human-only or non-agentic) for comparison. Effect sizes are anecdotal.
- **In-distribution target.** RV32I is small, standardized, and abundantly
  represented in training data. Results may not transfer to novel ISAs,
  aggressive microarchitectures, or analog/mixed-signal work.
- **ABV, not proof.** The formal layer ran as bounded, stimulus-driven
  assertion checking, not exhaustive model checking (§5). "Verified" here means
  "no property violated on the exercised states."
- **Self-reported effort and cost are unreliable.** The per-iteration
  `duration_seconds` are agent estimates; the git-timestamp Δ is the better
  proxy but conflates reasoning, tool latency, and (for later iterations)
  interleaved conversation. Token/USD figures are estimates.
- **Timing at 25 MHz.** The design is not pushed for frequency; the reported
  ~49 MHz Fmax is headroom at a deliberately conservative operating point, not a
  max-performance result.
- **Observability gap.** Final functional confirmation depended on a human
  eyeball; no on-chip readback (ILA) was instrumented.

---

## 12. Reproducibility

The entire flow is scripted and committed; program images are checked in as
both source (`.s`) and assembled hex (`.hex`).

```bash
# simulate (seconds)
scripts/run_sim.sh sim/tb_alu.v
scripts/run_sim.sh sim/tb_core.v sim/programs/test1.s     # -> led = 0x0ACE

# assertion-based / formal
formal/run_formal.sh                                       # 19 properties

# synthesize, implement, program (bake in any program via PROG_HEX)
PROG_HEX=sim/programs/test1.hex scripts/run_vivado.sh synth/synth.tcl
scripts/run_vivado.sh synth/impl.tcl
scripts/run_vivado.sh scripts/program.tcl                 # -> board runs test1
```

The process dataset is `logs/*.jsonl` (`iterations`, `bugs`, `metrics`,
`formal`, `cost`), documented field-by-field in `logs/SCHEMA.md`, and the
git history provides an independent, timestamped audit trail.

---

## 13. Lessons for agentic hardware design

1. **Instrument the process, not just the product.** A ~250-line self-logger
   turned an ordinary design session into a reusable dataset at near-zero
   overhead. The artifact documenting its own construction is the paper's spine.
2. **Simulation-first is what makes the slow tools tractable.** Closing
   correctness in seconds meant the minute-scale Vivado stages were hit rarely
   and passed first-try.
3. **The LLM's RTL was reliable; its bespoke tooling was the risk.** Both bugs
   were in agent-built collateral (assembler, SVA), not the CPU — suggesting
   review effort for agentic HW flows should concentrate on the *scaffolding*
   the agent improvises around a standard design.
4. **EDA tools need an adapter layer to be agent-usable.** Summarize logs,
   structure reports, script interactivity, exploit checkpoints — a small,
   transferable engineering pattern (§8).
5. **Write properties proof-ready even when you can only afford ABV today.** The
   SVA is one `sby` install away from real BMC, with no rewrite.
6. **The human's residual role can be pinpointed.** Here it collapsed to the
   observability boundary (seeing the board) plus milestone direction — a
   concrete, measurable division of labor rather than a vague "human oversight."

---

*Generated as part of the project's self-documentation. All quantitative claims
trace to `logs/*.jsonl` and the git history; estimates are labeled as such.*
