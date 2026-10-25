"""Berapa besar kontribusi trade yang MELINTASI batas periode pada run kontinu?

LIFO pairing untuk memasangkan deal in/out, lalu pisahkan posisi yang dibuka dan
ditutup di periode berbeda (dev/val/hold). Ini menjelaskan selisih antara run
kontinu dan run terpisah.
"""
import re

BOUNDS = [("dev", "2020.01.01", "2022.12.31"),
          ("val", "2023.01.01", "2024.12.31"),
          ("hold", "2025.01.01", "2026.08.31")]

RUNS = {
    "G27B": (os.path.abspath(os.path.join(os.path.dirname(__file__), "..")/Backtests/"
             r"YANSTD-LIVE-SELECTION-MODULE/Runs/G27B_RECHECK_20260922/report.htm"),
    "L5": os.path.abspath(os.path.join(os.path.dirname(__file__), "..")/LAYLA/Runs/L5_LimitExpiry_60/report.htm",
}


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


def val(c):
    return sum(float(c[i].replace(" ", "")) for i in (8, 9, 10))


def period(d):
    if d <= "2022.12.31":
        return "dev"
    if d <= "2024.12.31":
        return "val"
    return "hold"


def analyse(name, path):
    deals = load(path)
    stack = []
    same, cross = 0.0, 0.0
    n_same = n_cross = 0
    for c in deals:
        if c[3] not in ("buy", "sell"):
            continue
        if c[4] == "in":
            stack.append([{"vol": float(c[5]), "v": 0.0, "t": c[0]}])
        else:
            vol = float(c[5])
            v = val(c)
            orig = vol
            while vol > 1e-9 and stack:
                top = stack[-1][0]
                take = min(vol, top["vol"])
                top["v"] += v * (take / orig)
                top["vol"] -= take
                if top["vol"] <= 1e-9:
                    stack.pop()
                    if period(top["t"]) == period(c[0]):
                        same += top["v"]
                        n_same += 1
                    else:
                        cross += top["v"]
                        n_cross += 1
                vol -= take
    print(f"{name}: posisi utuh dalam satu periode {n_same} bernilai {same:,.2f}")
    print(f"{name}: posisi MELINTASI batas periode  {n_cross} bernilai {cross:,.2f}")
    return n_cross, cross


if __name__ == "__main__":
    print("Run kontinu, dipasangkan LIFO:\n")
    res = {k: analyse(k, p) for k, p in RUNS.items()}
    print()
    print(f"selisih kontinu vs terpisah: G27B 9.196,81 vs 9.410,68 = -213,87; "
          f"L5 11.962,86 vs 9.968,33 = +1.994,53")
    print("kalau angka 'melintasi batas' di atas seorder besaran dengan selisih itu,")
    print("maka penyebabnya adalah posisi yang hidup melewati batas periode.")
