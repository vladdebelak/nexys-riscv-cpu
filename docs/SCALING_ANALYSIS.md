# If the core were much bigger: how the agentic design effort would scale

This note projects how the process documented in
[`AGENTIC_DESIGN_CASE_STUDY.md`](AGENTIC_DESIGN_CASE_STUDY.md) would change if
the target were a substantially larger processor. It is grounded in this
project's *measured* baseline, but the forward projections are **order-of-
magnitude estimates**, explicitly labeled — offered as structured intuition for
the article, not as benchmarks.

## The measured baseline (this project)

| Quantity | Value |
|---|---|
| Design | RV32I, 3-stage, in-order, no caches/CSRs |
| Source produced | ~2,082 lines (RTL + tests + formal + scripts + docs) |
| RTL only | ~600 lines across 7 modules |
| Active wall-clock, spec→silicon | ~66 min |
| Iterations | 12 |
| Bugs | 2 (both in tooling/collateral; **0 in the CPU RTL**) |
| Tokens (agent estimate) | ~1.8 M in / ~90 k out |
| Quality | 798 LUT, 161 FF, 6.5 BRAM, 0 DSP; timing met |
| Verification | unit + self-checking integration + 19 SVA (ABV) |

Two baseline facts drive everything below: **RTL authoring was cheap and
reliable, verification was the larger share, and the human's only irreducible
role was observing hardware.** Scaling stresses exactly those seams.

## What "much bigger" means — three axes

Complexity does not grow along one dimension. A larger core grows along three,
and they interact:

1. **ISA scope**: RV32I → add `M` (mul/div) → CSRs + machine-mode traps/
   interrupts → `A` (atomics) → `F/D` (floating point) → supervisor mode + MMU
   (virtual memory, page tables).
2. **Microarchitecture**: 3-stage → 5-stage → branch prediction → caches (I/D)
   → superscalar → out-of-order (register renaming, reorder buffer, load/store
   queue) → multicore + coherence.
3. **SoC integration**: bare core → AXI/TileLink interconnect → peripherals
   (UART, timers, PLIC/CLINT interrupt controllers) → DMA → DDR memory
   controller → boot ROM + software stack.

## Why effort grows *super-linearly*

Lines of RTL grow roughly linearly with features, but the two things that
actually consume agent (and human) effort grow faster:

- **Verification state space explodes.** A scalar in-order core's correctness
  is dominated by a handful of hazard cases. An out-of-order core must be
  correct under *every* interleaving of speculative execution, renaming,
  memory-ordering, and interrupt timing. Random/directed simulation samples a
  vanishing slice of that space; this is precisely where **formal methods stop
  being optional** (see below). Industry data routinely puts verification at
  60–70% of total effort for non-trivial cores.
- **Cross-cutting invariants multiply.** Caches add coherence; multiple clocks
  add CDC; virtual memory adds TLB/page-table consistency; interrupts add
  precise-exception requirements across the whole pipeline. Each is a *global*
  property that no single module encapsulates — the hardest thing for a
  context-window-bounded agent to keep coherent.
- **Tool latency compounds.** This core synthesized in ~15 s and routed in
  ~90 s. A cache-coherent multicore can take **hours** per synth/impl run, and
  timing closure becomes an iterative search. The "Vivado doesn't fit an
  agentic loop" friction (case study §8) gets qualitatively worse: slow,
  serial, hard-to-summarize feedback.

## How the agent's behavior would change

