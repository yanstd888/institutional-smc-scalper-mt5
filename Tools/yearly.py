"""Ringkas per-tahun dari report.htm: python yearly.py <run-dir> [<run-dir> ...]"""
import re
import sys


def yearly(run_dir):
    h = open(run_dir + "/report.htm", "rb").read().decode("utf-16-le", "replace")
    out = []
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", h, re.S):
        cells = [re.sub("<[^>]+>", " ", c).strip()
                 for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)]
        cells = [re.sub(r"\s+", " ", c) for c in cells]
        if cells and re.fullmatch(r"20\d\d", cells[0]):
            out.append(cells)
    return out


for d in sys.argv[1:]:
    print("==", d.rsplit("/", 1)[-1])
    for c in yearly(d):
        print("   ", " | ".join(c[:8]))
