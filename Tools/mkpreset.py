"""Buat preset .set dari preset lain dengan sedikit override, newline CRLF SEJATI.

Wajib pakai ini, jangan tulis .set sendiri: `open(..., 'w', newline='\\r\\n')` menghasilkan
\\r\\r\\n -> MT5 gagal parse dan input diam-diam kembali ke default EA (run menguji preset lain
tanpa peringatan apa pun). Self-check di bawah menolak hasil yang tercemar.

Pakai: python mkpreset.py <src.set> <dst.set> KEY=VAL [KEY=VAL ...]
"""
import os
import sys


def build(src, dst, changes):
    txt = open(src, encoding="utf-8-sig").read().replace("\r\n", "\n").replace("\r", "\n")
    lines = txt.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    seen = set()
    for i, l in enumerate(lines):
        k = l.split("=", 1)[0].strip() if "=" in l else None
        if k in changes:
            lines[i] = f"{k}={changes[k]}"
            seen.add(k)
    assert seen == set(changes), f"key not found in {src}: {sorted(set(changes) - seen)}"
    data = ("\r\n".join(lines) + "\r\n").encode("utf-8-sig")
    assert b"\r\r\n" not in data, "doubled CR: MT5 would silently use EA defaults"
    assert data.count(b"\r\n") == len(lines), "line/CRLF count mismatch"
    open(dst, "wb").write(data)
    return len(lines)


if __name__ == "__main__":
    src, dst, *pairs = sys.argv[1:]
    changes = {}
    for p in pairs:
        k, _, v = p.partition("=")
        changes[k] = v
    n = build(src, dst, changes)
    print(f"wrote {os.path.basename(dst)} lines={n} changes={changes}")
