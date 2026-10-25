#!/usr/bin/env python
"""Fail closed unless every reconstructed Gen-4 thesis volume is 0.10."""
import argparse
import csv
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--positions-csv',required=True)
args=parser.parse_args()
with Path(args.positions_csv).open(encoding='utf-8-sig',newline='') as f:
    rows=list(csv.DictReader(f))
if not rows:
    raise SystemExit('Fixed-lot gate: no positions')
def _is_pt1(v):
    s = (v or '').strip()
    if not s:
        return None
    try:
        return abs(float(s) - 0.10) < 1e-6
    except ValueError:
        return False

# entry_volume must be 0.10; initial_volume (if telemetry captured) must also be 0.10
bad = [
    r for r in rows
    if _is_pt1(r.get('entry_volume')) is not True
    or _is_pt1(r.get('initial_volume')) is False
]
if bad:
    raise SystemExit(f'Fixed-lot gate: {len(bad)}/{len(rows)} positions not 0.10')
print(f'FIXED-LOT GATE: PASS positions={len(rows)}')
