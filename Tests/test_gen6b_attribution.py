import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("attr", ROOT / "Tools" / "extract_backtest_attribution.py")
attr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(attr)

with tempfile.TemporaryDirectory() as tmp:
    log = Path(tmp) / "tester.log"
    log.write_text(
        "2026.01.02 03:04:05 YANSTD Auto Limit: BUY LIMIT Placed [OB 15%] @ 2500.123 | SL:2490 (10p) | Lot:0.10 | Session=SESSION_LONDON | Score:75.0 | Path=CONFIRMED | Source=OB | Freshness=RETESTED\n"
        "2026.01.02 03:05:05 YANSTD Auto Limit: SELL LIMIT Placed [FVG 50%] @ 2501.123 | SL:2510 (10p) | Lot:0.10 | Session=SESSION_NEW_YORK | Score:70.0 | Path=FALLBACK | Source=FVG | Freshness=FRESH\n"
        "2026.01.02 03:06:05 YANSTD Auto Limit: BUY LIMIT Placed [Fib 70.5%] @ 2499.123 | SL:2490 (10p) | Lot:0.10 | Session=SESSION_ASIA | Score:65.0 | Path=DIRECT | Source=FIB | Freshness=FRESH\n",
        encoding="utf-8",
    )
    placements, _, _, _ = attr.parse_log(log)
    rows = [item for values in placements.values() for item in values]
    assert {r["entry_path"] for r in rows} == {"CONFIRMED", "FALLBACK", "DIRECT"}
    assert {r["entry_source"] for r in rows} == {"OB", "FVG", "FIB"}
    assert {r["entry_freshness"] for r in rows} == {"FRESH", "RETESTED"}
print("TEST-GEN6B-ATTRIBUTION: PASS")
