"""
YANSTD backtest result -> single self-contained HTML report (Glass Morphism).
Reads every Attribution_*/candidate_scores.json (+cost_stress_summary.json),
writes RESULT_REPORT.html next to them. No deps, no CDN.

Usage: python Tools/export_web_report.py
"""
import os, json, glob, html, datetime

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(PROJECT_ROOT, "Backtests", "YANSTD-LIVE-SELECTION-MODULE")
OUT = os.path.join(MOD, "RESULT_REPORT.html")
CORE_LO, CORE_HI = 2020, 2026

# Display order: newest generation first. Generations not listed sort last.
GEN_ORDER = ["Gen18", "Gen17", "Gen16", "Gen15", "Gen14", "Gen13", "Gen12", "Gen11", "Gen10", "9CONT",
             "9r", "9q", "9p", "9n", "9m", "9l", "9k", "9j", "9i",
             "Gen7FIX_Verify", "Gen8_Full", "Gen6E", "Gen6D", "Gen6C", "Gen6B", "Gen6A",
             "6h", "6g", "6f",
             "Gen5", "Gen4"]

MODE_LABEL = {"M0_HYBRID": "M0 Hybrid", "M1_MSNR_SOFTSMC": "M1 MSNR",
              "M2_SMC_SOFTMSNR": "M2 SMC", "M3_MEANREV": "M3 MeanRev"}

CONTINUOUS_NOTE = "continuous"  # window key marker for non-annual runs


def load_generation(attr_dir):
    p = os.path.join(attr_dir, "candidate_scores.json")
    if not os.path.exists(p):
        return None
    sc = json.load(open(p, encoding="utf-8"))
    is_cont = sc.get("schema") == CONTINUOUS_NOTE
    cands = []
    for c in sc.get("candidates", []):
        wins = {}
        for y, v in sorted(c.get("windows", {}).items()):
            a = v.get("ANNUAL") or {}
            if a.get("net_profit") is None:
                continue
            wins[y] = a
        if is_cont:
            # One continuous window: core == total == that window.
            core = sum(w["net_profit"] for w in wins.values())
            tot = core
            core_n = sum(1 for w in wins.values() if w["net_profit"] > 0)
            core_t = len(wins)
            tot_n = core_n
        else:
            core = sum(w["net_profit"] for y, w in wins.items() if CORE_LO <= int(y[1:]) <= CORE_HI)
            tot = sum(w["net_profit"] for y, w in wins.items())
            core_n = sum(1 for y, w in wins.items() if CORE_LO <= int(y[1:]) <= CORE_HI and w["net_profit"] > 0)
            core_t = sum(1 for y in wins if CORE_LO <= int(y[1:]) <= CORE_HI)
            tot_n = sum(1 for w in wins.values() if w["net_profit"] > 0)
        trades = sum(w.get("trade_count") or 0 for w in wins.values())
        buys = sum(w.get("buy_count") or 0 for w in wins.values())
        sells = sum(w.get("sell_count") or 0 for w in wins.values())
        errs = sum(len(w.get("errors") or []) for w in wins.values())
        cands.append({
            "id": c.get("candidate_id"), "passed": c.get("passed"),
            "fails": c.get("fail_reasons") or [],
            "core": core, "tot": tot, "core_wins": core_n, "core_total": core_t,
            "tot_wins": tot_n, "years": len(wins), "trades": trades,
            "buys": buys, "sells": sells, "errors": errs, "wins": wins,
            "cont": is_cont,
        })
    cands.sort(key=lambda x: -x["core"])
    stress_p = os.path.join(attr_dir, "cost_stress_summary.json")
    stress = json.load(open(stress_p, encoding="utf-8")) if os.path.exists(stress_p) else None
    return {"cands": cands, "stress": stress, "cont": is_cont}


def money(v):
    if v is None:
        return "-"
    return f"{'+' if v >= 0 else '-'}${abs(v):,.2f}"


