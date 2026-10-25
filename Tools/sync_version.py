#!/usr/bin/env python3
"""Keep YANSTD.mq5 version literals in sync with Defines.mqh.

Source of truth: #define YANSTD_VERSION "X.Y.Z-HYBRID"
Targets in YANSTD.mq5: header Version comment, #property copyright, #property version.

Usage:
  python3 Tools/sync_version.py          # validate
  python3 Tools/sync_version.py --apply  # rewrite YANSTD.mq5
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFINES = ROOT / "Modules" / "Defines.mqh"
EA = ROOT / "YANSTD.mq5"
VERSION_RE = re.compile(r'^#define\s+YANSTD_VERSION\s+"(\d+\.\d+\.\d+)-HYBRID"', re.M)


def read_version() -> str:
    text = DEFINES.read_text(encoding="utf-8")
    match = VERSION_RE.search(text)
    if not match:
        raise SystemExit("YANSTD_VERSION was not found in Defines.mqh.")
    return match.group(1)


def expected_ea(text: str, version: str) -> str:
    replacements = [
        (r'(^//\|\s+Version\s+)\d+\.\d+\.\d+', rf"\g<1>{version}"),
        (r'(^#property\s+copyright\s+"YANSTD EA v)\d+\.\d+\.\d+', rf"\g<1>{version}"),
        (r'(^#property\s+version\s+")\d+\.\d+', rf"\g<1>{version.rsplit('.', 1)[0]}"),  # MQL5 Market needs xxx.yyy
    ]
    out = text
    for pattern, repl in replacements:
        new, n = re.subn(pattern, repl, out, count=1, flags=re.M)
        if n != 1:
            raise SystemExit(f"Version field not found: {pattern}")
        out = new
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    version = read_version()
    current = EA.read_text(encoding="utf-8")
    expected = expected_ea(current, version)
    if args.apply:
        if current != expected:
            EA.write_text(expected, encoding="utf-8", newline="\n")
        print(f"Synchronized YANSTD version {version}.")
        return 0
    if current != expected:
        print("Version mismatch. Run: python3 Tools/sync_version.py --apply", file=sys.stderr)
        return 1
    print(f"PASS: all YANSTD version fields are {version}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())