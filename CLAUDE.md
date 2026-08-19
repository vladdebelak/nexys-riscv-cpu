# nexys-riscv-cpu — logging conventions

This project logs its own design process for an academic write-up (agentic
LLM-assisted FPGA/CPU design). See `logs/SCHEMA.md` for the full field
reference. Follow these rules in every session, without being asked:

## Log every iteration

After finishing a meaningful unit of work (an RTL edit + its test run, a
formal-verification pass, a synth/impl run, a hardware test), run:

```
python3 scripts/labjournal.py iteration --phase <rtl-edit|sim|formal|synth|impl|bitstream|hw-test|review> \
  --component <short name, e.g. forwarding-unit> --prompt "<1-line summary of what was asked>" \
  --outcome <pass|fail|partial> --duration <seconds this took>
```

Commit the change first (`git add` + `git commit`) if you want accurate
diff-line counts — the logger reads `git diff HEAD~1 HEAD`. If you didn't
commit, pass `--no-git`.

If the user corrected you, explained something you got wrong, or overrode a
decision, that's a human intervention — include `--human-note "<what
happened>"`. Don't skip this out of politeness; it's the data point that
makes the paper's "where did the human have to step in" analysis possible.

## Log every bug

The moment a bug is identified (simulation failure, formal counterexample,
synthesis DRC, timing violation, or something a human review caught):

```
python3 scripts/labjournal.py bug --id <slug> --category <hazard|cdc|off-by-one|tool-usage|timing|protocol|other> \
  --description "<what's wrong>" --detected-by <simulation|formal|synthesis-drc|timing-report|hardware|human-review> \
  --detected-iter <iteration_id> --artifact <path to vcd/log/counterexample if any>
```

When it's fixed:

```
python3 scripts/labjournal.py fix-bug --id <slug> --fixed-iter <iteration_id>
```

## Log every formal run

After any `sby` run:

```
python3 scripts/labjournal.py formal --iteration <id> --task <bmc|prove|cover> --engine <e.g. smtbmc+z3> \
  --total <n> --pass <n> --fail <n> --bound <n> --duration <seconds> [--counterexample <path>]
```

## Log every synth/impl run

Run Vivado through `scripts/run_vivado.sh <tclscript>` (not `vivado` directly)
so errors/warnings get summarized instead of dumped raw. Afterward, parse the
reports and log the metrics:

```
python3 scripts/parse_vivado_reports.py --iteration <id> --stage <synth|impl> \
  --util <path to utilization.rpt> --timing <path to timing_summary.rpt>
```

This prints the ready-made `labjournal.py metrics` command — run it as-is.

## Waveforms

When a bug is illustrated with a waveform, dump the `.vcd`, point `bugs.jsonl`'s
`--artifact` at it, and render the actual paper figure with
`scripts/render_waveform.py` (not a Vivado GUI screenshot — see the script's
docstring for why).

## Don't ask the user to do this bookkeeping

These commands are mechanical — run them yourself as part of finishing each
unit of work, the same way you'd run a test suite. Only flag it to the user
if a required field genuinely needs their input (e.g. they know why a bug
was introduced and you don't).
