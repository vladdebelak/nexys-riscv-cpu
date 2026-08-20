#!/usr/bin/env python3
"""vcd2svg.py — render selected signals from a VCD dump as a digital-timing
SVG, with NO external dependencies (pure standard library). The output is a
vector figure that renders inline on GitHub and in papers, and any reviewer can
regenerate it from the committed .vcd.

(The repo also ships render_waveform.py, which is prettier but needs
vcdvcd+matplotlib; this one is the zero-install fallback used for the figures.)

Usage:
  python scripts/vcd2svg.py sim/waves/wavedemo.vcd \\
      --signals clk pc instr alu_a alu_b alu_y wb_rd wb_data redirect flush_ex led \\
      --start 30 --end 150 --clock clk \\
      --title "3-stage pipeline: forwarding + branch flush" \\
      --out docs/figures/pipeline_waveform.svg
Times are in nanoseconds. Signal names match by exact or suffix (so 'pc'
matches 'dut.pc'). 1-bit signals draw as square waves; multi-bit as hex buses.
"""
import argparse, re, sys, html

def parse_vcd(path):
    scale_ns, name2id, id2info, changes = 1.0, {}, {}, {}
    cur = 0
    with open(path) as f:
        tokens = f.read().split('\n')
    i = 0
    # ---- header ----
    while i < len(tokens):
        line = tokens[i].strip(); i += 1
        if line.startswith('$timescale'):
            body = line
            while '$end' not in body:
                body += ' ' + tokens[i]; i += 1
            m = re.search(r'(\d+)\s*(fs|ps|ns|us|ms|s)', body)
            if m:
                mag = int(m.group(1)); unit = m.group(2)
                to_ns = {'fs':1e-6,'ps':1e-3,'ns':1.0,'us':1e3,'ms':1e6,'s':1e9}[unit]
                scale_ns = mag * to_ns
        elif line.startswith('$var'):
            # $var <type> <width> <id> <name> [<range>] $end
            p = line.split()
            width = int(p[2]); vid = p[3]; name = p[4]
            id2info[vid] = (name, width)
            name2id.setdefault(name, vid)
            changes[vid] = []
        elif line.startswith('$enddefinitions'):
            break
    # ---- value changes ----
    while i < len(tokens):
        line = tokens[i].strip(); i += 1
        if not line: continue
        if line[0] == '#':
            cur = int(line[1:])
        elif line[0] in '01xz':
            vid = line[1:]
            if vid in changes: changes[vid].append((cur, line[0]))
        elif line[0] in 'bB':
            val, vid = line[1:].split()
            if vid in changes: changes[vid].append((cur, val))
        # ignore 'r' real, $dumpvars/$end markers
    return scale_ns, name2id, id2info, changes

def val_at(seq, t):
    """Last value at or before time t (ticks)."""
    v = None
    for (tt, vv) in seq:
        if tt <= t: v = vv
        else: break
    return v

def bin2hex(b):
    if b is None: return 'x'
    if 'x' in b or 'X' in b: return 'x'
    if 'z' in b or 'Z' in b: return 'z'
    try: return format(int(b, 2), 'x')
    except ValueError: return '?'

