"""Append satu baris metrik report ke PURE-REFINE.csv: python report_row.py <run-dir> <csv>"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_report import summary

KEYS = [("Net", "Total Net Profit"), ("PF", "Profit Factor"), ("Trades", "Total Trades"),
        ("WR", "Profit Trades (% of total)"), ("DD", "Equity Drawdown Maximal")]


def row(run_dir):
    d = os.path.basename(run_dir.rstrip("/\\"))
    s = summary(run_dir)
    parts = [d] + [s.get(k, "?") for _, k in KEYS]
    return ",".join('"%s"' % p for p in parts)


if __name__ == "__main__":
    r = row(sys.argv[1])
    print(r)
    if len(sys.argv) > 2:
        csv = sys.argv[2]
        if not os.path.exists(csv):
            open(csv, "w", encoding="utf-8").write("RunId,Net,PF,Trades,WR,DDEquity\n")
        open(csv, "a", encoding="utf-8").write(r + "\n")
