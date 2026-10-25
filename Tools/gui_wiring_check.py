"""Cek wiring GUI: setiap tombol harus DIGAMBAR dan punya HANDLER.

Menangkap bug kelas BTN_CLEAR_WR (handler ada, tombol tak pernah digambar).
Pakai: python Tools/gui_wiring_check.py  (dari folder LAYLA)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(p):
    return open(p, encoding="utf-8", errors="replace").read()


def main():
    cp = read(os.path.join(ROOT, "GUI", "ControlPanel.mqh"))
    btns = re.findall(r'#define\s+(BTN_\w+)\s+"([^"]+)"', cp)
    dash = read(os.path.join(ROOT, "GUI", "StatsDashboard.mqh"))
    main5 = read(os.path.join(ROOT, "YANSTD.mq5"))

    fails = []
    pnames = re.search(r'pnames\[\d+\]\s*=\s*\{([^}]*)\}', dash)
    pnames_set = set(re.findall(r'BTN_\w+', pnames.group(1))) if pnames else set()
    for const, name in btns:
        drawn = (re.search(rf'\b(?:Btn|Rect|Lbl)\s*\(\s*{const}\b', dash)
                 or const in pnames_set)
        handled = re.search(rf'sparam\s*==\s*{const}\b', main5)
        if not drawn:
            fails.append(f"{const} ({name}): tidak pernah digambar")
        if not handled:
            fails.append(f"{const} ({name}): tidak ada handler")
    if fails:
        print("GUI WIRING CHECK: FAIL")
        for f in fails:
            print(" -", f)
        return 1
    print(f"GUI WIRING CHECK: PASS ({len(btns)} tombol: semua digambar + handler)")


if __name__ == "__main__":
    sys.exit(main())
