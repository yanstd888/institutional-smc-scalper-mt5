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
        "2026.01.02 03:04:05 YANSTD Auto Limit: BUY LIMIT Placed [OB 45%] @ 2500.123 | SL:2490 (10p) | Lot:0.10 | Session=SESSION_LONDON | Score:75.0 | Path=CONFIRMED | Source=OB | Freshness=RETESTED | ParentOBColor=SAME | ExecutionOBColor=OPPOSITE | OBColorMarker=OPPOSITE\n"
        "2026.01.02 03:05:05 YANSTD Auto Limit: SELL LIMIT Placed [FVG 50%] @ 2501.123 | SL:2510 (10p) | Lot:0.10 | Session=SESSION_NEW_YORK | Score:70.0 | Path=FALLBACK | Source=FVG | Freshness=FRESH | ParentOBColor=OPPOSITE | ExecutionOBColor=UNKNOWN | OBColorMarker=NONE\n"
        "2026.01.02 03:06:05 YANSTD Auto Limit: BUY LIMIT Placed [OB 15%] @ 2499.123 | SL:2490 (10p) | Lot:0.10 | Session=SESSION_ASIA | Score:65.0 | Path=FALLBACK | Source=OB | Freshness=FRESH | ParentOBColor=OPPOSITE | ExecutionOBColor=UNKNOWN | OBColorMarker=OPPOSITE\n",
        encoding="utf-8",
    )
    placements, _, _, _ = attr.parse_log(log)
    rows = sorted((item for values in placements.values() for item in values), key=lambda r: r["time"])
    assert [(r["parent_ob_color"], r["execution_ob_color"], r["ob_color_marker"]) for r in rows] == [
        ("SAME", "OPPOSITE", "OPPOSITE"),
        ("OPPOSITE", "UNKNOWN", "NONE"),
        ("OPPOSITE", "UNKNOWN", "OPPOSITE"),
    ]
    positions = [{"run_id": "R", "split": "DEV", "mode": "HYBRID", "net_profit": 1.0,
                  "entry_year": 2026, "direction": "BUY", "session": "SESSION_LONDON",
                  "grade": "A", "entry_variant": "OB_45", "setup_description": "OB 45%",
                  "entry_path": "CONFIRMED", "entry_source": "OB", "entry_freshness": "RETESTED",
                  "ob_color_marker": "OPPOSITE"}]
    assert any(row["dimension"] == "ob_color_marker" for row in attr.attribution_rows(positions, []))
print("TEST-OB-COLOR-ATTRIBUTION: PASS")
