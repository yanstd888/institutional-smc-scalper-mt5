#!/usr/bin/env python
"""Extract deterministic position/exit attribution from MT5 reports."""
from __future__ import annotations

import argparse
import csv
import html
import json
import math
import re
from collections import defaultdict, deque
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

GRADE_NAMES = {
    0: "S+", 1: "S", 2: "A+", 3: "A", 4: "B+",
    5: "B", 6: "C+", 7: "C", 8: "D+", 9: "D",
}
VARIANT_NAMES = {
    0: "OB_15", 1: "OB_45", 2: "FVG_50",
    3: "FIB_618", 4: "FIB_705", 5: "FIB_790",
}
COMMENT_RE = re.compile(r"^SMC_T(?P<variant>\d+)G(?P<grade>\d+)_B(?P<bucket>-?\d+)_E(?P<event>[A-Z0-9]+)$")
ROW_RE = re.compile(r"<tr[^>]*>(.*?)</tr>", re.I | re.S)
CELL_RE = re.compile(r"<t[dh][^>]*>(.*?)</t[dh]>", re.I | re.S)
TAG_RE = re.compile(r"<[^>]+>")
DATE_FMT = "%Y.%m.%d %H:%M:%S"


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16", errors="replace")
    return raw.decode("utf-8-sig", errors="replace")


def html_rows(path: Path) -> list[list[str]]:
    text = read_text(path)
    rows: list[list[str]] = []
    for block in ROW_RE.findall(text):
        cells = [html.unescape(TAG_RE.sub("", cell)).replace("\xa0", " ").strip()
                 for cell in CELL_RE.findall(block)]
        if cells:
            rows.append(cells)
    return rows


def section_records(rows: list[list[str]], title: str, expected_header: list[str]) -> list[dict[str, str]]:
    try:
        marker = next(i for i, row in enumerate(rows) if row == [title])
    except StopIteration as exc:
        raise ValueError(f"Report section missing: {title}") from exc
    if marker + 1 >= len(rows):
        raise ValueError(f"Report section has no header: {title}")
    header = rows[marker + 1]
    if header != expected_header:
        raise ValueError(f"Unexpected {title} header: {header}")
    records: list[dict[str, str]] = []
    for row in rows[marker + 2:]:
        if row in (["Deals"], ["Orders"], ["Results"]):
            break
        if len(row) != len(header):
            continue
        records.append(dict(zip(header, row)))
    return records


def number(value: str | None) -> float:
    if value is None:
        return 0.0
    clean = value.replace(" ", "").replace("\xa0", "").strip()
    if clean in ("", "-"):
        return 0.0
    return float(clean)


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, DATE_FMT)


def parse_comment(comment: str) -> dict[str, Any]:
    match = COMMENT_RE.match(comment.strip())
    if not match:
        return {"entry_variant": "UNKNOWN", "grade": "UNKNOWN", "brain_bucket": "", "event_token": ""}
    variant = int(match.group("variant"))
    grade = int(match.group("grade"))
    return {
        "entry_variant": VARIANT_NAMES.get(variant, f"T{variant}"),
        "grade": GRADE_NAMES.get(grade, f"G{grade}"),
        "brain_bucket": match.group("bucket"),
        "event_token": match.group("event"),
    }


def mode_from_run(run_id: str, metadata: dict[str, Any]) -> str:
    mode_text = str(metadata.get("Mode", ""))
    if mode_text.endswith("=0") or "M0_HYBRID" in run_id:
        return "HYBRID"
    if mode_text.endswith("=1") or "M1_MSNR_SOFTSMC" in run_id:
        return "MSNR_SOFTSMC"
    if mode_text.endswith("=2") or "M2_SMC_SOFTMSNR" in run_id:
        return "SMC_SOFTMSNR"
    return "UNKNOWN"


def split_from_run(run_id: str) -> str:
    return "VALIDATE" if "VALIDATE" in run_id else ("DEV" if "DEV" in run_id else "OTHER")