| Regime | What changes for the LLM agent |
|---|---|
| **Fits in context** (≈ this project) | The agent holds the whole design in view, keeps modules consistent, and authors standard blocks reliably. Bugs concentrate in *bespoke* collateral (as observed here). |
| **Exceeds context** (tens of thousands of LOC) | The agent can no longer see the whole design at once. It must work module-by-module with retrieval, and **global-consistency bugs appear** (an interface changed in one module, stale assumptions in another). Maintained spec/interface docs and a persistent process log (this repo's `labjournal`) become load-bearing, not nice-to-have. |
| **Novel microarchitecture** (custom OoO scheduler, coherence protocol) | Reliability drops: less in-distribution training data, and correctness rests on subtle, non-local invariants. The agent shifts from *author* to *assistant*; human architectural direction and formal specs dominate. |
| **Long hardware bring-up** (real DDR, peripherals, an OS) | The observability gap widens far beyond "look at the LEDs": the agent needs instrumented readback (ILA, trace ports), co-simulation, and a human for physical debugging. |

The consistent pattern: **standard, in-distribution IP (ALUs, register files,
AXI slaves, UARTs) stays cheap and reliable; novel control logic and system-
level verification are where cost and risk concentrate.**

## Where SymbiYosys / formal stops being optional

In this project, formal ran as bounded assertion-based verification because the
design was small enough that self-checking simulation already gave high
confidence. At scale that inverts:

- For an **out-of-order** core, the interesting bugs are rare interleavings that
  random simulation will not hit in any feasible number of vectors. **Bounded
  model checking and k-induction** (SymbiYosys, or commercial JasperGold) become
  the primary way to establish hazard, forwarding, and memory-ordering
  invariants — and the ROI on writing properties rises sharply.
- **Differential co-simulation against a golden ISA model** (Spike, Sail) plus
  the official `riscv-arch-test` suite become the backbone of functional sign-
  off — turning "is it correct?" into an automated, exhaustive-ish oracle the
  agent can run in its loop. This is the single highest-leverage tool to add for
  scaling an agentic CPU project.

The design choice made here — writing SVA in the proof-ready subset with `bind`
— is exactly what makes that transition cheap: the same properties scale from
ABV to full BMC without rewriting.

## Rough cost projection (order-of-magnitude, speculative)

Extrapolating from the baseline, with the explicit caveat that token cost scales
**super-linearly** with design size (as the codebase outgrows the context
window, each edit re-reads more surrounding code, and debug/verification
iterations multiply):

| Tier | Design | RTL (LOC) | Human-supervised effort | Tokens (very rough) | Dominant cost |
|---|---|---:|---|---:|---|
| **T0 (this)** | RV32I 3-stage, LEDs | ~600 | ~1 hour | ~2 M | authoring |
| **T1** | RV32IM + CSRs + traps, 5-stage, UART; passes `riscv-arch-test` | 3–8 k | ~1–3 days of sessions | ~15–50 M | test infra + trap corner cases |
| **T2** | Pipelined core + I/D caches + AXI SoC + interrupts; boots bare-metal | 15–30 k | ~1–3 weeks | ~100–400 M | cache/interconnect verification, timing closure |
| **T3** | Superscalar/OoO, branch prediction, MMU; boots Linux; multicore | 80–200 k | months | billions | memory-model & coherence formal verification, deep debug |

Read these as *relative shapes*, not promises: each tier is roughly an order of
magnitude more tokens than the last, and the growth is driven by **verification
and debugging, not RTL typing**. At T3, current agents are best understood as
force-multipliers for an expert team, not autonomous designers — the failure
modes have moved from syntax (which LLMs handle well) to architecture and
system-level correctness (which they do not, alone).

## What would most help an agent scale (highest leverage first)

1. **A golden-model differential-test harness** (Spike/Sail + `riscv-arch-test`)
   wired into the agent's loop — an automated correctness oracle.
2. **Formal verification** (SymbiYosys → commercial) for the non-local
   invariants simulation cannot cover.
3. **Better EDA adapters** — the log-summarizing / report-parsing / checkpoint-
   resuming pattern from this project (case study §8), extended with structured
   timing-report diffing and incremental synthesis, so multi-hour tools stay
   loop-compatible.
4. **Maintained architecture & interface specs** the agent updates as it goes,
   to preserve global consistency past the context-window limit.
5. **Standard, reusable interfaces and IP** (AXI/TileLink) — the in-distribution
   material LLMs handle most reliably.
6. **Persistent process memory** (this repo's self-logging) so state survives
   across the many sessions a large design requires.

## Bottom line for the article

The agentic loop demonstrated here — simulation-first, self-logging, thin EDA
adapters, ABV that is proof-ready — is a genuine methodology, not a one-off. It
**scales in structure** to much larger cores. What does **not** scale for free
is *verification and system-level debugging*: those grow super-linearly and are
where both the token budget and the human's involvement would increasingly go.
The most useful next investment for scaling is therefore not a bigger model but
a **stronger correctness oracle** (golden-model co-simulation + formal) inside
the loop.

*All baseline numbers trace to `logs/*.jsonl`; tier projections are
order-of-magnitude estimates and are labeled as such.*