def resolve(sig, name2id):
    if sig in name2id: return name2id[sig]
    cand = [n for n in name2id if n == sig or n.endswith('.'+sig) or n.split('.')[-1] == sig]
    if cand: return name2id[sorted(cand, key=len)[0]]
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('vcd')
    ap.add_argument('--signals', nargs='+', required=True)
    ap.add_argument('--start', type=float, default=0.0)   # ns
    ap.add_argument('--end', type=float, required=True)   # ns
    ap.add_argument('--clock', default='clk')
    ap.add_argument('--title', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--list', action='store_true')
    a = ap.parse_args()

    scale_ns, name2id, id2info, changes = parse_vcd(a.vcd)
    if a.list:
        for n in name2id: print(n)
        return
    t0 = int(round(a.start / scale_ns)); t1 = int(round(a.end / scale_ns))

    # layout
    LBL, ROW, GAP, PXNS = 120, 26, 12, 7.0    # px
    top = 46 if a.title else 20
    width_px = LBL + (a.end - a.start) * PXNS + 30
    height_px = top + len(a.signals) * (ROW + GAP) + 30
    def X(t_ticks): return LBL + (t_ticks * scale_ns - a.start) * PXNS

    # clock rising edges -> cycle grid
    edges = []
    cid = resolve(a.clock, name2id)
    if cid:
        seq = changes[cid]; prev = '0'
        for (tt, vv) in seq:
            if prev in '0' and vv == '1' and t0 <= tt <= t1: edges.append(tt)
            prev = vv

    S = []
    S.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width_px:.0f}" height="{height_px:.0f}" '
             f'font-family="monospace" font-size="12">')
    S.append(f'<rect width="100%" height="100%" fill="white"/>')
    if a.title:
        S.append(f'<text x="{LBL}" y="26" font-size="15" font-weight="bold" fill="#111">{html.escape(a.title)}</text>')

    # cycle gridlines + numbers
    for k, e in enumerate(edges):
        x = X(e)
        S.append(f'<line x1="{x:.1f}" y1="{top-4}" x2="{x:.1f}" y2="{height_px-24}" stroke="#e2e2e2"/>')
        if k+1 < len(edges):
            xm = (x + X(edges[k+1]))/2
            S.append(f'<text x="{xm:.1f}" y="{top-8}" fill="#999" font-size="10" text-anchor="middle">c{k+1}</text>')

    y = top
    for sig in a.signals:
        vid = resolve(sig, name2id)
        label = sig
        S.append(f'<text x="{LBL-8}" y="{y+ROW*0.7:.1f}" text-anchor="end" fill="#111">{html.escape(label)}</text>')
        base_y, hi_y = y+ROW, y+2
        if vid is None:
            S.append(f'<text x="{LBL+4}" y="{y+ROW*0.7:.1f}" fill="#c00">?missing?</text>')
            y += ROW+GAP; continue
        name, wdt = id2info[vid]; seq = changes[vid]
        # transition times within window
        tset = sorted({t0} | {tt for (tt,_) in seq if t0 < tt < t1})
        segs = tset + [t1]
        if wdt == 1:
            # square wave with explicit vertical transitions
            pts = []
            for idx in range(len(segs)-1):
                ts, te = segs[idx], segs[idx+1]
                v = val_at(seq, ts)
                lvl = hi_y if v == '1' else base_y
                if not pts:
                    pts.append((X(ts), lvl))
                else:
                    pts.append((X(ts), pts[-1][1]))   # hold, then step
                    pts.append((X(ts), lvl))
                pts.append((X(te), lvl))
            path = 'M ' + ' L '.join(f'{px:.1f},{py:.1f}' for px, py in pts)
            S.append(f'<path d="{path}" fill="none" stroke="#1a56db" stroke-width="1.6"/>')
        else:
            # bus: hex label per stable segment
            for idx in range(len(segs)-1):
                ts, te = segs[idx], segs[idx+1]
                v = val_at(seq, ts); hx = bin2hex(v)
                xa, xb = X(ts), X(te); mid=(xa+xb)/2
                fill = '#f3f4f6' if hx not in ('x','z','?') else '#fde2e2'
                # hexagon-ish cell
                S.append(f'<path d="M {xa+3:.1f},{y+2} L {xb-3:.1f},{y+2} L {xb:.1f},{(y+ROW/2):.1f} '
                         f'L {xb-3:.1f},{y+ROW-2} L {xa+3:.1f},{y+ROW-2} L {xa:.1f},{(y+ROW/2):.1f} Z" '
                         f'fill="{fill}" stroke="#9aa0a6" stroke-width="0.8"/>')
                if xb-xa > 16:
                    S.append(f'<text x="{mid:.1f}" y="{y+ROW*0.68:.1f}" text-anchor="middle" fill="#111">'
                             f'{html.escape(("0x"+hx) if hx not in ("x","z","?") else hx)}</text>')
        y += ROW+GAP

    # time axis
    S.append(f'<text x="{LBL}" y="{height_px-6}" fill="#666" font-size="10">'
             f'{a.start:.0f}&#8211;{a.end:.0f} ns &#183; cycles c1..c{len(edges)-1 if len(edges)>1 else 0} '
             f'&#183; buses shown in hex</text>')
    S.append('</svg>')
    with open(a.out, 'w') as f: f.write('\n'.join(S))
    print(f"wrote {a.out}  ({len(a.signals)} signals, {len(edges)} clock edges in window)")

if __name__ == '__main__':
    main()
