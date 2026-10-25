"""Uji kerapuhan dari tabel deal yang sudah ada. Tidak menjalankan tester.

1. Kurva ekuitas dari trade tertutup: DD aktual vs DD di bawah urutan acak (Monte Carlo).
2. Uji ekor gemuk: buang N trade terbaik, lihat net dan PF.
3. Konsentrasi bulanan.

Self-check: total trade tertutup dan net wajib sama dengan journal.json run itu.
Pakai: python Tools/robustness.py [folder-run label]
"""
import json
import os
import random
import re
import sys

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DEFAULT_JOBS = [
    (os.path.join(BASE, "LAYLA/Runs/L5_LimitExpiry_60"), "L5 (expiry 60)"),
    (os.path.join(BASE, "Backtests/YANSTD-LIVE-SELECTION-MODULE/Runs/G27B_RECHECK_20260922"),
     "G27B champion (expiry 30)"),
]


def load(path):
    raw = open(path, "rb").read()
    enc = "utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
    html = raw.decode(enc, "replace")
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html[html.rfind("<b>Deals</b>"):], re.S | re.I)
    out = []
    for r in rows:
        c = [re.sub(r"<[^>]+>", "", x).replace("\xa0", " ").strip()
             for x in re.findall(r"<td[^>]*>(.*?)</td>", r, re.S | re.I)]
        if c and re.match(r"\d{4}\.\d{2}\.\d{2}", c[0]):
            out.append(c)
    return out


def num(s):
    return float(s.replace(" ", ""))


def closed_trades(rows):
    """(waktu, nilai) untuk setiap deal keluar."""
    return [(c[0], num(c[8]) + num(c[9]) + num(c[10]))
            for c in rows if c[3] in ("buy", "sell") and c[4] == "out"]


def dd_curve(vals, start=10000.0):
    eq = peak = start
    dd = 0.0
    for v in vals:
        eq += v
        peak = max(peak, eq)
        dd = max(dd, peak - eq)
    return dd, eq, peak


def pf(vals):
    gp = sum(v for v in vals if v > 0)
    gl = sum(v for v in vals if v <= 0)
    return gp / abs(gl) if gl else float("inf")


def analyse(run_dir, label, seed=20260923, mc=2000):
    j = json.load(open(os.path.join(run_dir, "journal.json"), encoding="utf-8-sig"))
    exp_net = num(j["NetProfit"])
    exp_tr = int(j["TotalTrades"].replace(" ", ""))

    tr = closed_trades(load(os.path.join(run_dir, "report.htm")))
    vals = [v for _, v in tr]
    assert abs(sum(vals) - exp_net) < 0.02, (sum(vals), exp_net)
    assert len(vals) == exp_tr, (len(vals), exp_tr)

    dd, end, peak = dd_curve(vals)
    rng = random.Random(seed)
    dds = sorted(dd_curve(rng.sample(vals, len(vals)))[0] for _ in range(mc))
    pct = 100.0 * sum(1 for d in dds if d < dd) / len(dds)

    print(f"\n=== {label} — {os.path.basename(run_dir)} ===")
    print(f"trade {len(vals)} | net {sum(vals):,.2f} | PF {pf(vals):.2f}")
    print(f"DD kurva tutup {dd:,.2f} = {100.0*dd/peak:.2f}% dari puncak {peak:,.2f}")
    print(f"  vs urutan acak: p05 {dds[int(.05*mc)]:,.2f} | p50 {dds[mc//2]:,.2f} | "
          f"p95 {dds[int(.95*mc)]:,.2f} -> DD aktual di persentil {pct:.0f}")

    srt = sorted(vals, reverse=True)
    print("buang N trade terbaik -> net / PF:")
    for n in (1, 5, 10, 20):
        rest = srt[n:]
        print(f"  {n:2d}: {sum(rest):>10,.2f} / {pf(rest):.2f}")

    bulan = {}
    for t, v in tr:
        bulan[t[:7]] = bulan.get(t[:7], 0.0) + v
    tot = sum(bulan.values())
    top = sorted(bulan.items(), key=lambda x: -x[1])[:6]
    share = 100.0 * sum(v for _, v in top) / tot
    print(f"enam bulan teratas: {share:.1f}% dari net")
    for m, v in top:
        print(f"  {m}: {v:>9,.2f} ({100.0*v/tot:4.1f}%)")

    return {"net": sum(vals), "pf": pf(vals), "dd": dd, "dd_pct": 100.0 * dd / peak,
            "pct": pct, "pf10": pf(srt[10:]), "pf20": pf(srt[20:]), "top6": share}


if __name__ == "__main__":
    jobs = DEFAULT_JOBS
    if len(sys.argv) > 1:
        jobs = [(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "run")]
    res = {label: analyse(d, label) for d, label in jobs}
    if len(res) > 1:
        print("\n=== perbandingan ===")
        for label, m in res.items():
            print(f"{label:26} net {m['net']:>10,.2f} | PF {m['pf']:.2f} -> buang10 "
                  f"{m['pf10']:.2f} -> buang20 {m['pf20']:.2f} | DD {m['dd_pct']:.2f}% "
                  f"(pctl {m['pct']:.0f}) | top6 bulan {m['top6']:.1f}%")
