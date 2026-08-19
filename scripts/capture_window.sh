#!/bin/bash
# Capture a single window (e.g. Vivado's GUI) to PNG, for the cases where you
# genuinely want to show the tool itself -- an error dialog, the schematic
# viewer, the utilization pie chart, the Tcl console -- rather than data that
# should be a regenerable figure (waveforms: use render_waveform.py instead).
#
# Usage:
#   scripts/capture_window.sh figures/vivado_timing_violation.png
#
# Click the target window when the crosshair appears. macOS's screencapture
# grabs just that window (with its native chrome cropped by -o), at full
# Retina resolution, no manual cropping needed.
set -euo pipefail
if [ $# -ne 1 ]; then
  echo "usage: $0 <output.png>" >&2
  exit 1
fi
out="$1"
mkdir -p "$(dirname "$out")"
echo "click the window to capture..."
screencapture -w -o -x "$out"
echo "wrote $out"