def gen_rank(gname):
    return GEN_ORDER.index(gname) if gname in GEN_ORDER else 99


def build(gens):
    parts = []

    # ---- champion cards: best core per mode, preferring positive & newest ----
    best = {}
    for gname in sorted(gens, key=gen_rank):
        g = gens[gname]
        for c in g["cands"]:
            for m in MODE_LABEL:
                if c["id"].startswith(m):
                    if m not in best or c["core"] > best[m]["core"]:
                        best[m] = dict(c, gen=gname)
    cards = []
    for m, label in MODE_LABEL.items():
        if m not in best:
            continue
        c = best[m]
        cls = "pos" if c["core"] > 0 else "neg"
        cards.append(f"""<div class="card"><div class="card-inner">
          <div class="card-h">{label}</div>
          <div class="card-v {cls}">{money(c['core'])}</div>
          <div class="card-s">{'continuous 2020-2026.08' if c['cont'] else f'core {CORE_LO}-{CORE_HI}'} &middot; Gen-{c['gen']}</div>
          <div class="card-id">{html.escape(c['id'])}</div>
        </div></div>""")
    if cards:
        parts.append('<div class="cards">' + "".join(cards) + "</div>")

    # ---- per generation, strictly in GEN_ORDER ----
    for gname in sorted(gens, key=gen_rank):
        g = gens[gname]
        badge = ('<span class="badge cont">continuous</span>'
                 if g["cont"] else f'<span class="badge annual">annual {CORE_LO}-{CORE_HI}</span>')
        rows = []
        for ci, c in enumerate(g["cands"]):
            cls = "pos" if c["core"] > 0 else "neg"
            fails = (" <span class='badge bad'>"
                     + html.escape("; ".join(str(f) for f in c["fails"])) + "</span>") if c["fails"] else ""
            win_label = "Y2020_2026" if c["cont"] else "Tahun"
            detail_rows = "".join(
                f"<tr><td>{html.escape(y)}</td>"
                f"<td class='{'pos' if w['net_profit']>0 else 'neg'}'>{money(w['net_profit'])}</td>"
                f"<td>{(w.get('profit_factor') or 0):.2f}</td><td>{w.get('trade_count') or 0:,}</td>"
                f"<td>{w.get('buy_count') or 0}</td><td>{w.get('sell_count') or 0}</td>"
                f"<td>{'OK' if w.get('test_completed') else 'INCOMPLETE'}</td>"
                f"<td>{html.escape('; '.join(str(e) for e in (w.get('errors') or []))) or '-'}</td></tr>"
                for y, w in c["wins"].items())
            rows.append(f"""<tr class="cand">
              <td class="mono">{html.escape(c['id'])}{fails}</td>
              <td class="{cls}"><b>{money(c['core'])}</b></td>
              <td>{c['core_wins']}/{c['core_total']}</td>
              <td class="{'pos' if c['tot']>0 else 'neg'}">{money(c['tot'])}</td>
              <td>{c['tot_wins']}/{c['years']}</td>
              <td>{c['trades']:,}</td>
              <td>{c['buys']:,}/{c['sells']:,}</td>
              <td>{'<span class=badge-ok>PASS</span>' if c['passed'] else '<span class=badge bad>FAIL</span>'}</td>
              <td>{c['errors'] or 0}</td>
              <td><button onclick="tg('g{gname}_{ci}')">detail</button></td>
            </tr>
            <tr class="det" id="d_g{gname}_{ci}"><td colspan="10">
              <div class="glass"><table class="sub">
              <tr><th>{win_label}</th><th>Net P/L</th><th>PF</th><th>Trades</th><th>BUY</th><th>SELL</th><th>Status</th><th>Errors</th></tr>
              {detail_rows}</table></div></td></tr>""")
        parts.append(f"""<section><h2>Gen-{gname} {badge}</h2>
        <div class="glass"><table class="main">
        <tr><th>Candidate</th><th>{'Window NP' if g['cont'] else 'Core NP'}</th><th>Wins</th>
        <th>Total NP</th><th>Total wins</th><th>Trades</th><th>BUY/SELL</th><th>Gate</th><th>Err</th><th></th></tr>
        {''.join(rows)}</table></div>""")
        st = g["stress"]
        if st and st.get("totals"):
            t = st["totals"]
            parts.append(f"""<details><summary>Cost stress (Gen-{gname})</summary>
            <div class="glass"><table class="sub"><tr><th>Metrik</th><th>Nilai</th></tr>
            <tr><td>Posisi</td><td>{t['positions']:,}</td></tr>
            <tr><td>Raw</td><td class="{'pos' if t['raw']>0 else 'neg'}">{money(t['raw'])}</td></tr>
            <tr><td>Setelah swap</td><td class="neg">{money(t['after_swap'])}</td></tr>
            <tr><td>Swap+slip 100pt</td><td class="neg">{money(t['after_swap_slip100'])}</td></tr>
            <tr><td>Swap+slip 200pt</td><td class="neg">{money(t['after_swap_slip200'])}</td></tr>
            </table></div></details>""")
        parts.append("</section>")

    css = """
    :root{
      --bg1:#050816; --bg2:#0b1224;
      --glass:rgba(255,255,255,.045); --glass-br:rgba(255,255,255,.10);
      --glass-hi:rgba(255,255,255,.08);
      --txt:#dbe6f5; --muted:#8ba0bd; --faint:#5b6d88;
      --acc:#7cc4ff; --pos:#4ade80; --neg:#f87171;
      --row:rgba(255,255,255,.025); --row-hi:rgba(124,196,255,.07);
    }
    *{box-sizing:border-box}
    html{scroll-behavior:smooth}
    body{
      margin:0; padding:28px 30px 60px;
      min-height:100vh;
      color:var(--txt);
      font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
      background:
        radial-gradient(1100px 600px at 12% -8%, rgba(91,86,255,.20), transparent 60%),
        radial-gradient(900px 520px at 92% 4%,  rgba(34,211,238,.14), transparent 62%),
        radial-gradient(900px 700px at 50% 108%, rgba(236,72,153,.10), transparent 60%),
        linear-gradient(180deg,var(--bg1),var(--bg2));
      background-attachment:fixed;
    }
    h1{margin:0 0 4px;font-size:24px;letter-spacing:.01em;
       background:linear-gradient(90deg,#eaf2ff,#7cc4ff 55%,#c4b5fd);
       -webkit-background-clip:text;background-clip:text;color:transparent}
    .meta{color:var(--muted);font-size:12.5px;margin-bottom:20px}
    h2{margin:30px 0 10px;font-size:16px;color:var(--acc);letter-spacing:.02em;
       display:flex;align-items:center;gap:10px}
    .glass{
      background:var(--glass); border:1px solid var(--glass-br);
      border-radius:14px; padding:14px 16px;
      backdrop-filter:blur(14px) saturate(140%); -webkit-backdrop-filter:blur(14px) saturate(140%);
      box-shadow:0 10px 30px rgba(0,0,0,.35), inset 0 1px 0 rgba(255,255,255,.06);
    }
    table{border-collapse:collapse;width:100%;font-size:13px}
    th,td{padding:7px 10px;border-bottom:1px solid rgba(255,255,255,.06);text-align:left;white-space:nowrap}
    th{color:var(--faint);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.06em;
       border-bottom:1px solid rgba(255,255,255,.10)}
    tbody tr{border-bottom:1px solid rgba(255,255,255,.04)}
    tr.cand{background:var(--row)}
    tr.cand:hover{background:var(--row-hi)}
    .mono{font-family:ui-monospace,SFMono-Regular,Consolas,"SF Mono",Menlo,monospace;font-size:11.5px;color:#bcd2ee}
    .pos{color:var(--pos)} .neg{color:var(--neg)}
    .cards{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:8px}
    .card{flex:1 1 240px;min-width:230px;border-radius:16px;padding:1px;
          background:linear-gradient(135deg,rgba(255,255,255,.14),rgba(255,255,255,.03));
          box-shadow:0 12px 34px rgba(0,0,0,.35)}
    .card-inner{border-radius:15px;padding:16px 18px;height:100%;
                background:rgba(10,14,28,.55);backdrop-filter:blur(16px) saturate(150%);
                -webkit-backdrop-filter:blur(16px) saturate(150%)}
    .card-h{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.09em}
    .card-v{font-size:25px;font-weight:700;margin:7px 0 3px;font-variant-numeric:tabular-nums}
    .card-s{font-size:11px;color:var(--faint)}
    .card-id{font-family:ui-monospace,Consolas,monospace;font-size:10.5px;color:var(--acc);margin:5px 0 0;
             word-break:break-all;white-space:normal}
    .badge{padding:2px 8px;border-radius:20px;font-size:10px;font-weight:600;letter-spacing:.03em;
           border:1px solid rgba(255,255,255,.12)}
    .badge.annual{background:rgba(124,196,255,.12);color:var(--acc)}
    .badge.cont{background:rgba(74,222,128,.12);color:var(--pos)}
    .badge.bad{background:rgba(248,113,113,.14);color:var(--neg)}
    .badge-ok{padding:2px 8px;border-radius:20px;font-size:10px;font-weight:600;
              background:rgba(74,222,128,.13);color:var(--pos);border:1px solid rgba(74,222,128,.25)}
    tr.det{display:none}
    tr.det.open{display:table-row}
    tr.det>td{padding:0 6px 10px}
    table.sub{font-size:12px}
    table.sub th{position:sticky;top:0}
    button{background:rgba(124,196,255,.10);color:var(--acc);
           border:1px solid rgba(124,196,255,.28);border-radius:8px;
           padding:3px 11px;cursor:pointer;font-size:11px;font-weight:600;
           transition:background .15s,border-color .15s}
    button:hover{background:rgba(124,196,255,.22);border-color:rgba(124,196,255,.5)}
    details{margin:10px 0 20px;color:var(--muted);font-size:12.5px}
    summary{cursor:pointer;padding:6px 0;color:var(--acc);font-weight:600}
    section{margin-bottom:26px}
    ::-webkit-scrollbar{width:10px;height:10px}
    ::-webkit-scrollbar-thumb{background:rgba(255,255,255,.12);border-radius:8px}
    ::-webkit-scrollbar-track{background:transparent}
    @media(max-width:860px){body{padding:18px 14px}.cards{flex-direction:column}}
    """
    js = ("function tg(i){var r=document.getElementById('d_'+i);"
          "if(r)r.classList.toggle('open')}")
    return f"""<!doctype html><html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>YANSTD Backtest Result Report</title><style>{css}</style></head><body>
<h1>YANSTD — Backtest Result Report</h1>
<div class="meta">Digenerate {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')} &middot;
sumber: <span class="mono">Attribution_*/candidate_scores.json</span> &middot;
klik <b>detail</b> untuk per-window (P/L, PF, trades, BUY/SELL, status, error)</div>
{''.join(parts)}
<script>{js}</script></body></html>"""


def main():
    gens = {}
    for d in sorted(glob.glob(os.path.join(MOD, "Attribution_*"))):
        name = os.path.basename(d).replace("Attribution_", "").replace("_Annual", "")
        g = load_generation(d)
        if g and g["cands"]:
            gens[name] = g
    if not gens:
        raise SystemExit("no attribution data found")
    html_out = build(gens)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(html_out)
    print(f"wrote {OUT}  ({len(html_out):,} bytes, {len(gens)} generations, "
          f"{sum(len(g['cands']) for g in gens.values())} candidates)")


if __name__ == "__main__":
    main()
