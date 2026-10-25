# Contributing to YANSTD MT5 EA

Thank you for contributing to YANSTD! We welcome bug fixes, optimization hypotheses, and clean architectural improvements.

## Development Standards

### 1. Compile Discipline
- Any changes to `YANSTD.mq5`, `Modules/*.mqh`, or `GUI/*.mqh` must compile in MetaEditor with **0 errors and 0 warnings**.
- Successful `.ex5` generation with compiler warnings is considered a test failure.

### 2. Schema Contract Invariant
- The EA input schema currently has **204 unique input parameters**.
- Do not add or remove `input` declarations lightly; doing so modifies the preset contract across all `.set` files.
- Prefer updating existing enums or using conditional logic before expanding the input schema.

### 3. Backtest Verification
- Every proposed parameter change or algorithmic refinement must be backed by empirical evidence:
  - Minimum 5-year historical backtest on `XAUUSD` or target symbol with real ticks.
  - Verification of Profit Factor (PF >= 1.30), maximum equity drawdown (DD <= 15%), and minimum sample size (n >= 500 trades).
  - Walk-forward or out-of-sample validation.

## Pull Request Process

1. Fork the repository and create your feature branch from `main`.
2. Ensure all MQL5 modules pass compilation.
3. If introducing a new `.set` preset, validate it using `python Tools/mkpreset.py`.
4. Open a PR with an evidence table (Net Profit, Profit Factor, Max Drawdown, Total Trades) comparing your branch against the baseline champion.
