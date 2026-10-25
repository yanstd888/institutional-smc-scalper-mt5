#!/usr/bin/env python
"""Apply analytical cost stress to reconstructed YANSTD positions.

What this is: the Strategy Tester runs used real Dukascopy Bid/Ask ticks,
zero commission, and ExecutionMode=0. The tester custom symbol carries zero
swap, and MT5 has no native forced-adverse-slippage control (InpSlippage is
only a maximum allowed deviation). This tool therefore applies the
preregistered conservative cost contract ANALYTICALLY on top of raw
tester P/L so raw-vs-net-after-cost is explicit and auditable:

- Swap:  BUY -30 USD / lot / night, SELL -15 USD / lot / night,
         triple charge when the rollover day is Wednesday (UTC+0, DST OFF).
- Slippage: 0 / 100 / 200 MT5 points, applied as a round-turn surcharge
         (entry fill + exit fill) using point=0.001 and
         100 USD per 1.00 price move per 1.0 lot (standard 100 oz XAU).
         100 points = 0.100 price = 10 USD per lot per fill.

Delay (0/100/300/500 ms) is NOT analytical: it must be executed in the
tester via ExecutionMode. See Tools/Run-YANSTDBacktestJob.ps1 -DelayMs.

Midnight convention (UTC+0, DST OFF): for each calendar midnight strictly
after the entry date and at-or-before the exit timestamp, one night is
charged to the day that just ended; if that day is a Wednesday the charge
is tripled (3 nights).
"""
from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timedelta
from pathlib import Path

TIME_FORMATS = ("%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y.%m.%d %H:%M", "%Y-%m-%dT%H:%M:%S")


def parse_time(value: str) -> datetime:
    text = value.strip().strip('"').strip("'")
    for fmt in TIME_FORMATS:
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    raise ValueError(f"Unparseable MT5 timestamp: {value!r}")


def nights_charged(entry: datetime, exit: datetime) -> int:
    """Count charged nights between entry and exit (UTC, DST OFF)."""
    if exit <= entry:
        return 0
    charged = 0
    day = entry.date() + timedelta(days=1)
    while datetime.combine(day, datetime.min.time()) <= exit:
        ended = day - timedelta(days=1)
        # 1970-01-01 was Thursday; Python weekday(): Monday=0..Sunday=6.
        charged += 3 if ended.weekday() == 2 else 1  # Wednesday -> triple
        day += timedelta(days=1)
    return charged


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--positions-csv", required=True)
    parser.add_argument("--output-csv", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--swap-buy", type=float, default=-30.0)
    parser.add_argument("--swap-sell", type=float, default=-15.0)
    parser.add_argument("--point", type=float, default=0.001)
    parser.add_argument("--usd-per-price-per-lot", type=float, default=100.0)
    args = parser.parse_args()

    positions_path = Path(args.positions_csv)
    out_csv = Path(args.output_csv)
    summary_path = Path(args.summary_json)

    per_fill_per_lot = {n: n * args.point * args.usd_per_price_per_lot for n in (0, 100, 200)}

    rows_out = []
    totals = {"positions": 0, "raw": 0.0, "swap": 0.0, "after_swap": 0.0,
              "slip100": 0.0, "slip200": 0.0,
              "after_swap_slip100": 0.0, "after_swap_slip200": 0.0}
    per_run: dict[str, dict[str, float]] = {}

    with positions_path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"run_id", "position_id", "direction", "entry_volume",
                    "entry_time", "exit_time", "net_profit"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"positions CSV missing columns: {sorted(missing)}")
        for row in reader:
            direction = row["direction"].strip().upper()
            if direction not in ("BUY", "SELL"):
                raise SystemExit(f"Unknown direction: {row['direction']!r}")
            volume = float(row["entry_volume"])
            raw = float(row["net_profit"])
            entry = parse_time(row["entry_time"])
            exit = parse_time(row["exit_time"])
            nights = nights_charged(entry, exit)
            rate = args.swap_buy if direction == "BUY" else args.swap_sell
            swap_cost = round(volume * nights * rate, 2)
            after_swap = round(raw + swap_cost, 2)
            slip100 = round(2 * per_fill_per_lot[100] * volume, 2)
            slip200 = round(2 * per_fill_per_lot[200] * volume, 2)
            after_slip100 = round(after_swap - slip100, 2)
            after_slip200 = round(after_swap - slip200, 2)
            rows_out.append({
                "run_id": row["run_id"],
                "position_id": row["position_id"],
                "direction": direction,
                "entry_volume": volume,
                "nights_charged": nights,
                "net_raw": raw,
                "swap_cost_usd": swap_cost,
                "net_after_swap": after_swap,
                "slip_cost_100": slip100,
                "slip_cost_200": slip200,
                "net_after_swap_slip100": after_slip100,
                "net_after_swap_slip200": after_slip200,
            })
            totals["positions"] += 1
            totals["raw"] += raw
            totals["swap"] += swap_cost
            totals["after_swap"] += after_swap
            totals["slip100"] += slip100
            totals["slip200"] += slip200
            totals["after_swap_slip100"] += after_slip100
            totals["after_swap_slip200"] += after_slip200
            run = per_run.setdefault(row["run_id"], {"positions": 0, "raw": 0.0,
                                                     "after_swap": 0.0,
                                                     "after_swap_slip100": 0.0,
                                                     "after_swap_slip200": 0.0})
            run["positions"] += 1
            run["raw"] += raw
            run["after_swap"] += after_swap
            run["after_swap_slip100"] += after_slip100
            run["after_swap_slip200"] += after_slip200

    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows_out[0].keys()) if rows_out else [])
        writer.writeheader()
        writer.writerows(rows_out)

    summary = {
        "schema_version": 1,
        "assumptions": {
            "spread": "real Dukascopy Bid/Ask ticks (tester baseline)",
            "commission_usd_per_lot_roundturn": 0.0,
            "swap_buy_usd_per_lot_night": args.swap_buy,
            "swap_sell_usd_per_lot_night": args.swap_sell,
            "triple_swap_day": "Wednesday (UTC+0, DST OFF)",
            "slippage_points": [0, 100, 200],
            "slippage_method": "analytical round-turn surcharge (entry+exit fills)",
            "point": args.point,
            "usd_per_price_per_lot": args.usd_per_price_per_lot,
            "delay_ms": "NOT analytical; execute via tester ExecutionMode",
        },
        "totals": {k: (v if k == "positions" else round(v, 2)) for k, v in totals.items()},
        "per_run": {run_id: {k: (v if k == "positions" else round(v, 2)) for k, v in vals.items()}
                    for run_id, vals in sorted(per_run.items())},
    }
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"COST STRESS APPLIED: positions={totals['positions']} "
          f"raw={totals['raw']:.2f} after_swap={totals['after_swap']:.2f} "
          f"slip100={totals['after_swap_slip100']:.2f} slip200={totals['after_swap_slip200']:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
