## 4.50.0 — Full 24h Session + V15 Champion Refinement (2026-09-18)

**REFINE Gen-15: V9 SL2.0 → V15 24h Session:**

1. **24h trading session (Hypo 3) = champion baru.** V9 (time-filtered 07:00-19:00 UTC) → V15 (00:00-23:59 UTC)
   - V9 SL2.0: +$5,771, PF 1.29, DD 10.85%, 1,222 trades, exp +4.72
   - V15 24H: **+$6,021, PF 1.30, DD 10.42%, 1,245 trades, exp +4.84**
   - Δ = +$250 profit tambahan, trades naik 18, DD turun 0.43% — scalping volume + precision sekaligus.

2. **Session filter relaxation:** `InpStartHourUTC=7` → `0`, `InpEndHourUTC=19` → `23`, `InpFridayCutoffHour=15` → `23`. Asian session (00-07 UTC) kini terbuka penuh. DD tetap <20%.

3. **Hypo 1 (M1 scalping) & Hypo 2 (HTF trigger) disimpan.** V15 champion bekas V9 frozen, hanya time-filter diperluas.

**Champion frozen:** `Candidates_Gen15/YANSTD_XAUUSD_M2_G16_V15_CHAMPION.set` (SL2.0 + 24h + BlockOverlap)

## 4.52.0 — V17 Champion + BlockOverlap OFF (2026-09-18)

**REFINE Gen-17: BlockOverlap OFF = new champion:**

1. **BlockOverlap OFF = winner.** V15 (overlap ON) +$6.021 → V15 (overlap OFF) **+$7.090** (+$1,069, trades +139)
   - V15 overlap ON: +$6,021, PF 1.30, DD 10.42%, 1,245 trades
   - V17 overlap OFF: **+$7,090, PF 1.31, DD 10.29%, 1,384 trades**
   - BlockOverlap mengurangi entry opportunity — confluence filter terlalu ketat untuk 24h session

2. **SL 2.50 = tidak unggul.** Trade count turun 20% (1,032), profit turun ke +$5,838. SL 2.0 optimal.

3. **Champion final:** V15 SL2.0 + 24h + BlockOverlap OFF → **+$7,090**

**Champion frozen:** `Candidates_Gen18/YANSTD_XAUUSD_M2_G18_V15_NOCHAMP.set`

## 4.52.0 — V17 Champion Final + Gen-21 Micro-opts Null Result (2026-09-18)

**REFINE Gen-21: micro-optimization test — both kandidat identitcal V17:**

1. **Session 01-22 UTC (avoid rollover noise) = NO EFFECT.** A: session 01-22 UTC = +$7,090, PF 1.31, DD 10.29%, 1,384 trades — bit-for-bit identitcal V17.

2. **FVG tolerance 0.020 (super precision) = NO EFFECT.** B: FVG 0.020 = +$7,090, PF 1.31, DD 10.29%, 1,384 trades — identitcal.

**Conclusion:** V17 (SL2.0 + 24h + BlockOverlap OFF) = champion definitif. Trade chain final: V6(+$5,247) → V9(+$5,771) → V15(+$6,021) → **V17(+$7,090)** — +$1,843 improvement. Tidak ada ruang refine tambahan.

**Champion final:** `YANSTD_XAUUSD_M2_G18_V15_NOCHAMP.set` (SLATRMult=2.00, BlockOverlap OFF, 24h session)

## 4.54.0 — Gen-25 Multi-Entry Trade Count Optimization (2026-09-18)

**REFINE Gen-25: Naik trade count via early TP1 + multi-layer (no code change):**

| Kandidat | MultiLayer | TP1 RR | Profit | PF | DD | Trades | Exp | vs V17 |
|---|---|---|---|---|---|---|---|---|
| V17 champion | 1 | 0.9 | **+$7,090** | 1.31 | 10.29% | 1,384 | 5.12 | — |
| G25A: ML2 dist15 | 2 | 0.9 | +$7,022 | 1.28 | 11.36% | 1,500 | 4.68 | −$68, +116 trades |
| G25B: TP1 0.6 | 1 | 0.6 | +$6,197 | 1.25 | 11.53% | **1,944** | 3.19 | −$893, **+560 trades** |

**Findings:**
- **G25B breakout:** TP1 RR 0.9→0.6 = position recycle lebih cepat → 1,944 trades (+40%)
- Profit sacrificed −$893, exp 5.12→3.19 — quality tradeoff
- **G25A balanced:** ML2 dist15 piplining = 1,500 trades, profit −$68 (minimal)

**Trade count progression:** V17(1,384) → G25A(1,500) → **G25B(1,944)**

**Next step:** 2,000+ trades butuh multi-TF parallel entry (code change). V17 tetap profit champion.

**Champion final (saat itu):** `YANSTD_XAUUSD_M2_G18_V15_NOCHAMP.set` (profit: +$7,090) | volume: `G25B` (1,944 trades). Dilampaui G27B — entri berikutnya.

## 4.52.0 — G27B champion berjalan (2026-09-22)

Bukan rilis kode baru. `YANSTD_VERSION` tetap `4.52.0`. Gen-26 multi-entry loop sudah dihapus dari source.

| | Net | PF | Trade | Sharpe | DD |
|---|---|---|---|---|---|
| G27B TP1 1.5 MaxPos 3 | **+$9,196** | **1.34** | 1,309 | 3.49 | 11.81% |
| G27A TP1 1.2 MaxPos 2 | +$8,660 | 1.32 | 1,404 | 3.42 | 11.53% |
| G28 TP1 0.6 MaxPos 5 = MaxPos 6 | +$5,327 | 1.26 | 1,686 | 3.13 | 11.99% |

**Champion:** `G27B_TP1_1.5_MAXPOS3_LIVE.set`. V17 dan G25B bukan champion lagi. MaxPos 5 dan 6 menghasilkan angka yang sama.