def parse_log(path: Path) -> tuple[dict[tuple[str, str, str], list[dict[str, str]]], set[str], set[str], dict[str, dict[str, float]]]:
    placements: dict[tuple[str, str, str], list[dict[str, str]]] = defaultdict(list)
    managed: set[str] = set()
    friday: set[str] = set()
    trade_results: dict[str, dict[str, float]] = {}
    if not path.exists():
        return placements, managed, friday, trade_results
    placement_re = re.compile(
        r"(?P<time>\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*"
        r"YANSTD Auto Limit: (?P<side>BUY|SELL) LIMIT Placed \[(?P<setup>[^\]]+)\] @ (?P<price>[0-9.]+).*"
        r"Lot:(?P<lot>[0-9.]+).*Session=(?P<session>[A-Z_]+).*Score:(?P<score>[0-9.]+).*"
        r"Path=(?P<entry_path>[A-Z_]+).*Source=(?P<entry_source>[A-Z_]+).*Freshness=(?P<entry_freshness>[A-Z_]+)"
        r"(?:.*ParentOBColor=(?P<parent_ob_color>[A-Z_]+).*ExecutionOBColor=(?P<execution_ob_color>[A-Z_]+).*OBColorMarker=(?P<ob_color_marker>[A-Z_]+))?"
    )
    trade_result_re = re.compile(
        r"\[YANSTD TRADE_RESULT\].*position=(?P<position>\d+).*"
        r"initialRiskPrice=(?P<initial_risk_price>-?[0-9.]+).*"
        r"initialRiskMoney=(?P<initial_risk_money>-?[0-9.]+).*"
        r"NetR=(?P<net_r>-?[0-9.]+).*"
        r"MFE=(?P<mfe_r>-?[0-9.]+)R.*"
        r"MAE=(?P<mae_r>-?[0-9.]+)R.*"
        r"maxSpreadPoints=(?P<max_spread_points>-?[0-9.]+)"
    )
    for line in read_text(path).splitlines():
        match = placement_re.search(line)
        if match:
            item = match.groupdict()
            key = (item["time"], item["side"].lower(), f"{number(item['price']):.3f}")
            placements[key].append(item)
        result_match = trade_result_re.search(line)
        if result_match:
            item = result_match.groupdict()
            volume_match = re.search(r"initialVolume=(?P<initial_volume>-?[0-9.]+)", line)
            if volume_match:
                item["initial_volume"] = volume_match.group("initial_volume")
            trade_results[item.pop("position")] = {key: float(value) for key, value in item.items()}
        if "[ManagedClose] Closing position" in line:
            ticket = re.search(r"ticket=(\d+)", line)
            if ticket:
                managed.add(ticket.group(1))
        if "FRIDAY" in line.upper() and "ticket=" in line:
            ticket = re.search(r"ticket=(\d+)", line, re.I)
            if ticket:
                friday.add(ticket.group(1))
    return placements, managed, friday, trade_results


def placement_for(order: dict[str, str], placements: dict[tuple[str, str, str], list[dict[str, str]]]) -> dict[str, str] | None:
    side = "buy" if order["Type"].startswith("buy") else "sell"
    key = (order["Open Time"], side, f"{number(order['Price']):.3f}")
    choices = placements.get(key, [])
    if not choices:
        return None
    target_lot = number(order["Volume"].split("/")[0])
    return min(choices, key=lambda item: abs(number(item["lot"]) - target_lot))


def classify_exit(comment: str, remaining_after: float, position_ticket: str,
                  managed: set[str], friday: set[str]) -> str:
    lowered = comment.strip().lower()
    if lowered.startswith("sl"):
        return "SL"
    if lowered.startswith("tp"):
        return "TP"
    if remaining_after > 1e-8:
        return "TP1_PARTIAL"
    if position_ticket in managed:
        return "TIME_INVALIDATION"
    if position_ticket in friday:
        return "FRIDAY_CLOSE"
    return "EA_MANAGED_EXIT"


