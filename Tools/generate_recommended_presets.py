"""Generate complete recommended and 2007-2026 protocol presets.

The canonical 199-key preset is cloned in source declaration order. Generation
fails before writing anything if the source schema, canonical preset, overrides,
or output files are inconsistent.
"""
from __future__ import annotations

import re
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EA = ROOT / "YANSTD.mq5"
BASE = ROOT / "Presets" / "SET - GROK 4.6" / "YANSTD_HYBRID_BT_MEDIUM.set"
OUT = ROOT / "Presets" / "RECOMMENDED 2007-2026"
PROTOCOL = OUT / "PROTOCOL"

INPUT_RE = re.compile(
    r"^\s*input\s+(?!group\b)[A-Za-z_][A-Za-z0-9_]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*=",
    re.MULTILINE,
)
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


def source_inputs() -> list[str]:
    names = INPUT_RE.findall(EA.read_text(encoding="utf-8-sig"))
    if len(names) != 199 or len(set(names)) != 199:
        raise RuntimeError(f"expected 199 unique EA inputs, got {len(names)}/{len(set(names))}")
    return names


def parse_base() -> tuple[list[str], OrderedDict[str, str]]:
    lines = BASE.read_text(encoding="utf-8-sig").splitlines()
    values: OrderedDict[str, str] = OrderedDict()
    for line in lines:
        match = ASSIGN_RE.match(line)
        if match:
            if match.group(1) in values:
                raise RuntimeError(f"duplicate canonical key: {match.group(1)}")
            values[match.group(1)] = match.group(2)
    return lines, values


def render(base_lines: list[str], values: OrderedDict[str, str], overrides: dict[str, str], title: str) -> str:
    unknown = sorted(set(overrides) - set(values))
    if unknown:
        raise RuntimeError(f"unknown override(s) in {title}: {unknown}")
    seen: set[str] = set()
    output = [
        f"; YANSTD v4.47.16 — {title}",
        "; Generated from the audited 199-input canonical preset.",
        "; Dates, real-tick model, delay, deposit and leverage are configured in MT5 Tester, not this file.",
        "; Do not optimize or claim profitability from this preset before completing README_BACKTEST_2007_2026.md.",
        "; Brain namespaces are mode/protocol-specific; MagicNumber alone does not isolate Brain files.",
    ]
    for line in base_lines:
        match = ASSIGN_RE.match(line)
        if not match:
            continue
        key = match.group(1)
        value = overrides.get(key, values[key])
        output.append(f"{key}={value}")
        seen.add(key)
    if seen != set(values):
        raise RuntimeError(f"rendered key mismatch in {title}")
    return "\n".join(output) + "\n"


def validate_output(text: str, expected_order: list[str], title: str) -> None:
    parsed: list[tuple[str, str]] = []
    for line in text.splitlines():
        match = ASSIGN_RE.match(line)
        if match:
            parsed.append((match.group(1), match.group(2)))
    keys = [key for key, _ in parsed]
    if len(keys) != 199 or len(set(keys)) != 199:
        raise RuntimeError(f"{title}: expected 199 unique keys, got {len(keys)}/{len(set(keys))}")
    if keys != expected_order:
        raise RuntimeError(f"{title}: key order differs from YANSTD.mq5")


