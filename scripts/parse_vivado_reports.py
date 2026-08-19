#!/usr/bin/env python3
"""Parse a Vivado report_utilization / report_timing_summary .rpt into the
fields labjournal.py's `metrics` subcommand wants, and print the ready-made
command line (doesn't call labjournal.py itself, so you can eyeball the
numbers before they're logged).

Usage:
  parse_vivado_reports.py --iteration 12 --stage impl \\
      --util build/impl/utilization.rpt --timing build/impl/timing_summary.rpt

Point --util / --timing at whatever you passed to
`report_utilization -file ...` / `report_timing_summary -file ...` in your
build.tcl.
"""
import argparse
import re


def parse_utilization(text):
    out = {}
    # Vivado utilization tables look like:
    # | Slice LUTs   | 1234 | 0 | 20800 | 5.93  |
    patterns = {
        "luts": r"\|\s*Slice LUTs\*?\s*\|\s*(\d+)\s*\|.*\|\s*(\d+)\s*\|\s*([\d.]+)\s*\|",
        "ffs": r"\|\s*Slice Registers\s*\|\s*(\d+)\s*\|.*\|\s*(\d+)\s*\|\s*([\d.]+)\s*\|",
        "bram": r"\|\s*Block RAM Tile\s*\|\s*([\d.]+)\s*\|.*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|",
        "dsp": r"\|\s*DSPs\s*\|\s*(\d+)\s*\|.*\|\s*(\d+)\s*\|\s*([\d.]+)\s*\|",
    }
    for key, pat in patterns.items():
        m = re.search(pat, text)
        if m:
            used, _total, pct = m.groups()
            out[key] = float(used) if key == "bram" else int(used)
            out[f"{key}_pct"] = float(pct)
    return out


def parse_timing(text):
    out = {}
    for key, label in [("wns", "WNS"), ("tns", "TNS"), ("whs", "WHS"), ("ths", "THS")]:
        m = re.search(rf"{label}\(ns\)\s*:?\s*(-?[\d.]+)", text)
        if m:
            out[key] = float(m.group(1))
    m = re.search(r"Requirement:\s*([\d.]+)ns", text) or re.search(r"period\s*=\s*([\d.]+)", text, re.I)
    if m:
        out["target_clock_ns"] = float(m.group(1))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--iteration", type=int, required=True)
    ap.add_argument("--stage", required=True, choices=["synth", "impl"])
    ap.add_argument("--util")
    ap.add_argument("--timing")
    ap.add_argument("--power-report")
    a = ap.parse_args()

    fields = {}
    if a.util:
        fields.update(parse_utilization(open(a.util).read()))
    if a.timing:
        fields.update(parse_timing(open(a.timing).read()))
    if a.power_report:
        m = re.search(r"Total On-Chip Power \(W\)\s*\|\s*([\d.]+)", open(a.power_report).read())
        if m:
            fields["power"] = float(m.group(1))

    if not fields:
        print("no fields parsed -- check the report format matches your Vivado version")
        return

    parts = [f"python3 scripts/labjournal.py metrics --iteration {a.iteration} --stage {a.stage}"]
    key_to_flag = {
        "luts": "--luts", "luts_pct": "--luts-pct", "ffs": "--ffs", "ffs_pct": "--ffs-pct",
        "bram": "--bram", "bram_pct": "--bram-pct", "dsp": "--dsp", "dsp_pct": "--dsp-pct",
        "target_clock_ns": "--target-clock-ns", "wns": "--wns", "tns": "--tns",
        "whs": "--whs", "ths": "--ths", "power": "--power",
    }
    for k, v in fields.items():
        parts.append(f"{key_to_flag[k]} {v}")
    if a.util:
        parts.append(f"--report-file {a.util}")
    print("Parsed fields:", fields)
    print("\nRun this to log it:\n")
    print(" \\\n  ".join(parts))


if __name__ == "__main__":
    main()
