# What the board is doing — reading the LEDs

This page explains, in plain terms, what you see on the Nexys A7 when the CPU
is running, and how to interpret the LEDs. It covers the two demo programs
shipped in `sim/programs/` and how to switch between them.

## The one mechanism behind everything: memory-mapped LEDs

The CPU has a small trick wired in. Normally a **store** instruction writes a
value into data memory. But one address — **`0x0000_1000`** — isn't memory at
all. When the CPU stores to that address, the hardware instead latches the low
16 bits into a register physically connected to the 16 green LEDs (LD0–LD15).
(See `LED_ADDR` in `rtl/rv32i_core.v`, and the `is_led` decode.)

So the LEDs are literally **a window into one number the CPU chose to display.**
Each LED is one bit: lit = 1, dark = 0. Read right-to-left — LD0 is the "ones"
place — to get the binary value.

Everything you see on the board is just **different programs writing different
numbers to `0x1000`.** Same silicon; the behavior comes entirely from the
~100–400 instructions loaded into the instruction memory. That is the whole
point of a CPU: general-purpose hardware whose personality is the program.

## Demo 1 — `test1.s`: the self-test (a frozen result)

`sim/programs/test1.s` is a **self-checking** program. It runs a gauntlet —
add/sub, shifts, signed/unsigned comparisons, every branch type, a function
call+return, and byte/half/word loads and stores — and after each step checks
the answer. If any check fails it jumps to a failure path. Then:

1. load the verdict into a register,
2. **store** it to `0x1000` (→ LEDs show it),
3. execute **`ECALL`**, which **halts** the CPU (pipeline freezes).

Because it halts, the LEDs are **static**. The pattern *is* the result:

| Verdict | Value | LEDs lit (all others dark) |
|---|---|---|
| **PASS** | `0x0ACE` ("ACE") | **LD11, LD9, LD7, LD6, LD3, LD2, LD1** |
| FAIL | `0x0BAD` ("BAD") | LD11, LD9, LD8, LD7, LD5, LD3, LD2, LD0 |

```
PASS = 0x0ACE
       0    A    C    E
     0000 1010 1100 1110
LD:  15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
      ·  ·  ·  ·  ●  ·  ●  ·  ●  ●  ·  ·  ●  ●  ●  ·
```

The values are mnemonic on purpose: `ACE` = "aced the test," `BAD` = a failed
check. So the board isn't merely "on" — it is reporting that the CPU verified
its **own** correctness in hardware and succeeded.

Press **CPU RESET** (button, pin C12): the LEDs go dark, the CPU re-runs the
whole gauntlet in microseconds, and the same `0x0ACE` snaps back — repeatable
proof.

## Demo 2 — `led_counter.s`: the counter (a live, moving display)

`sim/programs/led_counter.s` loops forever:

1. keep a counter in a register,
2. store it to `0x1000` (→ show it),
3. add 1,
4. **wait** in a short delay loop (~4,096 do-nothing iterations),
5. repeat.

There is no `ECALL`, so it **never halts** — the display is *alive*. Each step
bumps the number by one, roughly every **half a millisecond** at the 25 MHz CPU
clock.

Why the low LEDs blur while the high ones "walk": that's **binary counting** —
each bit flips half as often as the one to its right.

| LED | flips… | looks like |
|---|---|---|
| LD0 | every increment (~2 kHz) | steady dim glow (too fast to see) |
| LD4 | every 16 increments (~120 Hz) | flicker |
| LD8 | every 256 increments (~8 Hz) | visible blinking |
| LD15 | every 32,768 increments (~16 s) | slow, deliberate on/off |

The "walking wave" is the classic binary-odometer effect — frantic on the
right, increasingly stately toward the left — and it means the CPU is
faithfully executing millions of instructions (add, store, delay, loop) with
you watching the arithmetic happen in real time.

## Side by side

| | `led_counter` | `test1` |
|---|---|---|
| Program does | infinite count-and-display loop | run checks, post verdict, halt |
| LEDs | continuously changing | frozen |
| Proves | the CPU executes instructions reliably | the CPU computes *correct* answers across the ISA |
| Ends? | never (loops) | yes (`ECALL` halts) |

Both are the **same CPU** — the difference is only which program sits in the
instruction memory.

## Switching which program runs on the board

The program is baked into the instruction BRAM at build time via the `PROG_HEX`
override, so switching means re-running synth → impl → program:

```bash
export PATH="/c/Xilinx/Vivado/2020.2/bin:$PATH"   # adjust to your Vivado

# self-test (frozen 0x0ACE on pass)
PROG_HEX=sim/programs/test1.hex \
  scripts/run_vivado.sh synth/synth.tcl
scripts/run_vivado.sh synth/impl.tcl
scripts/run_vivado.sh scripts/program.tcl

# or the counting demo
PROG_HEX=sim/programs/led_counter.hex \
  scripts/run_vivado.sh synth/synth.tcl
scripts/run_vivado.sh synth/impl.tcl
scripts/run_vivado.sh scripts/program.tcl
```

To write your own program, edit/create a `.s`, assemble it
(`python scripts/asm.py my.s -o sim/programs/my.hex`), then build with
`PROG_HEX=sim/programs/my.hex`. Store any value to `0x1000` to show it on the
LEDs; `ECALL` to halt.

> Note: configuration is volatile (SRAM). Power-cycling the board clears it;
> re-run `scripts/program.tcl` to reload. To make it survive power cycles you
> would program the bitstream into the board's SPI flash instead.
