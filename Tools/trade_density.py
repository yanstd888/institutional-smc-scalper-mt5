"""Berapa trade/hari champion di jendela terakhir backtest? -> untuk membedakan 'rejimen sepi' vs 'filter memblokir'."""
import re, sys, collections, datetime

path = sys.argv[1]
html = open(path, "r", encoding="utf-8", errors="replace").read()

# baris trade: sel waktu format "2026.08.12 14:35:00"
times = re.findall(r"(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})", html)
dates = sorted({datetime.datetime.strptime(t, "%Y.%m.%d %H:%M:%S") for t in times})
if not dates:
    print("tidak ada timestamp ditemukan"); sys.exit(1)

print(f"rentang data dalam report : {dates[0]} .. {dates[-1]}")
day_counts = collections.Counter(d.date() for d in dates)
# entry = waktu unik pertama per hari? report berisi entry+exit; hitung pasangan unik per hari
print(f"hari trading aktif        : {len(day_counts)}")
print(f"timestamp unik            : {len(dates)}  (≈ 2x jumlah trade: entry+exit)")

# 30 hari terakhir
last = dates[-1].date()
cut = last - datetime.timedelta(days=30)
recent = {d: c for d, c in day_counts.items() if d > cut}
tot = sum(recent.values())
print(f"\n30 hari terakhir ({cut} .. {last}):")
print(f"  hari dengan aktivitas   : {len(recent)}")
print(f"  timestamp              : {tot}  -> ≈ {tot/2:.0f} trade  ({tot/2/30:.2f} trade/hari)")
print(f"  30 hari itu per hari   : {sorted(recent.items())[-10:]}")