def extract_run(run_dir: Path, allow_holdout: bool = False) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, int]]:
    metadata_path = run_dir / "run-metadata.json"
    if not metadata_path.exists():
        raise SystemExit(
            f"HOLDOUT GUARD: refusing to extract {run_dir.name} without run-metadata.json"
        )
    metadata = json.loads(read_text(metadata_path))
    to_date = str(metadata.get("ToDate", "")).strip()
    if not to_date:
        raise SystemExit(
            f"HOLDOUT GUARD: refusing to extract {run_dir.name} without a non-empty ToDate"
        )
    try:
        to_date_value = datetime.strptime(to_date, "%Y.%m.%d")
    except ValueError as exc:
        raise SystemExit(f"Invalid run metadata ToDate in {run_dir.name}: {to_date}") from exc
    if not allow_holdout and to_date_value > datetime(2025, 1, 1):
        raise SystemExit(
            f"HOLDOUT GUARD: refusing to extract {run_dir.name} with ToDate={to_date}; "
            "allowed exclusive end is at most 2025.01.01"
        )
    rows = html_rows(run_dir / "report.htm")
    orders = section_records(rows, "Orders", [
        "Open Time", "Order", "Symbol", "Type", "Volume", "Price", "S / L", "T / P", "Time", "State", "Comment"
    ])
    deals = section_records(rows, "Deals", [
        "Time", "Deal", "Symbol", "Type", "Direction", "Volume", "Price", "Order", "Commission", "Swap", "Profit", "Balance", "Comment"
    ])
    run_id = run_dir.name
    mode = mode_from_run(run_id, metadata)
    split = split_from_run(run_id)
    order_map = {row["Order"]: row for row in orders}
    placements, managed, friday, trade_results = parse_log(run_dir / "tester-log-slice.log")

    positions: list[dict[str, Any]] = []
    exit_legs: list[dict[str, Any]] = []
    active: deque[dict[str, Any]] = deque()
    gaps = {"unmatched_exit_deals": 0, "open_positions_at_end": 0, "entries_without_session": 0}

    for deal in deals:
        direction = deal["Direction"].strip().lower()
        if direction == "in":
            order = order_map.get(deal["Order"], {})
            parsed = parse_comment(deal["Comment"] or order.get("Comment", ""))
            placement = placement_for(order, placements) if order else None
            entry_time = parse_time(deal["Time"])
            volume = number(deal["Volume"])
            position = {
                "run_id": run_id,
                "split": split,
                "mode": mode,
                "position_id": f"{run_id}:{deal['Deal']}",
                "position_ticket": deal["Order"],
                "entry_deal": deal["Deal"],
                "entry_order": deal["Order"],
                "entry_time": deal["Time"],
                "entry_year": entry_time.year,
                "direction": deal["Type"].upper(),
                "entry_volume": volume,
                "entry_price": number(deal["Price"]),
                "initial_sl": number(order.get("S / L", "")),
                "initial_tp": number(order.get("T / P", "")),
                "session": placement["session"] if placement else "UNKNOWN",
                "session_source": "auto-limit-log" if placement else "missing",
                "setup_description": placement["setup"] if placement else "",
                "entry_score": number(placement["score"]) if placement else "",
                "entry_path": placement["entry_path"] if placement else "UNKNOWN",
                "entry_source": placement["entry_source"] if placement else "UNKNOWN",
                "entry_freshness": placement["entry_freshness"] if placement else "UNKNOWN",
                "parent_ob_color": (placement.get("parent_ob_color") or "UNKNOWN") if placement else "UNKNOWN",
                "execution_ob_color": (placement.get("execution_ob_color") or "UNKNOWN") if placement else "UNKNOWN",
                "ob_color_marker": (placement.get("ob_color_marker") or "NONE") if placement else "UNKNOWN",
                **parsed,
                "exit_time": "",
                "holding_seconds": "",
                "exit_reason": "",
                "exit_reason_sequence": "",
                "gross_profit": 0.0,
                "commission": number(deal["Commission"]),
                "swap": number(deal["Swap"]),
                "net_profit": number(deal["Profit"]) + number(deal["Commission"]) + number(deal["Swap"]),
                "exit_leg_count": 0,
                "initial_risk_price": "",
                "initial_risk_money": "",
                "initial_volume": "",
                "net_r": "",
                "mae_r": "",
                "mfe_r": "",
                "max_spread_points": "",
                "join_status": "exact-order-deal",
                "_remaining": volume,
                "_entry_dt": entry_time,
                "_reasons": [],
            }
            if placement is None:
                gaps["entries_without_session"] += 1
            positions.append(position)
            active.append(position)
        elif direction == "out":
            volume_left = number(deal["Volume"])
            while volume_left > 1e-8:
                while active and active[0]["_remaining"] <= 1e-8:
                    active.popleft()
                if not active:
                    gaps["unmatched_exit_deals"] += 1
                    break
                position = active[0]
                allocated = min(volume_left, position["_remaining"])
                remaining_after = position["_remaining"] - allocated
                reason = classify_exit(deal["Comment"], remaining_after, position["position_ticket"], managed, friday)
                exit_dt = parse_time(deal["Time"])
                ratio = allocated / number(deal["Volume"]) if number(deal["Volume"]) > 0 else 1.0
                profit = number(deal["Profit"]) * ratio
                commission = number(deal["Commission"]) * ratio
                swap = number(deal["Swap"]) * ratio
                leg = {
                    "run_id": run_id,
                    "split": split,
                    "mode": mode,
                    "position_id": position["position_id"],
                    "position_ticket": position["position_ticket"],
                    "exit_deal": deal["Deal"],
                    "exit_order": deal["Order"],
                    "exit_time": deal["Time"],
                    "exit_year": exit_dt.year,
                    "direction": position["direction"],
                    "exit_volume": allocated,
                    "exit_price": number(deal["Price"]),
                    "profit": profit,
                    "commission": commission,
                    "swap": swap,
                    "net_profit": profit + commission + swap,
                    "exit_reason": reason,
                    "holding_seconds": int((exit_dt - position["_entry_dt"]).total_seconds()),
                    "comment": deal["Comment"],
                    "join_status": "volume-ledger",
                }
                exit_legs.append(leg)
                position["_remaining"] = remaining_after
                position["gross_profit"] += profit
                position["commission"] += commission
                position["swap"] += swap
                position["net_profit"] += profit + commission + swap
                position["exit_leg_count"] += 1
                position["exit_time"] = deal["Time"]
                position["holding_seconds"] = int((exit_dt - position["_entry_dt"]).total_seconds())
                position["exit_reason"] = reason
                position["_reasons"].append(reason)
                volume_left -= allocated
                if remaining_after <= 1e-8:
                    active.popleft()

    gaps["open_positions_at_end"] = sum(1 for item in active if item["_remaining"] > 1e-8)
    for position in positions:
        telemetry = trade_results.get(str(position["position_ticket"]))
        if telemetry:
            position.update(telemetry)
        position["exit_reason_sequence"] = ">".join(position.pop("_reasons"))
        position.pop("_remaining", None)
        position.pop("_entry_dt", None)
    return positions, exit_legs, gaps


