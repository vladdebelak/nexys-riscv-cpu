# Log schema

All logs are JSONL (one JSON object per line, append-only). This makes them
easy to append from a script mid-session, easy to `grep`, and trivial to load
into pandas for the paper's figures/tables later.

Write entries with `scripts/labjournal.py` rather than by hand — it fills in
timestamp, git commit, and diff stats automatically so the data stays
consistent.

## iterations.jsonl — one record per agent iteration

The core process-metrics log. An "iteration" is one prompt → tool-use →
result cycle that touches the design (an edit + a test run, roughly).

| field | meaning |
|---|---|
| `iteration_id` | monotonically increasing int |
| `timestamp` | ISO8601, UTC |
| `phase` | `rtl-edit` \| `sim` \| `formal` \| `synth` \| `impl` \| `bitstream` \| `hw-test` \| `review` |
| `component` | free text, e.g. `forwarding-unit`, `uart-rx`, `decode-stage` |
| `prompt_summary` | 1-line human summary of what was asked for |
| `files_changed` | list of paths |
| `diff_lines_added` / `diff_lines_removed` | from `git diff --numstat`, auto-filled |
| `git_commit` | sha if committed, else `null` |
| `duration_seconds` | wall clock for this iteration |
| `outcome` | `pass` \| `fail` \| `partial` |
| `human_intervention` | bool |
| `human_intervention_note` | what the human had to do/explain/override, if any |
| `notes` | free text |

## bugs.jsonl — one record per distinct bug

The bug taxonomy table for the paper comes straight from this file.

| field | meaning |
|---|---|
| `bug_id` | short slug, e.g. `hazard-load-use-01` |
| `iteration_introduced` | iteration_id, or `null` if unknown/pre-existing |
| `iteration_detected` | iteration_id |
| `category` | `hazard` \| `cdc` \| `off-by-one` \| `tool-usage` \| `timing` \| `protocol` \| `other` |
| `description` | what was wrong |
| `detected_by` | `simulation` \| `formal` \| `synthesis-drc` \| `timing-report` \| `hardware` \| `human-review` |
| `detection_artifact` | path to the vcd/wdb/counterexample/log/screenshot that shows it |
| `iteration_fixed` | iteration_id, or `null` if still open |
| `iterations_to_fix` | `iteration_fixed - iteration_detected` (auto-computed) |
| `fix_commit` | sha |
| `notes` | free text |

## metrics.jsonl — one record per synth/impl run

Parsed straight out of Vivado's reports by `scripts/parse_vivado_reports.py`
rather than typed by hand.

| field | meaning |
|---|---|
| `iteration_id` | which iteration triggered this run |
| `stage` | `synth` \| `impl` |
| `luts`, `luts_pct`, `ffs`, `ffs_pct`, `bram_tiles`, `bram_pct`, `dsp`, `dsp_pct` | from `report_utilization` |
| `target_clock_ns`, `wns`, `tns`, `whs`, `ths` | from `report_timing_summary` |
| `fmax_mhz` | derived: `1000 / (target_clock_ns - wns)` |
| `power_estimate_w` | from `report_power`, if run |
| `report_file` | path to the raw `.rpt` this was parsed from (keep it — reviewers may ask) |

## formal.jsonl — one record per SymbiYosys run

| field | meaning |
|---|---|
| `iteration_id` | |
| `task` | `bmc` \| `prove` (k-induction) \| `cover` |
| `engine` | e.g. `smtbmc` with `z3` |
| `properties_total`, `properties_pass`, `properties_fail` | |
| `bound` | BMC depth reached |
| `duration_seconds` | |
| `counterexample_file` | path to `.vcd`/trace if a property failed |

## cost.jsonl — one record per work session

| field | meaning |
|---|---|
| `session_id` | |
| `date` | |
| `tokens_in`, `tokens_out` | |
| `estimated_cost_usd` | |
| `wall_clock_seconds` | |
| `iterations_covered` | `[first_iteration_id, last_iteration_id]` |
