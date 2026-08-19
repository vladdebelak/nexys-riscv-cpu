#!/usr/bin/env python3
"""Append-only JSONL logger for the FPGA agentic-design-loop paper.

Usage:
  labjournal.py iteration --phase sim --outcome fail --component forwarding-unit \\
      --prompt "add EX/MEM forwarding" --duration 42 [--human-note "..."]

  labjournal.py bug --id hazard-load-use-01 --category hazard \\
      --description "load-use hazard not stalled" --detected-by simulation \\
      --detected-iter 7 --artifact sim/waves/bug01.vcd

  labjournal.py fix-bug --id hazard-load-use-01 --fixed-iter 9

  labjournal.py formal --task bmc --engine "smtbmc+z3" --total 12 --pass 11 \\
      --fail 1 --bound 20 --duration 8.4 --counterexample formal/cex/prop3.vcd \\
      --iteration 9

  labjournal.py cost --session 2026-08-19a --tokens-in 120000 --tokens-out 8000 \\
      --cost 3.10 --duration 3600 --first-iter 1 --last-iter 14

Each subcommand appends one line to the matching file in logs/. `iteration`
auto-fills timestamp, git commit (if HEAD exists), and diff line counts from
`git diff --numstat` against the previous commit — run it AFTER staging/
committing the change it describes, or pass --no-git to skip.
"""
import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / "logs"


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def append(path, record):
    with open(path, "a") as f:
        f.write(json.dumps(record) + "\n")
    print(f"logged -> {path.relative_to(ROOT)}: {json.dumps(record)}")


def next_id(path, key):
    n = 0
    if path.exists():
        for line in path.read_text().splitlines():
            if line.strip():
                n = max(n, json.loads(line).get(key, 0))
    return n + 1