def profit_metrics(values: Iterable[float]) -> dict[str, Any]:
    vals = list(values)
    gross_win = sum(value for value in vals if value > 0)
    gross_loss = sum(value for value in vals if value < 0)
    return {
        "count": len(vals),
        "wins": sum(1 for value in vals if value > 0),
        "losses": sum(1 for value in vals if value < 0),
        "net_profit": round(sum(vals), 8),
        "profit_factor": (round(gross_win / abs(gross_loss), 8) if gross_loss < 0 else None),
        "expectancy": (round(sum(vals) / len(vals), 8) if vals else None),
    }


def attribution_rows(positions: list[dict[str, Any]], legs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for dimension in ("entry_year", "direction", "session", "grade", "entry_variant", "setup_description",
                      "entry_path", "entry_source", "entry_freshness", "ob_color_marker"):
        groups: dict[tuple[str, str, str, str], list[float]] = defaultdict(list)
        for position in positions:
            key = (position["run_id"], position["split"], position["mode"], str(position[dimension]))
            groups[key].append(float(position["net_profit"]))
        for (run_id, split, mode, value), profits in sorted(groups.items()):
            output.append({"run_id": run_id, "split": split, "mode": mode, "unit": "position",
                           "dimension": dimension, "value": value, **profit_metrics(profits)})
    groups: dict[tuple[str, str, str, str], list[float]] = defaultdict(list)
    for leg in legs:
        key = (leg["run_id"], leg["split"], leg["mode"], leg["exit_reason"])
        groups[key].append(float(leg["net_profit"]))
    for (run_id, split, mode, value), profits in sorted(groups.items()):
        output.append({"run_id": run_id, "split": split, "mode": mode, "unit": "exit_leg",
                       "dimension": "exit_reason", "value": value, **profit_metrics(profits)})
    return output


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fields = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs-root", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--run-id-prefix", default="", help="only extract run directories whose names start with this prefix")
    parser.add_argument("--allow-holdout", action="store_true", help="Allow extraction of runs beyond 2025.01.01 (exploratory only)")
    args = parser.parse_args()
    runs_root = Path(args.runs_root)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    all_positions: list[dict[str, Any]] = []
    all_legs: list[dict[str, Any]] = []
    gaps_by_run: dict[str, dict[str, int]] = {}
    run_dirs = sorted(path for path in runs_root.iterdir()
                      if path.is_dir() and (path / "report.htm").exists()
                      and path.name.startswith(args.run_id_prefix))
    if not run_dirs:
        raise SystemExit(f"No MT5 run reports found under {runs_root}")
    for run_dir in run_dirs:
        positions, legs, gaps = extract_run(run_dir, allow_holdout=args.allow_holdout)
        all_positions.extend(positions)
        all_legs.extend(legs)
        gaps_by_run[run_dir.name] = gaps

    attrs = attribution_rows(all_positions, all_legs)
    write_csv(output_dir / "positions.csv", all_positions)
    write_csv(output_dir / "exit_legs.csv", all_legs)
    write_csv(output_dir / "attribution_by_dimension.csv", attrs)
    summary = {
        "schema_version": 1,
        "runs": len(run_dirs),
        "positions": len(all_positions),
        "exit_legs": len(all_legs),
        "net_profit_from_positions": round(sum(float(row["net_profit"]) for row in all_positions), 8),
        "gaps_by_run": gaps_by_run,
        "mae_mfe_status": "available from unconditional TRADE_RESULT telemetry" if all_positions and all(row.get("mfe_r") not in (None, "") and row.get("mae_r") not in (None, "") for row in all_positions) else "unavailable",
        "files": ["positions.csv", "exit_legs.csv", "attribution_by_dimension.csv"],
    }
    (output_dir / "attribution_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"ATTRIBUTION EXTRACTED: runs={len(run_dirs)} positions={len(all_positions)} exit_legs={len(all_legs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