def main() -> None:
    expected = source_inputs()
    base_lines, base_values = parse_base()
    if list(base_values) != expected:
        raise RuntimeError("canonical preset does not match EA input names/order")

    modes = {
        0: ("M0_HYBRID", "XAUUSD_HYBRID_R1", "1.50", "45.0"),
        1: ("M1_MSNR_SOFTSMC", "XAUUSD_MSNR_R1", "1.50", "55.0"),
        2: ("M2_SMC_SOFTMSNR", "XAUUSD_SMC_R1", "2.50", "45.0"),
    }
    common = {
        "InpRiskPercent": "1.0",
        "InpMaxAggregateRiskPct": "3.0",
        "InpMaxDailyLossPct": "4.0",
        "InpMaxEquityDDPct": "12.0",
        "InpRejectBelowMinLot": "1",
        "InpMultiLayerEntry": "0",
        "InpMaxActivePositions": "1",
        "inp_max_spread": "350",
        "InpBrainEventJournalInTester": "0",
        "InpDiagnosticIntervalMinutes": "60",
    }

    specs: list[tuple[Path, dict[str, str], str]] = []
    for mode, (label, brain_key, distance, score) in modes.items():
        mode_common = {
            **common,
            "InpSetupMode": str(mode),
            "InpMaxEntryDistanceATR": distance,
            "InpMinimumSoftScore": score,
            "InpBrainInstrumentKey": brain_key,
        }
        specs.append((
            OUT / f"YANSTD_XAUUSD_{label}_BT_BASELINE_R1.set",
            {
                **mode_common,
                "InpMagicNumber": str(470001 + mode * 1000),
                "InpTesterExecutionMode": "1",
                "InpStrictValidationLearning": "0",
                "InpUseSmartBrain": "0",
                "InpAILearning": "0",
                "InpDataCollectionMode": "0",
                "InpEnablePushAlerts": "0",
                "InpShowDashboard": "0",
            },
            f"{label} BACKTEST BASELINE R1",
        ))
        specs.append((
            OUT / f"YANSTD_XAUUSD_{label}_LIVE_R1.set",
            {
                **mode_common,
                "InpMagicNumber": str(470000 + mode * 1000),
                "InpTesterExecutionMode": "2",
                "InpStrictValidationLearning": "0",
                "InpUseSmartBrain": "1",
                "InpAILearning": "1",
                "InpDataCollectionMode": "0",
                "InpEnablePushAlerts": "1",
                "InpShowDashboard": "1",
            },
            f"{label} LIVE/DEMO R1",
        ))

    stages = {
        1: ("SMOKE_2022Q4", "1", "0", "0", "0", "0"),
        2: ("TRAIN_DEV_2007_2022", "0", "1", "1", "1", "1"),
        3: ("VALIDATE_BASELINE_2023_2024", "1", "0", "0", "0", "0"),
        4: ("VALIDATE_BRAIN_2023_2024", "1", "1", "0", "0", "0"),
        5: ("TRAIN_FINAL_2007_2024", "0", "1", "1", "1", "1"),
        6: ("HOLDOUT_BASELINE_2025_2026", "1", "0", "0", "0", "0"),
        7: ("HOLDOUT_BRAIN_2025_2026", "1", "1", "0", "0", "0"),
        8: ("STRESS500_BRAIN_2025_2026", "1", "1", "0", "0", "0"),
    }
    research_common = {
        **common,
        "InpMaxDailyLossPct": "0.0",
        "InpMaxEquityDDPct": "0.0",
        "InpEnablePushAlerts": "0",
        "InpShowDashboard": "0",
        "InpBrainEventJournalInTester": "0",
    }
    for mode, (label, _live_key, distance, score) in modes.items():
        for stage, (stage_name, execution, brain, learning, strict_learning, collection) in stages.items():
            specs.append((
                PROTOCOL / f"YANSTD_{label}_P{stage:02d}_{stage_name}.set",
                {
                    **research_common,
                    "InpSetupMode": str(mode),
                    "InpMagicNumber": str(480000 + mode * 100 + stage),
                    "InpMaxEntryDistanceATR": distance,
                    "InpMinimumSoftScore": score,
                    "InpBrainInstrumentKey": f"XAUUSD_{label}_BTGEN1",
                    "InpTesterExecutionMode": execution,
                    "InpUseSmartBrain": brain,
                    "InpAILearning": learning,
                    "InpStrictValidationLearning": strict_learning,
                    "InpDataCollectionMode": collection,
                },
                f"{label} PROTOCOL P{stage:02d} {stage_name}",
            ))

    rendered: list[tuple[Path, str]] = []
    magics: set[str] = set()
    for path, overrides, title in specs:
        text = render(base_lines, base_values, overrides, title)
        validate_output(text, expected, title)
        magic = overrides["InpMagicNumber"]
        if magic in magics:
            raise RuntimeError(f"duplicate generated magic number: {magic}")
        magics.add(magic)
        rendered.append((path, text))

    for path, text in rendered:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
    print(f"Generated {len(rendered)} presets; each has 199/199 unique inputs; {len(magics)} unique magic numbers.")


if __name__ == "__main__":
    main()