def git(*args):
    try:
        return subprocess.run(
            ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.strip()
    except subprocess.CalledProcessError:
        return None


def diff_stats():
    out = git("diff", "--numstat", "HEAD~1", "HEAD") if git("rev-parse", "HEAD~1") else None
    added = removed = 0
    if out:
        for line in out.splitlines():
            a, r, _ = line.split("\t", 2)
            added += int(a) if a.isdigit() else 0
            removed += int(r) if r.isdigit() else 0
    return added, removed


def cmd_iteration(a):
    path = LOGS / "iterations.jsonl"
    added, removed = (0, 0) if a.no_git else diff_stats()
    record = {
        "iteration_id": next_id(path, "iteration_id"),
        "timestamp": now(),
        "phase": a.phase,
        "component": a.component,
        "prompt_summary": a.prompt,
        "files_changed": a.files or [],
        "diff_lines_added": added,
        "diff_lines_removed": removed,
        "git_commit": None if a.no_git else git("rev-parse", "HEAD"),
        "duration_seconds": a.duration,
        "outcome": a.outcome,
        "human_intervention": bool(a.human_note),
        "human_intervention_note": a.human_note or "",
        "notes": a.notes or "",
    }
    append(path, record)


def cmd_bug(a):
    path = LOGS / "bugs.jsonl"
    record = {
        "bug_id": a.id,
        "iteration_introduced": a.introduced_iter,
        "iteration_detected": a.detected_iter,
        "category": a.category,
        "description": a.description,
        "detected_by": a.detected_by,
        "detection_artifact": a.artifact or "",
        "iteration_fixed": None,
        "iterations_to_fix": None,
        "fix_commit": None,
        "notes": a.notes or "",
    }
    append(path, record)


def cmd_fix_bug(a):
    path = LOGS / "bugs.jsonl"
    lines = path.read_text().splitlines()
    out = []
    found = False
    for line in lines:
        rec = json.loads(line)
        if rec["bug_id"] == a.id:
            rec["iteration_fixed"] = a.fixed_iter
            if rec.get("iteration_detected") is not None:
                rec["iterations_to_fix"] = a.fixed_iter - rec["iteration_detected"]
            rec["fix_commit"] = git("rev-parse", "HEAD")
            found = True
        out.append(json.dumps(rec))
    if not found:
        sys.exit(f"no bug with id {a.id} in {path}")
    path.write_text("\n".join(out) + "\n")
    print(f"updated -> {path.relative_to(ROOT)}: {a.id} fixed at iteration {a.fixed_iter}")


def cmd_formal(a):
    path = LOGS / "formal.jsonl"
    record = {
        "iteration_id": a.iteration,
        "task": a.task,
        "engine": a.engine,
        "properties_total": a.total,
        "properties_pass": getattr(a, "passed"),
        "properties_fail": a.fail,
        "bound": a.bound,
        "duration_seconds": a.duration,
        "counterexample_file": a.counterexample or "",
        "timestamp": now(),
    }
    append(path, record)


def cmd_metrics(a):
    path = LOGS / "metrics.jsonl"
    record = {
        "iteration_id": a.iteration,
        "timestamp": now(),
        "stage": a.stage,
        "luts": a.luts,
        "luts_pct": a.luts_pct,
        "ffs": a.ffs,
        "ffs_pct": a.ffs_pct,
        "bram_tiles": a.bram,
        "bram_pct": a.bram_pct,
        "dsp": a.dsp,
        "dsp_pct": a.dsp_pct,
        "target_clock_ns": a.target_clock_ns,
        "wns": a.wns,
        "tns": a.tns,
        "whs": a.whs,
        "ths": a.ths,
        "fmax_mhz": (1000.0 / (a.target_clock_ns - a.wns)) if (a.target_clock_ns and a.wns is not None) else None,
        "power_estimate_w": a.power,
        "report_file": a.report_file or "",
    }
    append(path, record)


def cmd_cost(a):
    path = LOGS / "cost.jsonl"
    record = {
        "session_id": a.session,
        "date": a.date or now(),
        "tokens_in": a.tokens_in,
        "tokens_out": a.tokens_out,
        "estimated_cost_usd": a.cost,
        "wall_clock_seconds": a.duration,
        "iterations_covered": [a.first_iter, a.last_iter],
    }
    append(path, record)


def build_parser():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    it = sub.add_parser("iteration")
    it.add_argument("--phase", required=True, choices=["rtl-edit", "sim", "formal", "synth", "impl", "bitstream", "hw-test", "review"])
    it.add_argument("--component", required=True)
    it.add_argument("--prompt", required=True)
    it.add_argument("--outcome", required=True, choices=["pass", "fail", "partial"])
    it.add_argument("--duration", type=float, required=True)
    it.add_argument("--files", nargs="*")
    it.add_argument("--human-note")
    it.add_argument("--notes")
    it.add_argument("--no-git", action="store_true")
    it.set_defaults(func=cmd_iteration)

    b = sub.add_parser("bug")
    b.add_argument("--id", required=True)
    b.add_argument("--category", required=True, choices=["hazard", "cdc", "off-by-one", "tool-usage", "timing", "protocol", "other"])
    b.add_argument("--description", required=True)
    b.add_argument("--detected-by", required=True, choices=["simulation", "formal", "synthesis-drc", "timing-report", "hardware", "human-review"])
    b.add_argument("--detected-iter", type=int, required=True)
    b.add_argument("--introduced-iter", type=int)
    b.add_argument("--artifact")
    b.add_argument("--notes")
    b.set_defaults(func=cmd_bug)

    fb = sub.add_parser("fix-bug")
    fb.add_argument("--id", required=True)
    fb.add_argument("--fixed-iter", type=int, required=True)
    fb.set_defaults(func=cmd_fix_bug)

    f = sub.add_parser("formal")
    f.add_argument("--iteration", type=int, required=True)
    f.add_argument("--task", required=True, choices=["bmc", "prove", "cover"])
    f.add_argument("--engine", required=True)
    f.add_argument("--total", type=int, required=True)
    f.add_argument("--pass", dest="passed", type=int, required=True)
    f.add_argument("--fail", type=int, required=True)
    f.add_argument("--bound", type=int)
    f.add_argument("--duration", type=float, required=True)
    f.add_argument("--counterexample")
    f.set_defaults(func=cmd_formal)

    m = sub.add_parser("metrics")
    m.add_argument("--iteration", type=int, required=True)
    m.add_argument("--stage", required=True, choices=["synth", "impl"])
    m.add_argument("--luts", type=int)
    m.add_argument("--luts-pct", type=float)
    m.add_argument("--ffs", type=int)
    m.add_argument("--ffs-pct", type=float)
    m.add_argument("--bram", type=float)
    m.add_argument("--bram-pct", type=float)
    m.add_argument("--dsp", type=int)
    m.add_argument("--dsp-pct", type=float)
    m.add_argument("--target-clock-ns", type=float)
    m.add_argument("--wns", type=float)
    m.add_argument("--tns", type=float)
    m.add_argument("--whs", type=float)
    m.add_argument("--ths", type=float)
    m.add_argument("--power", type=float)
    m.add_argument("--report-file")
    m.set_defaults(func=cmd_metrics)

    c = sub.add_parser("cost")
    c.add_argument("--session", required=True)
    c.add_argument("--date")
    c.add_argument("--tokens-in", type=int, required=True)
    c.add_argument("--tokens-out", type=int, required=True)
    c.add_argument("--cost", type=float, required=True)
    c.add_argument("--duration", type=float, required=True)
    c.add_argument("--first-iter", type=int, required=True)
    c.add_argument("--last-iter", type=int, required=True)
    c.set_defaults(func=cmd_cost)

    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    args.func(args)
