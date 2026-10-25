"""Parse report.htm MT5 (UTF-16-LE) -> ringkasan angka. Pakai: python parse_report.py <run-dir> [...]"""
import re
import sys
import os


def read(p):
    raw = open(p, "rb").read()
    for enc in ("utf-16-le", "utf-8", "cp1252"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", "replace")


def cells(html):
    t = re.sub(r"<[^>]+>", "\t", html)
    return [c.replace("&nbsp;", " ").strip().rstrip(":") for c in t.split("\t")]


def summary(d):
    h = read(os.path.join(d, "report.htm"))
    c = [x for x in cells(h) if x]
    out = {}
    for i, x in enumerate(c):
        if x in ("Total Net Profit", "Profit Factor", "Total Trades", "Short Trades (won %)",
                 "Long Trades (won %)", "Balance Drawdown Maximal", "Equity Drawdown Maximal",
                 "Sharpe Ratio", "Expected Payoff", "Recovery Factor", "Profit Trades (% of total)"):
            for j in range(i + 1, min(i + 6, len(c))):
                if c[j] and re.search(r"\d", c[j]):
                    out[x] = c[j]
                    break
    return out


if __name__ == "__main__":
    for d in sys.argv[1:]:
        print("=" * 72)
        print(os.path.basename(d.rstrip("/\\")))
        s = summary(d)
        for k in ("Total Net Profit", "Profit Factor", "Total Trades", "Profit Trades (% of total)",
                  "Long Trades (won %)", "Short Trades (won %)", "Balance Drawdown Maximal",
                  "Equity Drawdown Maximal", "Expected Payoff", "Sharpe Ratio"):
            if k in s:
                print("  %-26s %s" % (k, s[k]))
