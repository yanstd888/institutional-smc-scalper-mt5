# YANSTD EA — System Architecture & Development Conventions

> **Tujuan dokumen ini:** menjadi "peta" tunggal untuk YANSTD EA (MetaTrader 5) supaya
> siapapun/vendor AI apapun (Claude, GPT, Gemini, dll.) yang melanjutkan development bisa
> langsung mengikuti pola yang sudah ada — **tanpa** menebak ulang arsitektur atau
> menciptakan konvensi baru yang bertabrakan dengan kode lama. Tempelkan file ini di awal
> setiap sesi/prompt ketika berpindah vendor AI.
>
> Dokumen ini berisi **aturan dan pola yang berlaku sekarang**, bukan riwayat perubahan.
> Jejak audit ("apa yang salah dan kenapa diperbaiki") ada di [CHANGELOG.md](CHANGELOG.md).
> Source hanya menyimpan rationale desain yang masih dipakai maintainer.
>
> **Identitas rilis aktif:** `#property version` **4.52** / `YANSTD_VERSION` **`4.52.0`** (2026-09-18). Champion berjalan: **G27B** (TP1RR 1.5, MaxPos 3, +$9,196, PF 1.34, 1,309 trade, 2020.01–2026.08) — lihat `FINAL.md` dan §63. V17 (+$7,090) adalah juara Gen-17, sudah dilampaui. Titik
> identitas disinkronkan oleh `Tools/sync_version.py` dari `YANSTD_VERSION`. Exit/SL/grade: §33. Holdout/recovery/throttle: §34. Setup mode: §10 overlay + `InpSetupMode`. v4.46 jam/SL/log/mode: `CHANGELOG.md`. v4.47 audit CRITICAL+HIGH: §37. Audit lanjutan H/M/L: §40. OTE 0.786 + QML close: §41. Audit 4.47.4 (freshness Mode 2, FVG fill, desync hard-stop): §42. Audit 4.47.5 (ADX fail-closed, OnTimer mark, alert cap, lot reject): §43. Mode 2 grade D palsu: §44. Visual HH/HL/LH/LL + BOS/CHoCH: §45. Preset .set: §46. Kontrak sizing grade maksimum 2.00x (koreksi H-2): §47. FVG wajib pada OB M5+, opsional pada M3 (H3-FVG): §48. FVG lifecycle: satu aturan CE 50%, hapus grace 80% (koreksi §42): §49. ATR historis per-shift untuk klasifikasi zona (H1): §50. Target STAGED/FIXED_RR tidak pulih setelah restart (H4): §51. Tooling: §26. GUI: §10 + §27. 24h Session V15 Champion: §60. V17 BlockOverlap OFF: §62. G27B champion: §63. Filter Overlap + whitelist variant MSNR: §59.

---

## 1. Ringkasan Sistem

YANSTD adalah Expert Advisor (EA) MT5 auto-trading dengan strategi hybrid MSNR + SMC (Simplified):

- **[Bias Arah] King SNR (default H4/H1, v4.34 — lihat §17.7 + §23):** King SNR yang belum termitigasi menentukan arah (Buy/Sell) yang diizinkan untuk dicari entry-nya. Bukan lagi tempat entry presisi, melainkan filter bias arah HTF dengan invalidasi buffer dan zona yang diskalakan secara dinamis oleh ATR. TF-nya genuinely configurable lewat `InpKingSNR_PrimaryTF`/`InpKingSNR_SecondaryTF` (default **H4 primary / H1 fallback**, sesuai rumus-teknis Tahap 0: H4 menang jika keduanya aktif).
- **[Zona Kandidat / Layer 1 MSNR]:**
  - Peta primer: A-level, V-level, OCL/gap, SBR/RBS, dan QML. King SNR tetap filter cerita HTF, bukan zona entry.
  - OB / FVG M15 adalah Layer 2 (eksekusi/konfirmasi), bukan pengganti peta MSNR.
  - QML memakai pita shoulder `0.10 × ATR(M15,14)` dan menyimpan harga head untuk SL. Sejak v4.47.3, tembus first high/low QML wajib dikonfirmasi **close** (bukan wick pivot ke-4) — lihat §41.
  - Default OTE ketat: `InpRequireZoneOTE=true`, window midpoint **0.618–0.786** (`InpMSNROTEFibMin` / `InpMSNROTEFibMax`; v4.47.3). Token varian deep tetap `FIB_790`.
- **[Overlap Logic Gate]:**
  - Setiap zona peta Layer 1 yang bisa di-entry wajib beririsan dengan OB/FVG M15 jika `InpUseLayer2M15Gate=true`.
  - Key level tipis memakai overlap vs kotak M5; QML lebar tetap bisa memakai containment.
- **[Refinement] M5 Refinement (Layer 3):** Mempersempit zona M15 yang sudah qualified ke ukuran OB M5 yang belum termitigasi. Sejak v4.34 default-nya **containment ketat** `Zona_OB_M5 ⊆ Zona_M15` (`InpRequireM5ContainedInM15=true`); `false` mengembalikan overlap + toleransi ATR.
- **[Trigger] M3 Confirmation Trigger (Layer 4):** Sweep M3 dan CHoCH M3 memberi konteks kualitas tertinggi di dalam Zona_Final. Jika `InpScanAllPOIsWhenNoTrigger=true` (default), ketiadaan trigger itu tidak membatalkan retest: EA tetap boleh memasang limit pada OB/FVG parent yang masih valid. Set `false` untuk membuat sweep+CHoCH menjadi gerbang wajib. `InpRequireM3Sweep=true` tetap mengatur trigger M3 ketika trigger itu dipakai; set `false` untuk CHoCH-only.
- **[SL / TP] v4.46 `EXIT_STRUCTURAL_POI`:** SL = struktur zone + buffer ATR, lalu batas volatilitas **0,35–2,50 × ATR M15** (`InpUseATRStopBounds`). `InpMinSLPips` / `InpMaxSLPips` default **0 = off** (bukan 25–70). Isi angka pip hanya jika ingin pagar cadangan di atas ATR. TP broker = target MSNR lawan M15 (`GetStructuralTarget`). Di **+80 pip** tutup sampai sisa **0,01**, SL ke BE; runner 0,01 ke target atau TP terbuka jika target tidak ada. TP RR 0.9/1.6/4R, trail-setelah-TP2, dan milestone RR **mati**.
- **[AI/Adaptive layer] SmartBrain:** hanya dapat mengurangi risk menjadi **0,50×** pada bucket negatif ber-evidence cukup. Tidak menolak entry. **Setup grade** memakai empat kelompok sizing: S/A 2,00×, B 1,00×, C 0,50×, D/D+ ditolak. Tanda `+` tidak membuat rung lot tambahan. Sesi Asia/EU/NY **tidak** mengubah lot.

Alur singkatnya: **King SNR H4/H1 = cerita arah → Layer 1 MSNR memetakan → Layer 2 OB/FVG overlap → M5 refine → limit retest OB/FVG, M3 sebagai kualitas → grade C–S+ menentukan lot, D/D+ ditolak → SL struktural + batas ATR 0,35–2,50× (pagar pip off jika min/max = 0) → TP M15 / step 80 pip sisa 0,01 → OrderManager. SmartBrain hanya overlay 0,50×.**

Yang **memutuskan** sebuah trade dibuka adalah SMC + MSNR, bukan SmartBrain — lihat aturan mengikat di §15.1. Pola yang belum terbukti diperlakukan **netral**, bukan ditolak. Sejak **V13**, ini berlaku identik di **kedua** jalur skoring kandidat (`YANSTD.mq5` auto-entry **dan** `Modules/SignalEngine.mqh`) — keduanya tidak lagi punya cabang veto atau blend confidence yang berbeda satu sama lain.

---

## 2. Alur Eksekusi (Execution Pipeline)

```
OnInit()
 ├─ ValidateInputs()                → gagal = INIT_PARAMETERS_INCORRECT (fail-safe)
 ├─ CheckAndPreloadHistoricalData() → gagal = INIT_FAILED (tester); live = warn & lanjut
 ├─ Init semua subsistem (session, news, risk, spread, orders, partial, trail, mtf, brain)
 ├─ g_signal.Init(...) + g_signal.SetRequireM3Sweep(InpRequireM3Sweep)
 ├─ g_msnr.Init(...) + g_msnr.SetRequireM5Contained(InpRequireM5ContainedInM15)
 │   + SetMSNREngine() menggabungkan keduanya
 ├─ Push parameter yang tidak terlihat modul (SetMinRewardRisk, SetMaxAggregateRiskPct,
 │  SetATRParams, SetZoneATRParams, SetRequireM3Sweep,
 │  SetRequireM5Contained, …) — modul tidak bisa membaca `input` EA, jadi semuanya
 │  WAJIB di-push dari OnInit
 ├─ Init dashboard (hanya kalau bukan tester ATAU visual mode)
 └─ EventSetTimer(1)                → OnTimer khusus untuk render GUI

OnTick()  — SEMUA logic trading & manajemen posisi jalan di sini
 1. Refresh news calendar (throttled 1 jam)
 2. Sample spread + hitung threshold dinamis → g_signal.SetMaxSpreadPoints()
 3. Diagnostic periodik (live) / heartbeat bulanan (tester)
 4. IsNewBar(M15) → OnNewHTFBar() (Phase 1 bias)
 5. IsNewBar(M5/M15 refinement) → OnNewMTFBar() (Phase 2 POI)
 6. Tester GUI sync (visual mode only, throttled 1 detik)
 7. UpdatePositionState()
 8. Friday auto-close guard
10. Loop posisi terbuka (iterasi MUNDUR), mode struktural: hit +80 pip →
    tutup sampai sisa 0,01 + SL ke BE → runner ke TP broker (target M15) atau
    tetap terbuka. TP2 / milestone / trail RR **tidak** dijalankan di `EXIT_STRUCTURAL_POI`.
11. Daily Max Loss Guard → block entry baru, TIDAK menutup posisi berjalan
12. Margin Level Circuit Breaker → sama seperti Daily Loss Guard, non-destruktif
13. News filter guard
14. AUTO_ON → TryAutoEntry() / ManageAutoLimitOrders() (atau Historical Matrix explorer
    di tester)

OnTimer()  — render GUI (tiap 1 detik). Boleh GenerateSignal non-mutating untuk
              tampilan dashboard, lalu MarkGenerateSignalRan(); tidak boleh entry/exit

OnTradeTransaction() — sinkronisasi state track setelah broker eksekusi (partial fill,
    SL/TP hit, dsb.); pakai HistorySelectByPosition, bukan scan seluruh akun

OnDeinit() — cleanup: kill timer, shutdown brain, release indicator handle, hapus objek
    chart (prefix "YANSTD_", "POI_", "MACRO_")
```

**Aturan penting:**

- Keputusan entry/exit **hanya** boleh ada di `OnTick()` (atau fungsi yang dipanggil dari situ).
  `OnTimer()` redraw dashboard. Sejak v4.47.5 pemanggilan `GenerateSignal(..., mutateState=false)`
  di timer **wajib** diikuti `MarkGenerateSignalRan()` agar Layer 1–4 tidak dihitung ulang
  di `OnTick` untuk bar/POI yang sama. Jangan menaruh `OpenBuy`/`PlaceBuyLimit`/close di timer
  supaya tester non-visual (tanpa timer) dan live tetap identik.
- Loop manajemen posisi **wajib iterasi mundur** (`for(int p = openCount-1; p >= 0; p--)`)
  karena partial-close bisa menutup posisi penuh di tengah loop.
- Gate entry memakai `g_orders.CountOpenPositions()` **live**, bukan `openCount` yang
  di-capture sebelum loop manajemen.
- Semua keputusan "hari ini" (sesi, kill zone, Asian range, Friday close, reset stats harian,
  Daily Loss Guard) memakai `g_session.GetSimulatedUTC()` / `ConvertServerToUTC()` — **jangan**
  campur `TimeCurrent()` untuk boundary hari, boundary-nya akan beda jauh di broker dengan
  offset UTC besar.

---

## 3. Peta Modul

| File | Class | Tanggung Jawab |
|---|---|---|
| `YANSTD.mq5` | — (main) | Input declarations, event handlers, orkestrasi antar modul |
| `Modules/Defines.mqh` | — | Struct/enum bersama, util (format, pip factor, base36, `GetCachedATR` + `ReleaseCachedATRHandles`, retcode transient, helper log `LogMsg`/`LogThrottled`/`LogTradeError`/`LogSystemError`/`LogSystemWarning`) — **semua module lain include ini** |
| `Modules/SessionManager.mqh` | `CSessionManager` | Deteksi sesi (Asia/London/NY), simulasi UTC + DST (EU & US) |
| `Modules/NewsFilter.mqh` | `CNewsFilter` | Kalender ekonomi, pre/post news block |
| `Modules/RiskCalculator.mqh` | `CRiskCalculator` | Lot sizing dari risk % (`OrderCalcProfit`, fallback tick value). Lot di bawah minimum broker di-clamp, atau ditolak/0 jika `InpRejectBelowMinLot=true` |
| `Modules/SpreadMonitor.mqh` | `CSpreadMonitor` | Rolling mean/stddev spread → threshold adaptif |
| `Modules/ZigZagEngine.mqh` | `CZigZagEngine` | Deteksi swing high/low non-repainting (fractal based) |
| `Modules/FVGValidator.mqh` | — (fungsi) | `IsFVGValid` / `IsFVGValidWithStructure` + overlap level/zona (§25) |
| `Modules/SMCLayerM15.mqh` | (Layer 2) | Order Block & FVG di M15 |
| `Modules/MSNREngine.mqh` | `CMSNREngine` | King SNR, Fresh SnD, QML, Overlap Logic gate (Layer 1, primary) |
| `Modules/SignalEngine.mqh` | `CSignalEngine` | Orkestrasi Phase 1 (HTF bias) → Phase 2 (POI) → Phase 3 (M3 trigger) → `GenerateSignal()` |
| `Modules/MTFTrendMeter.mqh` | `CMTFTrendMeter` | Skor tren multi-timeframe (M3–H4) → confluence 0–100 dipakai dashboard **dan** dimensi bucket key SmartBrain. Diinstansiasi sebagai `g_mtf` di `OnInit()`, di-refresh tiap bar M3 baru di `OnTick()` (lihat §21.1 — sebelumnya dead code) |
| `Modules/SmartBrain.mqh` | `CSmartBrain` | Q-learning confidence bucket, bloom-filter dedup, persistence; mesin shadow legacy dihapus total di audit 2026-09-09 (§31) |
| `Modules/OrderManager.mqh` | `COrderManager` | **Satu-satunya** titik kirim order ke broker (`CTrade`), tracking posisi (`SPosTrack`), persistence file biner |
| `Modules/PartialClose.mqh` | `CPartialClose` | Early BEP, TP1 partial, milestone lock, TP2 |
| `Modules/TrailingStop.mqh` | `CTrailingStop` | Trailing runner pasca-TP2 berbasis swing terkonfirmasi |
| `Modules/SignalDiagnostics.mqh` | `CSignalDiagnostics` | Funnel rejection telemetry (lihat §8) |
| `GUI/StatsDashboard.mqh` | `CStatsDashboard` | **GUI v3** — Stats Dashboard (performa dari history, kalender, daily summary, dark/light). Lihat §10 |
| `GUI/ControlPanel.mqh` | — (konstanta `BTN_*` saja) | Hanya nama tombol manual yang dipakai `OnChartEvent`; tombol digambar oleh `CStatsDashboard::DrawControls()`. Sejak audit 2026-09-07 file ini **hanya berisi `#define`** — implementasi render (`GUI_DrawControlPanel`/`_CP_Btn`/`_CP_Rect`) yang tidak pernah dipanggil sudah dihapus (§20.2) |
| `GUI/Dashboard.mqh`, `HeaderBar.mqh`, `StatsPanel.mqh`, `TrendMeter.mqh` | `CDashboard` (lama) | **Deprecated** sejak GUI v3 — tidak di-include; disimpan untuk rujukan |

**Aturan penting:** `COrderManager` adalah **satu-satunya** class yang boleh memanggil
`CTrade`/`OrderSend`/`PositionModify` langsung ke broker. Module lain (SignalEngine,
PartialClose, TrailingStop) **tidak pernah** memanggil broker API secara langsung — selalu
lewat method `g_orders.*`. Ini menjaga semua safety check (margin, stops-level, retry
transient, filling mode) tetap terpusat di satu tempat.

---

## 4. Struktur Data Inti (`Defines.mqh`)

- **`SSignal`** — hasil `GenerateSignal()`: entry/SL/TP, confidence, zoneIndex,
  brainBucketIdx, setupEventId, dsb. Diteruskan ke `ExecuteBuy()`/`ExecuteSell()`.
- **`SPositionInfo`** — snapshot posisi terbuka (dipakai loop manajemen di `OnTick`).
- **`SPosTrack`** (di `OrderManager.mqh`) — state persisten per-ticket: TP1/TP2 level,
  scale-out plan, milestone/BEP flags, brain bucket & evidence weight. **Ini yang
  di-serialize ke file biner**, bukan `SPositionInfo`.
- **`SStats`** — statistik untuk guard Daily Max Loss (bukan untuk GUI v3).
- **`SMC_Zone`, `SMC_SwingPoint`** — representasi OB/FVG/POI dan swing pivot.
- **`SBrainBucketView`** (di `SmartBrain.mqh`) — satu-satunya cara membaca atribut bucket
  (lihat §9).
- **Enum reject reason** (`ENUM_REJECT_REASON`) — lihat §8, wajib ditambah **sebelum**
  sentinel `SIGNAL_REJECT_REASON_COUNT`.

---

## 5. Konvensi Penamaan (WAJIB DIPERTAHANKAN)

| Elemen | Pola | Contoh |
|---|---|---|
| Class | `C` + PascalCase | `CSignalEngine`, `COrderManager` |
| Struct | `S` + PascalCase | `SSignal`, `SPosTrack` |
| Enum | `ENUM_` + UPPER_SNAKE | `ENUM_NEWS_STATUS` |
| Enum value | UPPER_SNAKE | `REJECT_DAILY_LOSS` |
| Global instance | `g_` + camelCase | `g_orders`, `g_signal`, `g_stats` |
| Include guard | `YANSTD_<NAMA>_MQH` | `YANSTD_ORDERMANAGER_MQH` |

**Catatan penting soal input parameter (jangan "dibersihkan"/diseragamkan tanpa diminta):**
Codebase ini punya **dua gaya penamaan input yang hidup berdampingan**:

- Mayoritas: `InpPascalCase` (mis. `InpMagicNumber`, `InpRiskPercent`, `InpMinMarginLevelPct`)
- Sebagian kecil — terutama parameter ZigZag/timeframe lama: `inp_snake_case` (mis.
  `inp_htf_period`, `inp_m15_depth`, `inp_max_spread`, `inp_sl_buffer_pips`)

Ini **bukan bug**, tapi historical inconsistency yang sudah tertanam di banyak signature
fungsi (`g_signal.Init(...)`, dsb.). **Jangan** merapikan ini dengan rename massal —
resikonya breaking change di puluhan call-site tanpa manfaat fungsional. Kalau ingin
dirapikan, lakukan sebagai task terpisah yang eksplisit diminta.

**Template file header** (pertahankan format ini di file baru):

```
//+------------------------------------------------------------------+
//|                                                <NamaFile.mqh>    |
//|                      YANSTD EA — <deskripsi singkat>             |
//|                                    v<X.X>  |  <YYYY-MM-DD>       |
//+------------------------------------------------------------------+
#ifndef YANSTD_<NAMA>_MQH
#define YANSTD_<NAMA>_MQH
#include "Defines.mqh"
...
#endif // YANSTD_<NAMA>_MQH
```

Naikkan nomor versi + tanggal setiap kali ada perubahan struktural pada file tersebut
(bukan untuk typo fix kecil).

---

## 6. Lifecycle Posisi & Skema Comment Order

Setiap posisi yang dibuka diberi comment dengan format:

```
SMC_T<entryType>G<setupGrade>_B<bucketIdx36>_E<setupEventId36>[_M]   (suffix _M hanya untuk matrix-mode backtest)
```

`bucketIdx` dan `setupEventId` di-encode **base36** (0-9A-Z, via `EncodeBase36()` /
`EncodeBase36Signed()` di `Defines.mqh`) — bukan desimal. `entryType` dan `setupGrade`
tetap desimal satu digit. `FormatEntryComment()` adalah satu-satunya penulis dan
`ParseEntryComment()` adalah satu-satunya parser aktif untuk rekonsiliasi/recovery di
`YANSTD.mq5`. Komentar legacy, manual, atau rusak menghasilkan sentinel unknown dan
caller memakai fallback price-only yang eksplisit; jangan menambahkan parser parsial lain.

> **Kalau menambah field baru ke skema comment ini:** hitung worst-case (nilai maksimum
> semua field + delimiter) dan pastikan masih jauh di bawah **31 karakter** (limit comment
> broker). Base36 dipilih justru karena worst-case desimal hanya menyisakan margin ~4 char;
> sekarang margin ~9 char. Prioritaskan menyimpan data non-kritikal-untuk-recovery di file
> track (`SaveTracks()`/`LoadTracks()`), bukan di comment.

**Urutan stage manajemen posisi (fixed, lihat §2 poin 10):**
`BEP protection → Opposing POI guard → TP1 partial → milestone lock → TP2 partial →
trailing runner`. Setiap stage punya guard `if(pos.xDone)`/`if(!pos.xDone)` yang
bergantung pada state stage sebelumnya — jangan reorder tanpa audit dependency-nya.

Posisi orphan (ada di broker, tidak ada di track) tetap dikelola fail-safe tapi
R-based management-nya nonaktif karena initial risk tidak diketahui; kondisi ini
di-log dengan warning throttled, bukan senyap.

---

## 7. Pola Risk & Safety Guard

Semua guard proteksi (Daily Loss, Margin Level, News, Friday Close, dst.) mengikuti pola
yang sama di `OnTick()`:

```mql5
if(<kondisi breach>)
  {
   g_diagnostics.Record(REJECT_<ALASAN>, (long)iTime(Symbol(), inp_ltf_period, 0));
   g_orders.DeleteAllPendingByMagic();
   g_signal.ClearAllPOIPendingLimits();
   return;   // hanya block ENTRY BARU, posisi berjalan tetap dikelola normal
  }
```

Kalau menambah guard baru, ikuti pola ini persis: (1) hanya delete pending & clear POI
lock, **jangan** otomatis menutup posisi berjalan kecuali memang itu tujuannya secara
eksplisit; (2) selalu catat lewat `g_diagnostics.Record()` dengan reason baru (§8);
(3) taruh sebagai numbered step baru di komentar `OnTick()`, ikuti penomoran yang sudah
ada (mis. "7b." untuk sisipan setelah step 7).

Guard yang sudah ada: Friday Close, Daily Max Loss, Margin Safety per-order + Margin Level
circuit breaker, News Filter, ADX/ATR market-quality gate, Time Invalidation, Spread dinamis.

**Rantai sizing v4.41 (urutannya WAJIB seperti ini):**

```
effRisk dasar → setup grade (S/A 2.0x; B 1.0x; C 0.5x; D+/D reject)
              → clamp InpMaxAggregateRiskPct
              → CalcLotSize() → NormalizeLotToBrokerLimits() / EnforceBrokerMinLot()
                (clamp minimum broker, atau reject bila InpRejectBelowMinLot=true)
              → CanAddAggregateRisk()
```

`BrainLotMultiplier(winWeight)` **tidak dipakai** untuk lot live. SmartBrain hanya
mencatat hasil. Kalau menambah pengali risiko baru, taruh di rantai ini dan **jangan**
mengalikan `InpRiskPercent` mentah. Setiap pengali wajib di-clamp ke
`InpMaxAggregateRiskPct`. Clamp aktif mencetak `[YANSTD LOT LADDER]`.

Catatan yang sudah diketahui dan **sengaja dibiarkan**: `RoundLotToStep()`/`CalcLotSize()`
meng-clamp ke `VOLUME_MAX` tanpa suara — dua rung teratas bisa menghasilkan lot identik. Pantau
lewat jurnal kalau ukuran akun besar.

> **PERUBAHAN 2026-09-09 — lantai keras 0,01 lot, tanpa cabang reject.**
> Kalau entry sudah lolos filter strategi dan `CalcLotSize()` menghasilkan volume di bawah
> minimum broker, lot **selalu** di-overwrite ke minimum legal. Di akun ini minimum itu
> `0,01`. Dua input kompatibilitas lama sudah dihapus pada v4.45. Runtime **tidak**
> boleh mengembalikan `0.0` atau menolak entry hanya karena risiko riil 0,01 lot
> melebihi % risk yang diminta. Journal: `LOT_CLAMP` / `LOT_FALLBACK`.
>
> Custom symbol (ticks Dukascopy) yang `SYMBOL_VOLUME_MIN` / `SYMBOL_VOLUME_STEP`-nya `0`
> memakai fallback `YANSTD_HARD_MIN_LOT = 0.01`. Helper: `EffectiveBrokerMinLot()`,
> `EffectiveBrokerLotStep()`, `NormalizeLotToBrokerLimits()` (alias `EnforceBrokerMinLot()`) di `Defines.mqh` — clamp min, max, dan step. Dipakai di
> `RiskCalculator`, `SignalEngine`, jalur market/limit `YANSTD.mq5`, dan
> `OpenBuy`/`OpenSell`/`PlaceBuyLimit`/`PlaceSellLimit`.
>
> ```
> rawLot < minLot && InpRejectBelowMinLot=false -> lot = broker min (LOT_CLAMP), warning Journal
> rawLot < minLot && InpRejectBelowMinLot=true  -> lot = 0 (LOT_STATUS_INVALID), entry ditolak
> rawLot >= minLot -> lot di-round ke step broker seperti biasa
> ```
> Default tetap clamp: risiko aktual pada posisi min-lot bisa lebih besar dari `InpRiskPercent`.
> Operator akun kecil yang tidak mau melebihi risk % menyalakan `InpRejectBelowMinLot`.
> `CheckMarginSafety()` tetap memblokir jika free margin tidak cukup. Helper sizing:
> `NormalizeLotForRisk()` / alias `RoundLotToStep()`.

---

## 8. Pola Ekstensi Diagnostics (Reject Reason)

`ENUM_SIGNAL_REJECT_REASON` di `Defines.mqh` **wajib** ditambah *sebelum* baris
`SIGNAL_REJECT_REASON_COUNT` (sentinel ini menentukan ukuran array `m_counts[]` di
`SignalDiagnostics.mqh` — jangan pernah hardcode angka sebagai gantinya). Setelah
menambah enum value, tambahkan juga satu `case` baru di
`CSignalDiagnostics::Label()`. Dua langkah ini **selalu berpasangan** — enum
tanpa case akan jatuh ke `"UNKNOWN"` di log.

`REJECT_SWEEP_NOT_CONFIRMED` (label funnel `M3_SWEEP_NOT_CONFIRMED`) dan
`REJECT_CHOCH_NOT_CONFIRMED` berlaku untuk jalur trigger M3/market-context. Jika
`InpScanAllPOIsWhenNoTrigger=true`, keduanya tidak menghapus POI parent; jalur direct-zone
tetap dapat memasang pending limit dari OB/FVG parent yang aktif pada scan M3 berikutnya.

Sejak v4.35:
- `REJECT_OB_NO_FVG` (`M3_OB_MISSING_DISPLACEMENT_FVG`) — candle base M3 tidak lolos
  definisi OB (tidak ada FVG displacement **dan** tidak ada FVG fallback).
- `REJECT_M3_OUTSIDE_PARENT_ZONE` (`M3_OUTSIDE_PARENT_M5`) — refined M3 OB/FVG
  menonjol keluar dari POI M5 induk melebihi `0.05×ATR(M3,14)`.

> **Jebakan membaca funnel:** `SignalDiagnostics` punya `if(m_counts[i] <= 0) continue;`
> sehingga kategori bernilai nol **tidak diprint**. Nol punya dua arti yang sangat berbeda:
> "gerbang itu tidak pernah memicu" **atau** "gerbang itu tidak pernah tercapai karena ada
> `return`/`continue` di hulunya". Selalu cek urutan gerbang di fungsi scan sebelum
> menyimpulkan sebuah gate aman.

---

## 9. Integrasi SmartBrain (Q-learning)

- Setiap setup punya `brainBucketIdx` (hasil hashing pola: sesi, arah, tipe POI, mitigation
  profile, fib, ukuran zona **dalam unit ATR**, trend — lihat `GetBucketIndex()`,
  `DecodePatternIndices()`/`GetHierarchyIndices()`). Ruang bucket **3.456**
  (= 4 sesi × 2 arah × 2 POI × 3 OB × 2 FVG × 4 fib × 3 zona × 3 trend; sumbu day-of-week
  sudah dihapus, stride per-sesi = 864). Hierarki: EXACT → CORE → MITIGATION → PROFILE.
- **Setiap perubahan skema bucket WAJIB bump ketiganya:** `AI_FILE_VERSION`,
  `AI_STRATEGY_FINGERPRINT`, `AI_STRATEGY_NAMESPACE`. Identitas aktif sekarang:
  **`1370` / `2096183460` / `HYBRID_MSNRSMC_QRL_V17_OB15_OB45`**. Namespace masuk ke nama file & folder
  journal, jadi bump = dataset baru otomatis; data lama tidak dihapus, hanya tidak dibaca.
- **Dataset legacy 43.200 bucket = REJECT eksplisit** (`RejectLegacyDataset()`), jangan
  pernah dibikin migrasi indeks-ke-indeks: skema zona (pip vs ATR) dan ada/tidaknya sumbu
  hari membuat indeks lama salah label — memaksa merge akan meracuni memori baru.
- `evidenceWeight` matrix memakai `1/N`, dengan `N` jumlah sibling order yang benar-benar
  berhasil ditempatkan untuk `setupEventId` yang sama. Bobot sibling satu setup berjumlah 1.
- Entry variant aktif sekarang enam ID: `OB_15`, `OB_45`, `FVG_50`, `FIB_618`,
  `FIB_705`, `FIB_790`. Entry OB memakai OB15 untuk SL 10–40 pip dan OB45 untuk
  SL 41–70 pip. Slot FVG 75/99 dan alias Fib lama dihapus karena
  backtest operator selalu dimulai dari nol.
- **Brain = OVERLAY, bukan gerbang wajib** — aturan mengikat, detail di §15.1.
- **`IsSetupApproved()` sudah dihapus.** Kedua jalur skoring kandidat (`YANSTD.mq5` dan
  `Modules/SignalEngine.mqh`) membaca Brain hanya lewat `GetBucketView()`. Tidak ada API
  atau cabang veto Brain yang tersisa. **[Diperbarui audit 2026-09-09, lihat §29]:**
  `GetSizingMultiplier()` sendiri sudah dihapus total di v4.42 sebagai dead code — lot sizing
  live sekarang murni `SetupGradeLotMultiplier()` (`Defines.mqh`). Pengali sesi Asia
  (`GetSessionSizeMultiplier` / `InpAsiaSessionSizeMult`) **sudah dihapus v4.46**. `BrainLotMultiplier(winWeight)` tetap ada di
  `SmartBrain.mqh` tapi hanya untuk laporan diagnostik `LogEvidenceDensity()`, tidak pernah
  memengaruhi lot live.
- **V13 — `finalScore`/`qualityScore` murni SMC+MSNR di semua jalur.** Blend lama
  `conf * 0.70 + smcScore * 0.30` (aktif saat `realEvidence >= AI_MIN_VETO_SAMPLE`) di
  `SignalEngine.mqh` sudah dihapus — itu adalah veto lewat pintu belakang di gate
  `SOFT_SCORE` yang sama persis dengan yang sudah diperbaiki aturan (c) di bawah, hanya saja
  belum ikut diperbaiki saat itu. `finalScore = smcScore`, titik, sama seperti
  `YANSTD.mq5`.
- **V13 — Sesi Asia dipisah dari Brain.** `DynamicThresholdForBucket()` dulu mengembalikan
  `m_asiaThreshold` (75%) untuk bucket sesi Asia dan `m_overlapThreshold` (65%) untuk sesi
  Overlap — artinya kebijakan waktu-sesi murni (Asia = likuiditas rendah) tertanam di dalam
  sistem confidence AI dan tidak bisa diubah/diuji terpisah darinya. Sekarang fungsi itu
  selalu mengembalikan `m_minConfidence` untuk semua sesi (session-agnostic), dan aturan Asia
  sempat dipindah ke `CSessionManager::GetSessionSizeMultiplier()` / `InpAsiaSessionSizeMult`.
  **v4.46:** input dan setter itu dihapus; sesi tidak mengubah lot. **Update audit 2026-09-05:** `InpBrainAsiaThreshold` /
  `InpBrainOverlapThreshold` yang tadinya hanya dipertahankan untuk kompatibilitas `.set` lama
  sekarang **sudah dihapus total** dari declaration, `ValidateInputs()`, dan signature
  `CSmartBrain::Init()` — dikonfirmasi eksplisit tidak punya backing member variable dan nol
  efek di gate manapun sebelum dihapus. `.set` lama yang masih menulis dua key ini akan
  di-ignore diam-diam oleh MT5 saat load (perilaku normal untuk unknown key), tidak
  memengaruhi setting lain di file. Lihat §17 untuk daftar lengkap input yang dihapus di pass
  ini.
- **Dua ambang sampel yang berbeda dan tidak boleh disatukan:**
  `AI_MIN_DECISION_SAMPLE` (=1) membuat bucket boleh dibaca; `AI_MIN_SIZING_EVIDENCE`
  (=6 bukti nyata ter-decay) memberi Brain hak mengubah ukuran lot. Sebelum ambang sizing
  tercapai, multiplier selalu netral `1.0`. Brain tidak punya hak menolak entry.
- **Ambang confidence sekarang seragam untuk semua sesi (V13).** `DynamicThresholdForBucket()`
  selalu mengembalikan `m_minConfidence` — lihat catatan V13 di atas untuk sejarah bug
  literal `10800` (pre-V13) dan kenapa levernya sekarang dipindah keluar dari fungsi ini
  sama sekali, bukan sekadar diperbaiki divisornya.
- **Satu getter untuk semua atribut bucket:** `GetBucketView()` → `SBrainBucketView`
  (confidence, sample, `winWeight`, `realEvidence`, `avgNetR`, `avgMFER`, `isBanned`,
  `level`). `GetConfidence()` dan `GetBucketSampleSize()` masing-masing menjalankan
  **ulang** fusion 3-sumber, jadi jangan memanggil beberapa getter untuk kandidat yang
  sama di dalam loop POI.
- **Decay bukti:** `DecayWeight = 0.5^(umurHari / 90)`. Bukti berumur > ~1 tahun praktis
  mati (365 hari ⇒ ~6 %, 970 hari ⇒ ~0,09 %). Ini penting saat menafsirkan run OOS.
- **Leakage guard** (sidecar `<dataset>.range.bin`, magic `YRNG`) hanya menolak **memuat**
  dataset kalau clock tester ≤ max-learned time; ia **tidak pernah** memblokir entry.
  Protokol validasi jujur: latih (matrix) periode A → validasi (strict) periode B setelah A.
- File brain persistent per broker/instrument (`InpBrainInstrumentKey`,
  `InpBrokerSpecificLiveBrain`) — jangan hardcode nama file, ikuti parameter yang sudah ada
  supaya data historis broker A tidak tercampur ke broker B.

---

## 10. Pola GUI Dashboard (v3 — Stats Dashboard)

**Prinsip:** dashboard = tampilan performa dari history akun (deal difilter magic EA) **plus** dua kartu
strategi read-only (Signal Status, MTF Trend Meter). Evaluasi sinyal untuk display **throttled**
(≤ 1× per 5 s / bar M3 baru) dan read-only (`invalidatePOI=false, mutateState=false`).
GUI tidak pernah mengubah state strategi.

File: `GUI\StatsDashboard.mqh` (`CStatsDashboard`). File lama `Dashboard.mqh`, `HeaderBar.mqh`,
`StatsPanel.mqh`, `TrendMeter.mqh` **tidak di-include lagi** (deprecated, disimpan untuk rujukan).
`ControlPanel.mqh` masih di-include hanya untuk **konstanta nama tombol** (`BTN_*`, `LBL_LOT_DISPLAY`)
yang dipakai `OnChartEvent` — tombol manual digambar ulang oleh `DrawControls()` sebagai strip kompak.

### Struktur (layout "rail + tiles + wide curve")

| Blok | Isi | Klik |
|---|---|---|
| Title bar (44 px) | brand `YANSTD` + sub "YANSTD · MSNR + SMC", status `ACTIVE/PAUSE`, mode akun + login + broker, baris live (jam, float, open, pending) | `◷ periode`, `◔` DD, `▦` kalender, `◉/○` layer SMC, `☀/☾` tema, `—` minimize |
| **Rail kiri** (150×317) | `◆ PROFIT` % + net, blok accent **Balance / Equity**, Balance Start, Commission/Swap/Lots/Avg duration, `◆ SYMBOLS` | checkbox ALL (`✓`) & NONE (`×`); checkbox per simbol |
| **4 tile** kanan-atas (102×92) | Trades/Wins · Profit Factor/Recovery · donut Win Rate · donut DD | klik donut DD → toggle DD |
| **Equity curve** lebar (434×217) | canvas gradien, garis gold, area gradient, zero-line, label tanggal | — |
| **Signal Status** (372×104) | arah setup, entry/SL/TP, market line (spread · session · margin · Brain %), news + toast `Notify()` | — |
| **MTF Trend Meter** (204×104) | 6 TF (M3/M5/M15 · M30/H1/H4) bar `■□` + %, confluence, bintang, bias label | — |
| Control strip | risk · lot · TP1 · Limit · Cut 50% · Hapus · BUY · SELL · AUTO · CLOSE ALL | handler `OnChartEvent` |
| Popup Calendar / Daily Summary | kalender bulanan & ringkasan harian | `‹ ›`, sel hari, `✕` |

**Depth (anti-flat):** latar rounded dilukis ke **canvas** (`M_CV_BG`, `CAL_CVBG`, `DAY_CVBG`),
bukan objek rect: shell r=12, band judul, spine gold, hairline, lalu tiap kartu via `CvCard`
(shadow 2 lapis → slab stripe → body gradien r=8 → highlight). `OBJ_BUTTON` tetap kotak (batas MT5).
Font terpusat di `SD_F_*` (`Trebuchet MS` brand, `Segoe UI` judul, `Arial` angka).

**Aturan urutan gambar (WAJIB):** MT5 melukis objek **berdasarkan urutan pembuatan**,
`OBJPROP_ZORDER` hanya prioritas klik. Karena itu `RebuildAll()` menghapus **juga** tombol legacy
`YANSTD_BTN_*` + `LBL_LOT_DISPLAY` sebelum menggambar ulang, dan canvas latar dibuat **pertama**;
shadow rect canvas dibuat **sebelum** `CreateBitmapLabel`. Bug "tombol hilang setelah
minimize/rebuild" berasal dari aturan ini.

**Aturan prioritas klik (WAJIB):** klik diterima objek dengan `OBJPROP_ZORDER` **tertinggi** di bawah
kursor. Latar popup memakai z 20–23, karena itu `Btn()` memberi semua tombol **z = 50** — jangan
pernah membuat rect/label dengan z ≥ 50, atau klik tombol akan ditelan latar.

**Jebakan nama:** `<Canvas\Canvas.mqh>` mendefinisikan macro `ARGB`, `XRGB`, `GETRGB*`,
`COLOR2RGB`, `RGB2COLOR`, `TRGB`. Jangan pakai nama itu untuk fungsi/variabel di modul yang
meng-include Canvas (helper internal dinamai `ToARGB`).

### Mesin data (`RefreshHistory`)

- `HistorySelect(0, now)` **hanya** saat: deal count berubah, `MarkDataDirty()` dari
  `OnTradeTransaction(DEAL_ADD)`, atau fallback 60 s. Filter/periode/tema **tidak** membaca ulang history.
- Trade = agregasi per `DEAL_POSITION_ID` (IN/OUT/INOUT/OUT_BY), net = profit+komisi+swap, pips =
  avg-exit vs avg-open berbobot volume; posisi yang masih terbuka dikeluarkan.
- **Ledger** = semua deal akun (termasuk deposit/withdraw) → `BalanceAt(t)` = balance sekarang − Σ delta
  deal ≥ t (binary search + suffix-sum). Untuk "All History", Balance Start di-anchor ke saldo tepat
  sebelum trade pertama di set terfilter (bukan saldo sebelum deposit, yang = 0).
- Balance DD = max drawdown kurva `balanceStart + kumulatif net` dalam set terfilter.

### Kontrak efisiensi

- Layout statis di-rebuild **hanya** saat `m_dirty` (data/tema/periode/filter/popup). Tick 1 s cuma
  update label live (~6 `SetText`) + warna tombol control strip.
- Canvas (2 donut + kurva) digambar ulang hanya saat rebuild; donut Equity DD saja yang live.
- Objek panel berprefix `YANSTD_UI_` (`SD_PFX`). Tombol trading tetap `YANSTD_BTN_*`.
  `OnDeinit` menghapus `YANSTD_UI_` / `OKX_UI_` lalu `YANSTD_` / `POI_` / `MACRO_`. `Destroy()` melepas canvas.
- Tester non-visual: GUI tidak dibuat.

### Overlay peta chart (v4.46 map)

`RenderAllSMCVisuals()` di `YANSTD.mq5` (bukan dashboard). Tester non-visual tetap skip.

| Flag | Default | Objek |
|---|---|---|
| `InpShowZoneBoxes` | true | Kotak OB POI M5 aktif + label |
| `InpShowFVGBoxes` | true | Kotak FVG yang menempel POI aktif |
| `InpShowStructureLines` | true | Swing M15, event BOS/CHoCH terakhir, EQ 50% |
| `InpShowMSNRMap` | true | Zona Layer-1 aktif: King / A / V / OCL / QML / SBR / RBS + garis QML HEAD / key SBR-RBS |
| `InpShowFibLevels` | true | `FIB 0.618 / 0.705 / 0.786` dari `fiboSwingHigh/Low` zona MSNR (rumus OTE engine) |
| `InpShowM3Refine` | true | Kotak `M3 OB` / `M3 FVG` terakhir yang lolos gate parent di `SMC_Zone.visM3*` |

Prefix objek peta: `YANSTD_MAP_`. Tidak digambar: Fib mandiri di luar swing zona, scan M3 yang belum diterima engine, zona mitigated/expired. QML/SBR/RBS adalah tipe `ENUM_MSNR_ZONE_TYPE`, bukan objek terpisah dari peta MSNR.

### Setup mode (v4.46)

`InpSetupMode` (`Defines.mqh` `ENUM_SETUP_MODE`):

| Nilai | Gerbang | Entry/SL | Grade | Soft score |
|---|---|---|---|---|
| `SETUP_HYBRID` (0) | MSNR+OTE+M3 seperti tes 01–08 | mid M3 | `ClassifySetupGrade` | 45 / counter 75 |
| `SETUP_MSNR_PRIMARY` (1) | Map MSNR + OTE + sentuh/dekat key | B2 key / QML shoulder / mid; SL tepi MSNR | M1-β | 55 / counter 75 |
| `SETUP_SMC_PRIMARY` (2) | Rantai POI SMC + M3 | mid M3 | M2-β (tanpa map + !OTE = D) | 45 / counter 75 |

ADX: default soft (`InpUseADXGuard`). Hard veto hanya jika `InpADXHardGateOnMode0=true`, mode HYBRID, dan ADX < `InpMinADX`. Mode 1/2 tetap soft. +DI/−DI dibaca sebagai bonus/penalti soft ±5, bukan gate baru. Funnel: hard = `REJECT_ADX_GUARD` (`ADX_M15_HARD_GATE`); soft = `REJECT_ADX_SOFT_PENALTY` (`ADX_M15_SOFT_PENALTY`). Jangan campur keduanya saat membaca statistik reject.

Preset eksperimen: `Presets/YANSTD_EXP_MODE1_MSNR_PRIMARY.set` (8889701), `YANSTD_EXP_MODE2_SMC_PRIMARY.set` (8889702). Live/RT tetap HYBRID. File Brain terpisah.

Wiring: `YANSTD.mq5` `g_signal.SetSetupMode(InpSetupMode)`. Mode 1 tidak memakai loop POI `GenerateSignal`. Mode 2 memakai loop POI yang sama dengan HYBRID, tanpa evict `lostPrimaryAlignment`.

Dashboard: `0 HYB` / `1 MSNR` / `2 SMC` di control strip. Klik → `SetSetupMode` + hapus pending. Reload EA kembali ke `InpSetupMode` di `.set`.

Jam default (live, LIVE_BT, EXP 1/2, RT_01–08, input mq5): `InpTimeFilterMode=TIME_FILTER_ROLLOVER_HOLE`, blok 20–23 UTC. Soft mode 1 = 55. Cap POI mode 2 = 2.5×ATR.

Tipe order (bukan semua limit):

| Jalur | Order |
|---|---|
| Auto HYBRID / SMC_PRIMARY | Limit `ManageAutoLimitOrders` |
| Auto MSNR_PRIMARY, entry masih di depan harga | Limit `PlaceMSNRPrimaryLimit` |
| Auto MSNR_PRIMARY, entry sudah lewat (P1-B) | Market `ExecuteBuy` / `ExecuteSell` |
| Tombol dashboard BUY/SELL | Market |
| Tombol LMT | Limit |

Tidak ada buy stop / sell stop.

Grade mode 1 (`ClassifySetupGradeMSNRPrimary`): S = QML/SBR/RBS + virgin + King OK; A = A/V/OCL + virgin/single + King OK; B = premium/key selain itu.

Grade mode 2 (`ClassifySetupGradeSMCPrimary`): premium+inOTE+King OK + VIRGIN = **S+**, + SINGLE_TOUCH = **S** — keduanya lot **2.00x** (tanda `+` cuma menandai kualitas VIRGIN, bukan rung lot baru; sempat 2.25x di v4.47.4–v4.47.7, dikoreksi v4.47.8 §47); key+inOTE+King OK + VIRGIN = **A+**, + SINGLE_TOUCH = **A** — keduanya lot **2.00x**; B = ada map tapi PARTIAL / tidak inOTE / King lawan; C = tidak ada map tapi POI inOTE; D = tidak ada map dan !inOTE. Sejak v4.47.6: tidak ada map ≠ mitigated; `primaryMSNRZoneIdx` diisi overlap geometris saja (bukan `EvaluatePrimaryGate`); jalur limit wajib `bestPoiInOTE`. Detail §44.

### Konvensi kalau menambah elemen

1. Nama objek: `SD_PFX + "M_..."` (panel utama) agar ikut terhapus di `RebuildAll()`; popup pakai
   prefix popup-nya.
2. Elemen yang bisa diklik: tambahkan cabang di `HandleClick()` **sebelum** `return true` terakhir;
   set `m_dirty = true` bila mengubah state yang memengaruhi layout.
3. Kartu strategi hanya **read-only**; jangan tambahkan aksi yang mengubah state pipeline dari GUI.
4. Tema OKX: dark pitch-black + lime `#C5F82A`, light clean + charcoal/green.
   Semua warna token di `GUI/ControlPanel.mqh` dan `ApplyTheme()`. `InpDashboardDark` default true.
5. Jangan spam Journal dari `HandleClick`. Toast operator lewat `Notify()`.
6. Aksi yang ditolak jangan diam: pakai `Notify(msg)` (toast 6 s di baris L2 Signal card).
   Catatan produk: tombol BUY/SELL **bukan** market order buta — ia mengeksekusi sinyal engine
   saat itu, jadi kalau tidak ada setup valid tombol memang "tidak melakukan apa-apa" + toast.

---

## 11. Persistence (File Biner Track)

`COrderManager` menyimpan state posisi (`SPosTrack[]`) ke file biner dengan skema:

```
[int version][int count][SPosTrack array...]
```

Nama file: `YANSTD_PosTrack_<server>_<login>_<symbol>_<magic>.bin` (karakter `/ \ :`
di-sanitize). Kalau menambah field baru ke `SPosTrack`, **wajib naikkan `version`**
(saat ini `500`) supaya file lama dengan layout berbeda tidak salah baca — `LoadTracks()`
memvalidasi `version == 500` sebelum membaca array.

Tidak dipakai di mode tester (`MQLInfoInteger(MQL_TESTER)` → skip load/save), by design.

Track array **dinamis** — `EnsureTrackCapacity()` grow `m_tracks` (reserve 64,
doubling) bila perlu; tidak ada fixed slot. `Init` sekarang (audit 2026-09-07)
me-reset array ke baseline 64 lalu `LoadTracks()` re-grow sesuai kebutuhan
persistensi (sebelumnya array tumbuh monotonik tanpa shrink lintas re-Init di
live). Counter `m_trackCount` di-decrement saat track di-remove.

---

## 12. Mode Testing & Safety Switch

- `MQLInfoInteger(MQL_TESTER)` — jalan di Strategy Tester.
- `MQLInfoInteger(MQL_VISUAL_MODE)` — tester visual (GUI & timer aktif).
- `MQLInfoInteger(MQL_FORWARD)` — segmen forward-test.
- **Historical Matrix Test** (`InpTesterExecutionMode=0`): eksplorasi hingga 6 kandidat aktif
  sekaligus (3 Fib + 2 OB + 1 FVG CE), pending cap = 6 — hasil PF/DD di tester adalah
  statistik **eksplorasi**, bukan performa strategi final. SmartBrain tidak memveto entry.
- **Live Strict Validation** (`InpTesterExecutionMode=1`): satu kandidat **terbaik per slot**
  per setup dan overlay risiko SmartBrain dapat aktif. SmartBrain tetap tidak memveto entry;
  setup-grade sizing aktif dan independen dari dataset Brain. Mode ini merepresentasikan
  perilaku live. Jumlah trade-nya **memang** jauh di bawah matrix; itu by design, bukan bug.
  - **Update kebijakan audit 2026-09-05:** pending cap **tidak lagi hardcoded ke `1`**.
    Sebelumnya `TryAutoEntry()` dan `ManageAutoLimitOrders()` memaksa `maxPending = 1` secara
    independen dari `InpMaxActivePositions`/`InpMultiLayerEntry`, sehingga seluruh pipeline
    evaluasi sinyal hanya bisa memegang satu kandidat sekaligus terlepas dari bagaimana input
    concurrency dikonfigurasi. Ini sekarang dianggap **keputusan produk yang disengaja**
    (bukan revert): `maxPendingSlots = g_multiLayerAllowed ? max(1, g_effectiveMaxPositions -
    openCount) : 1` — konsisten dengan ceiling hedging/netting-aware yang sudah dipakai untuk
    open position (§2 tabel `g_effectiveMaxPositions`). Konsekuensinya: akun **netting** atau
    `InpMultiLayerEntry=false` tetap berperilaku sama seperti sebelumnya (cap = 1, tidak ada
    perubahan). Akun **hedging** dengan `InpMultiLayerEntry=true` dan `InpMaxActivePositions>1`
    sekarang benar-benar bisa memegang beberapa kandidat/posisi independen sekaligus di STRICT —
    kalau Anda tidak menginginkan ini, set `InpMaxActivePositions=1` secara eksplisit di preset
    live/strict (§12 tabel Preset `.set` tidak berubah nilainya secara default, tapi levernya
    sekarang benar-benar hidup, jadi menaikkannya berdampak nyata). Detail lihat §17.
- `InpDataCollectionMode` hanya aktif kalau `historicalTester` true — **selalu diabaikan**
  di real/forward execution demi keamanan (lihat log `[YANSTD SAFETY]`).

Jangan ubah semantik dua mode ini tanpa memahami bahwa keduanya dipakai untuk tujuan analisis
yang berbeda (riset variasi vs. validasi realistis).

### Urutan run untuk riset Brain: MATRIX dulu, baru STRICT

Di STRICT, `InpStrictValidationLearning=false` membuat Brain read-only. Dataset kosong tetap
menghasilkan baseline SMC+MSNR yang sah: setup-grade sizing tetap aktif, sedangkan SmartBrain
netral dan tidak memblokir entry. Jalankan MATRIX/learning terlebih dahulu hanya bila tujuan
run berikutnya memang mengukur overlay risiko Brain yang telah memiliki evidence.

Urutan riset Brain yang disarankan:

1. Run **MATRIX** (`InpDataCollectionMode=true`, learning ON) untuk memanen bukti.
2. Simpan/biarkan dataset Brain hasil run itu.
3. Run **STRICT** di atas Brain yang sudah terlatih tadi.

EA sekarang mendeteksi kombinasi berbahaya ini sendiri dan mencetak `[YANSTD TEST VALIDITY]` tiga baris
di `OnInit`. Peringatan saja, bukan `INIT_FAILED` — baseline SMC+MSNR-only tetap sah kalau memang itu
yang diinginkan.

### Membaca `[YANSTD BRAIN DENSITY]`

Dicetak dua kali per run (`INIT` dan `DEINIT`). Isinya kepadatan bukti Brain: jumlah bucket yang punya
bukti nyata, total unit bukti (mentah vs. setelah decay), rata-rata dan maksimum per bucket, jumlah
bucket yang dapat dibaca / dapat mengubah sizing / berstatus quarantine, dan populasi tiap rung lot.

Baris utama adalah **`sizing-capable`**. Nilai nol berarti semua bucket masih memakai multiplier
netral `1.0x`; PF/DD run itu berasal dari SMC+MSNR dan sizing dasar. Record matrix masuk dengan bobot
`1/ENTRY_VARIANT_COUNT` (=1/6) karena enam sibling dari satu setup saling berkorelasi dan bersama-sama
mewakili satu unit bukti. Record live masuk dengan bobot 1.0.

### Preset `.set`

| File | Mode | Kunci pembeda |
|---|---|---|
| `YANSTD_16_Backtest_Very_High_Risk.set` | Backtest bebas breaker DD | Risk 5%; daily/equity DD cap 0; push alert OFF |
| `YANSTD_17_High_Risk.set` | Live high risk | Risk 3%; daily loss 6%; equity DD 20% |
| `YANSTD_18_Medium_Risk.set` | Live medium risk | Risk 1.5%; daily loss 4%; equity DD 12% |
| `YANSTD_19_Low_Risk.set` | Live low risk | Risk 0.5%; daily loss 2%; equity DD 8% |

Preset aktif v4.46 adalah peta lengkap satu-ke-satu dari seluruh input sumber (saat ini **190**). Nilai kosong
`InpFomcDatesOverride=` berarti kalender FOMC tester memakai fallback ordinal.
| `YANSTD_XAUUSD_LIVE_MATRIX.set` | Live / Demo — **forward exploration / training** | `InpTesterExecutionMode=0`, `InpDataCollectionMode=true`, `InpMultiLayerEntry=true`, `InpMaxActivePositions=8`, `InpMaxAggregateRiskPct=0`, `InpUseDynamicRisk=false`, dashboard ON, visual ON |
| `Presets/YANSTD_v441_VeryHighRisk.set` | Live / tester — Very High Risk | lihat §28 |
| `Presets/YANSTD_v441_HighRisk.set` | Live / tester — High Risk | lihat §28 |
| `Presets/YANSTD_v441_MediumRisk.set` | Live / tester — Medium Risk | lihat §28 |
| `Presets/YANSTD_v441_LowRisk.set` | Live / tester — Low Risk | lihat §28 |
| `YANSTD_XAUUSD_LIVE_STRICT.set` | Legacy strict | Jangan dipakai sebagai default 4.41; diganti paket `Presets/` |

#### Preset legacy 2026-09-06 (diarsipkan; jangan dipakai untuk konfigurasi baru)

Empat preset ini dibuat untuk skalping dengan target multi-entry per sesi. **Semua circuit
breaker drawdown dimatikan dan kapasitas posisi dimaksimalkan** sesuai permintaan operator —
artinya `InpRiskPercent` adalah **satu-satunya** pengendali risiko yang masih hidup.

| File | Tujuan | `InpRiskPercent` | Band SL (pip) | `MinSoftScore` / `MinRRR` | `ScanAllPOIs` |
|---|---|---|---|---|---|
| `YANSTD_01_High_Risk.set` | Agresif, multi-entry | 3.0 | 8 – 150 | 40 / 1.00 | `true` |
| `YANSTD_02_Medium_Risk.set` | Keseimbangan (dianjurkan sebagai baseline) | 1.5 | 10 – 120 | 45 / 1.10 | `true` |
| `YANSTD_03_Strict.set` | Paling selektif, hanya setup bermutu tinggi | 0.5 | 15 – 90 | 55 / 1.50 | `false` |
| `YANSTD_04_Test_Mode.set` | Riset / panen statistik matrix (maks. 6 kandidat) | 0.10 (`InpCollectionRiskPct`) | 8 – 150 | 35 / 1.00 | `true` |

Keempatnya berbagi nilai ini:

```
InpMaxDailyLossPct      = 0     ; daily-loss halt   OFF
InpMaxEquityDDPct       = 0     ; equity-DD halt    OFF  (tanpa ini: halt PERMANEN seumur run)
InpMinMarginLevelPct    = 0     ; margin-level halt OFF
InpMaxAggregateRiskPct  = 0     ; cap agregat OFF — kalau dihidupkan ia menjadi
                                ; limitasi posisi de-facto
InpMaxActivePositions   = 8     ; tidak ada cap posisi efektif
InpMultiLayerEntry      = true
InpAllowSingleExitFallback = true
```

> ⚠️ **Peringatan.** Konfigurasi ini sengaja menanggalkan jaring pengaman. Sebelum akun
> berdana sungguhan, hidupkan kembali minimal `InpMaxEquityDDPct` (20–30) dan
> `InpMaxActivePositions` (2–4). Tanpa keduanya, satu rangkaian loss panjang tidak memiliki
> rem apa pun selain ukuran lot per trade.

`03_Strict` mematikan `InpScanAllPOIsWhenNoTrigger` — jadi ia mempertahankan perilaku lama
yang mewajibkan CHoCH M3 sebelum limit dipasang. Itu membuatnya berguna sebagai baseline A/B
untuk mengukur kontribusi perbaikan frekuensi entry (§18.2).

Catatan preset yang mudah bikin salah tafsir:

- Tangga lot SPEC-C **hanya hidup kalau `InpUseDynamicRisk=true`**. Kalau menyalin preset lama
  yang masih `false`, tangga itu mati total tanpa pesan error apa pun.
- Cap agregat **3,0 %** dipilih supaya dua posisi rung teratas (2 × 0,50 % × 2,50x = 2,50 %) masih
  lolos. Menurunkannya ke 1,0 % akan mematikan dua rung teratas secara senyap.
- MATRIX sengaja `InpUseDynamicRisk=false`: risiko flat menjaga bukti yang dipanen tidak bias sizing.
- Jam tester (`InpTesterUTCOffsetWinter` / `InpTesterUseEuropeanDST`) **wajib** sama dengan timezone
  export data QDM: broker EEST = 2/true, broker UTC = 0/false.
- `InpSLATRMult=0.50` (preset yang masih 0.20 adalah preset lama).
- **Audit 2026-09-05:** `InpMaxActivePositions=1` di kedua preset STRICT/LIVE di atas tetap
  nilai default yang dianjurkan, tapi sejak pending-cap dinamis (§12, §17) angka ini sekarang
  **benar-benar mengontrol concurrency di STRICT/LIVE**, bukan cuma di MATRIX. Menaikkannya di
  akun hedging akan langsung membuka beberapa slot kandidat/posisi independen sekaligus di
  produksi — treat sebagai keputusan risiko baru, bukan sekadar tuning angka.

#### Preset audit-fixed 2026-09-06

Gunakan tiga file baru di folder `Presets`. Ketiganya memakai acceptance band stop
struktural **10–70 pip** (XAUUSD: kira-kira $1–$7), `InpMinimumStructuralRRR=1.60`,
dan circuit breaker aktif. Dengan TP1/TP2 aktif, EA juga memerlukan ruang struktural
minimal sampai TP2 (`1.6R`), bukan hanya nilai baseline yang lebih rendah.

| File | Tujuan | Risiko per setup | Batas eksposur | Mode eksekusi |
|---|---|---:|---|---|
| `YANSTD_05_High_Risk.set` | Live/demo agresif namun dibatasi | 1.5% | 4 posisi, 4% agregat, daily loss 4%, DD 10% | strict, kandidat terbaik |
| `YANSTD_06_Low_Risk.set` | Live/demo konservatif | 0.5% | 2 posisi, 1% agregat, daily loss 2%, DD 4% | strict, kandidat terbaik |
| `YANSTD_07_Backtest.set` | Eksplorasi Strategy Tester tanpa breaker | 0.10% per cluster | hingga 8 posisi/pending koleksi, aggregate/daily/DD/margin breaker OFF | matrix collection |

Preset Backtest sengaja mengaktifkan collection mode dan menonaktifkan breaker risiko agar
seluruh funnel entry dapat diukur. Hasilnya adalah statistik eksplorasi, bukan performa live;
gunakan tick nyata, spread/komisi broker, dan preset strict terpisah untuk out-of-sample.

---

## 13. Konvensi Bahasa & Logging

Codebase ini **sengaja bilingual**:

- Komentar kode & nama identifier → **Inggris**.
- Sebagian `Print()`/`Alert()` user-facing → **Indonesia** (mis. pesan validasi data
  historis, warning safety tertentu), sebagian lain Inggris dengan prefix `[YANSTD ...]`.

Ini bukan inkonsistensi yang perlu "diperbaiki" — pertahankan bahasa yang sudah dipakai
di sekitar baris yang diedit. Kalau menambah log baru, ikuti gaya prefix yang sudah ada:
`Print("YANSTD SMC: ...")`, `Print("⚠️ [YANSTD SAFETY] ...")`, `Print("[YANSTD TEST MODE] ...")`.
Peringatan yang bisa berulang tanpa arah baru (reject gate, risk cap, fallback sizing)
wajib lewat `LogThrottled(tag, minIntervalSec, msg, level)` di `Defines.mqh` — bukan
`Print()` mentah — supaya mode Matrix/Collection tidak membengkakkan journal.

---

## 14. Checklist Saat Menambah Fitur Baru

1. Baca bagian relevan dokumen ini dulu (§5–§12, dan §15.1 kalau menyentuh SmartBrain).
2. Tambah input baru? → taruh di `input group` yang paling relevan, ikuti gaya penamaan
   sekitar grup itu (`InpPascalCase` untuk grup baru; JANGAN buat `inp_snake_case` baru
   kecuali menyambung ke fungsi lama yang sudah pakai gaya itu).
3. Tambah validasi input baru → di `ValidateInputs()`, dekat input yang secara tematik
   terkait, ikuti pola `else if(...) reason = "...";`.
4. Input baru yang dibaca modul → **wajib** di-push dari `OnInit()` lewat setter; modul
   tidak bisa melihat `input` EA.
5. Trading action baru (kirim/modif/tutup order) → **harus** lewat method baru/existing
   di `COrderManager`, jangan panggil `CTrade` di file lain.
6. Reject reason baru → enum + switch-case sekaligus (§8).
7. Ubah struktur dashboard → ikuti checklist §10.
8. Ubah `SPosTrack`/format file track → bump `version` (§11).
9. Ubah skema bucket Brain → bump `AI_FILE_VERSION` + `AI_STRATEGY_FINGERPRINT` +
   `AI_STRATEGY_NAMESPACE` (§9).
10. Selesai edit → cek balance kurung kurawal/biasa/siku per file yang diubah sebelum
    menyerahkan hasil (indikasi cepat ada baris ketinggalan/kepotong), lalu compile di
    MetaEditor dan pastikan 0 error / 0 warning.
11. Update versi + tanggal di header file yang diubah signifikan (§5 template).
    Perubahan rilis EA: sinkronkan seluruh field dari `YANSTD_VERSION` melalui
    `Tools/sync_version.py` atau `Tools/Sync-Version.ps1`; identitas aktif selalu
    tercantum di pembuka dokumen.
12. Update tabel di §15.3 kalau menambah/mengubah lever tunable, dan §15.4 kalau item
    backlog selesai. Alignment spek Tahap 0/3/4 = §23.

---

## 15. Aturan Mengikat, Lever Tunable & Backlog

### 15.1 Aturan yang tidak boleh dilanggar

Enam aturan di bawah ini pernah dilanggar dan setiap kali menghasilkan kerusakan nyata.
Kalau sebuah perubahan menyentuh salah satunya, uji ulang terhadap aturannya.

**(a) SmartBrain adalah OVERLAY sizing, bukan prasyarat entry.**
Yang memutuskan sebuah trade dibuka adalah aturan **SMC + MSNR**. **[Diperbarui audit
2026-09-09]** Brain historically adjusted lot via `GetSizingMultiplier()`, tapi fungsi itu
sudah dihapus total sebagai dead code di v4.42 (§29) — lot sizing live sekarang murni
`SetupGradeLotMultiplier()` berbasis setup grade (lihat tabel di bawah), independen dari
Brain. Bucket yang belum memiliki
`AI_MIN_SIZING_EVIDENCE` bukti nyata ter-decay selalu netral (`1.0x`). Pola buruk yang sudah
memiliki cukup bukti dibatasi ke paling besar `0.50x`; ia tetap tidak membatalkan setup.

Jangan menambahkan kembali API atau cabang `IsSetupApproved()` ke pipeline. Perubahan Brain
baru harus tetap menghasilkan multiplier sizing dan tidak boleh melakukan `continue` /
`return false` pada kandidat entry. Aturan ini mencegah deadlock saat Brain belum mempunyai
bukti TAKE.

**(b) "Boleh dibaca" dan "boleh mengubah sizing" adalah dua ambang berbeda.**
`AI_MIN_DECISION_SAMPLE` (=1) untuk membaca bucket; `AI_MIN_SIZING_EVIDENCE` (=6 bukti nyata
ter-decay) untuk mengubah multiplier lot. Menyatukannya kembali akan membuat satu hasil awal
mengubah risiko secara berlebihan.

Satu "sample" = satu unit bukti **penuh**. `EffectiveBucketSample` memakai `MathFloor` murni, jadi
`AI_MIN_DECISION_SAMPLE = 1` berarti 1 trade live atau seluruh sibling matrix dari satu setup
yang bobot `1/N`-nya sudah berjumlah satu unit.
Jangan kembalikan pembulatan `MathFloor(x + 0.5)`: dengan pembulatan itu setengah unit (5 setup
matrix) sudah dilaporkan sebagai "sample 1", sehingga bucket EXACT setipis itu terpilih dan
mengalahkan bucket PROFILE yang memegang 27 unit — fallback EXACT → CORE → MITIGATION → PROFILE
justru dilewati tepat di titik yang paling butuh fallback. Itu overfitting pada ~3.456 bucket
dengan bukti yang jauh lebih sedikit, bukan pembacaan yang lebih sensitif.

**(c) `finalScore`/`qualityScore` tidak pernah di-blend dengan Brain confidence — V13.**
Sampai V12 ada blend bertingkat (`realEvidence >= AI_MIN_VETO_SAMPLE` ⇒ 70/30 (AI/SMC),
`>= 2.0` ⇒ 30/70) yang dimaksudkan sebagai kompromi, tapi itu sendiri masih **veto lewat
pintu belakang** di gate `SOFT_SCORE`: bucket berisi bukti nyata sesedikit 2 sampel saja
sudah bisa menarik `finalScore` turun cukup untuk gagal di ambang. V13 menghapus blend ini
sepenuhnya di kedua jalur (`YANSTD.mq5` dan `Modules/SignalEngine.mqh`): `finalScore =
smcScore` **selalu**, tanpa syarat evidence apa pun. `EffectiveBucketSample` (yang
digelembungkan bobot Q shadow-SKIP) tidak lagi relevan di sini karena tidak ada blend yang
bisa di-key ke situ.

**(d) `DynamicThresholdForBucket()` sekarang session-agnostic — V13.**
Sampai V12 fungsi ini membagi `bucketIdx` dengan `AI_TOTAL_BUCKETS / 4` untuk mendapatkan
`sessionIdx`, lalu mengembalikan `m_asiaThreshold` (sesi Asia) atau `m_overlapThreshold`
(sesi Overlap) — dan literal `10800` yang pernah tertinggal dari layout 43.200 bucket
membuat `sessionIdx` permanen 0 (semua sesi dinilai dengan ambang Asia, `InpMinAIConfidence` +
`InpBrainOverlapThreshold` jadi dead code). V13 menghapus cabang session ini sepenuhnya:
fungsi selalu mengembalikan `m_minConfidence` untuk **semua** bucket, sesi apa pun. Kelas
bug "divisor literal yang desync dari `AI_TOTAL_BUCKETS`" jadi tidak mungkin terjadi lagi di
titik ini karena tidak ada lagi pembagian sama sekali — bukan karena diperbaiki, tapi karena
levernya sudah dipindah keluar dari Brain (lihat §9). Pengali sesi itu sendiri
dihapus di v4.46; sesi tidak mengubah lot.
`InpBrainAsiaThreshold` / `InpBrainOverlapThreshold` dipertahankan hanya untuk kompatibilitas
`.set` lama.

**(e) Shadow SKIP tidak boleh menyegarkan jam decay bucket. [SEBAGIAN MOOT sejak
audit 2026-09-09 — lihat §31, koreksi lebih lanjut di bawah]**
`lastUpdateTime` adalah satu-satunya input umur untuk `DecayWeight`, dan berlaku untuk **seluruh**
bucket. Kalau shadow ikut menstempelnya, satu counterfactual membuat semua bukti di bucket itu
"segar" lagi — termasuk bukti nyata yang seharusnya melemah. Dan karena setiap veto melahirkan satu
shadow, bucket yang terus di-veto justru jam decay-nya terus di-reset, jadi **veto tidak pernah
kedaluwarsa** dan niat MED-G ("verdict basi kehilangan wewenang veto") tidak pernah benar-benar
berlaku. Aturan ini dulu ditegakkan di **dua** tempat — `ProcessShadowTrades()` dan jalur replay
journal. **Status sekarang (dikoreksi):** `ProcessShadowTrades()`/`RegisterShadowTrade()`/
`struct SShadowTrade` sudah dihapus total di audit 2026-09-09 (dead code — `shadowEnabled` selalu
`false`, tidak pernah dipanggil dari `YANSTD.mq5`), jadi **tidak ada lagi jalan untuk membuat
record SKIP (`action==0`) baru**. Tapi `ReplayJournal()` (masih ada, tidak disentuh audit ini)
tetap bisa memutar ulang segmen journal biner lama dari disk yang berisi record `action==0` —
baik dari sebelum fix ini, atau dari versi codebase yang lebih tua di mana `shadowEnabled` pernah
default `true`. Guard yang sama (`if(action == 1 || BucketEvidence(...) <= 0.0)
lastUpdateTime = ...`) masih ada persis di `ReplayJournal()` dan **masih wajib dipertahankan** —
jangan hapus atau longgarkan guard itu meski subsistem live-nya sudah tidak ada, karena journal
lama yang masih dipakai operator bisa saja masih berisi record SKIP.

**(f) Kunci tangga lot SPEC-C adalah `winWeight` yang sudah di-decay.**
`GetBucketView` dulu menyerahkan `winWeight` mentah sementara `realEvidence` di baris sebelahnya
sudah di-decay — dua standar berbeda untuk data yang sama, berjarak satu baris. Efeknya: bucket tua
dengan `winWeight = 20` menghasilkan `realEvidence ≈ 0,02` (benar: tidak punya wewenang veto) tapi
**tetap** menarik rung 2,50x, jadi risiko 2,5x per trade dari bukti yang sistemnya sendiri anggap
kedaluwarsa — dan karena cap agregat 3,0 %, clamp tidak pernah aktif sehingga tidak ada warning
apa pun di log. Rung harus **diraih ulang**, bukan diwarisi selamanya.

Ditambah aturan struktural yang sudah ada di bagiannya sendiri: hanya `COrderManager` yang
menyentuh broker (§3), rantai sizing tidak boleh dipotong (§7), enum reject selalu berpasangan
dengan `case` (§8), bump identitas dataset saat skema bucket berubah (§9), bump `version` saat
`SPosTrack` berubah (§11).

### 15.2 Spesifikasi entry & sizing yang berlaku

**Entry** = kombinasi **SMC + MSNR**, titik — MSNR+SMC memutuskan sendiri kelayakan entry
tanpa syarat apa pun dari Brain. Sejak v4.34 trigger market default adalah **syarat
gabungan Tahap 4**: Liquidity Sweep M3 terkonfirmasi **dan** CHoCH M3 terkonfirmasi
di dalam Zona_Final (`InpRequireM3Sweep=true`). M5 refinement default-nya **subset**
zona M15 (`InpRequireM5ContainedInM15=true`). Kedua lever bisa di-revert tanpa
menyentuh kode. "Reward > risk" (RR > 1,0) dijamin struktural oleh
`InpMinimumStructuralRRR=1.10`, independen dari Brain. Brain Bucket **tidak** menambah syarat
entry apa pun di atas itu. **[Diperbarui audit 2026-09-09, lihat §9 & §29]** Riwayat lama
menyebut `avgMFER = totalMFER / BucketEvidence` yang jatuh di bawah `InpBrainMinRewardRisk`
sebagai salah satu dari beberapa kondisi yang menurunkan pengali lot ke rung 0,50x lewat
`GetSizingMultiplier()` — fungsi itu sekarang sudah dihapus total (bukan sekadar dinetralkan
ke 1.0), dan audit ini juga mengonfirmasi `InpBrainMinRewardRisk`/`avgMFER`/`isBanned` tidak
pernah benar-benar ditegakkan di jalur eksekusi manapun bahkan sebelum fungsi itu dihapus:
`bestView` (`YANSTD.mq5`, `TryAutoLimitFallback`) diisi lalu tidak pernah dibaca lagi. Nilai
`InpBrainMinRewardRisk` sekarang murni diagnostik/telemetry, tidak menyentuh lot sama sekali.

**Tidak ada aturan minimal 8 trade.** Histori tetap dicatat akumulatif global untuk deteksi
kemiripan pola.

**Dynamic Lot Sizing — empat kelompok setup grade, bukan winWeight:**

| Grade | Multiplier | Syarat ringkas |
|---|---|---|
| S+ / S | 2.00x | QML/SBR/RBS; `+` = kualitas ekstra (Mode 0: `healthyR`; Mode 2: VIRGIN), **bukan** rung lot baru. Rung tertinggi tunggal (§56) |
| A+ / A | 1.50x | A/V/OCL; `+` = kualitas ekstra (Mode 0: `healthyR`/`usableR`; Mode 2: VIRGIN), **bukan** rung lot baru. Turun dari 2.00x per bukti Gen-6 (§56) |
| B+ / B | 1.00x | M3 ada, tetapi King lawan / OTE longgar / partial / kualitas sedang |
| C+ / C | 0.50x | limit tanpa CHoCH |
| D+ / D | 0 (tolak) | tidak ada peta / tidak ada overlap Layer 2 |

> **Kontrak final (v4.48.0, §56) — tabel di atas adalah satu-satunya source of truth.**
> `Modules/Defines.mqh::SetupGradeLotMultiplier()` wajib sinkron persis dengan tabel ini
> untuk seluruh 10 nilai `ENUM_SETUP_GRADE` (diverifikasi `Tests/Test_SetupGradeLotMultiplier.mq5`).
> S+/A+ sempat memakai 2.25x di v4.47.4–v4.47.7 — angka itu sudah dikoreksi kembali ke 2.00x
> di sini; riwayat keputusan lama tetap ada di `CHANGELOG.md` 4.47.4 dan 4.47.8.

**[Diperbarui audit 2026-09-09]** `GetSizingMultiplier()` sudah dihapus total sejak v4.42
(bukan sekadar mengembalikan 1.0) — lot sizing live sekarang murni dari Grade dan tidak
melewati Brain sama sekali. Grade dihitung di
`ClassifySetupGrade()` / `EvaluateSetupGrade()`, lalu dikalikan ke `effRisk`.
`InpUseDynamicRisk` tidak lagi menjadi sumber tangga. Exploration/collection mode tidak
mengalikan grade (risk koleksi tetap kecil).

> **Basisnya `winWeight`, BUKAN `wins` mentah.** `bucket.wins` naik `+1` per varian entry
> (satu setup lengkap dapat menghasilkan `+6` di matrix), sedangkan `winWeight` naik `evidenceWeight`
> (= `1/ENTRY_VARIANT_COUNT` ≈ 0,1667) sehingga satu setup lengkap menang = `+1,0`. Selain itu `wins`
> tidak pernah di-decay dan di jalur fusion `MergeWeighted` dibulatkan `MathRound` (bisa jadi 0),
> sedangkan `winWeight` konsisten di semua jalur. Kalau tangga membaca `wins`, satu setup menang
> langsung melompat ke rung 2,00x.
>
> **Dan `winWeight` yang dibaca tangga sudah di-decay** (§15.1 (f)) — rung harus diraih ulang,
> tidak diwarisi dari bukti yang sudah kedaluwarsa.

**V13 historis — pengali sesi Asia.** Sejak v4.46 input `InpAsiaSessionSizeMult` dan
`GetSessionSizeMultiplier()` dihapus. Lot live = risk% × grade (± overlay Brain 0,50×).
Sesi tidak mengalikan lot.

Konsekuensi yang sekarang berlaku: bucket Brain yang belum memiliki bukti sizing minimum tetap
neutral di **1,00x**; ia tidak memperoleh haircut global hanya karena belum pernah dilihat. Cek
`[YANSTD BRAIN DENSITY]` dan ringkasan akhir untuk memisahkan bukti nyata dari bucket yang belum
terbaca.

### 15.3 Lever tunable & cara revert

Semua di bawah ini adalah **parameter**, bukan koreksi wajib. Ubah **satu lever per run** supaya
efeknya terukur.

| Input | Nilai sekarang | Fungsinya | Revert / range |
|---|---|---|---|
| `InpSpreadCapFloorPips` | `3.5` | Lantai cap spread dalam **pip** (XAU 3,5 pip = $0,35). Cap efektif memakai ATR ketika `InpUseATRSpreadGate=true`; bila gate itu mati, `InpUseDynamicSpread=true` memakai ambang rolling monitor; selain itu memakai cap manual. Semua mode dibatasi floor dan `inp_max_spread`. | Per broker: raw-spread ECN ≈ 2,5 · standard ≈ 4–5. Floor harus ≥ spread normal broker |
| `InpMinRunnerInitialLot` | `0.04` | Batas lot minimum agar scale-out 50/25/25 aktif. 0.04 adalah batas **matematis** (leg 25 % → 0,01 di step 0,01) | Menaikkannya mematikan seluruh desain scale-out secara senyap (fallback = full-close di TP1) |
| `InpTP1RR` | `0.9` | Ambil partial 50 % di dalam impuls yang terbukti, sebelum retrace-ke-BE menghapusnya | Naikkan hanya dengan bukti; `InpTP2RR=1.6` default |
| `InpMilestoneTriggerR` / `InpMilestoneLockR` | `1.5` / `0.5` | Milestone relatif terhadap risiko struktural | Set masing-masing `0` untuk fallback pip legacy |
| `InpStructureTrailStartRR` | `1.2` | Disamakan dengan TP1 baru | Revert `1.5` (harus ikut `InpTP1RR`) |
| `InpStructureTrailBufferATR` | `0.75` | Napas volatilitas di bawah/atas pivot M3 supaya hanya **break struktur nyata** yang mengakhiri runner. Trail = `pivot ∓ spread ∓ buffer·ATR(TrailSwingTF,14)` | **Revert = `0`** (persis perilaku lama). Range uji wajar 0,5–1,5 |
| `InpUseDynamicRisk` | `true` (strict/live) | Menghidupkan tangga lot §15.2 | `false` = semua trade risiko flat, tanpa menyentuh kode |
| `InpBrainMinRewardRisk` | `1.00` (strict/live), `0.00` (matrix) | **[Dikoreksi audit 2026-09-09, §9]** Diagnostik-only — divalidasi 0–10 di `OnInit`, dipetakan ke `avgMFER` per-bucket, tapi tidak pernah dibaca untuk mengubah sizing atau kelayakan entry manapun | Aman diabaikan/di-set berapa pun; tidak ada efek pada lot atau entry saat ini |
| `InpMaxAggregateRiskPct` | `3.0` (strict/live) | Cap risiko agregat | `1.0` mematikan dua rung teratas (§12) |
| `InpEntryVariants` | `ALL` | Whitelist varian (`OB_15,OB_45,FVG_50,FIB_618,FIB_705,FIB_790`) | Enam varian aktif |
| `InpBlockSundayOpen` / `InpSundayOpenBlockHours` | `true` / `2` | Blokir entry baru pada gap pembukaan Minggu | `false` untuk reproduksi run lama |
| `InpVariantClusterMinATR` | `0.50` | Jarak minimum antar pending sibling dalam satu cluster | `0` = nonaktif; jangan gunakan fan-out rapat sebagai risiko independen |
| `InpMaxEntryDistanceATR` | `1.50` | Tolak limit yang lebih jauh dari harga sekarang daripada batas ATR(M5) | `0` = nonaktif; batas ini mengurangi pending expiry/churn |
| `InpRequireM3Sweep` | `true` | Sweep + CHoCH wajib untuk trigger M3 ber-konteks | `false` = CHoCH-only; direct-zone tetap diatur oleh `InpScanAllPOIsWhenNoTrigger` |
| `InpKingSNR_PrimaryTF` / `InpKingSNR_SecondaryTF` | `PERIOD_H4` / `PERIOD_H1` | Filter bias HTF; primary menang jika keduanya aktif | M30/H1 adalah default pre-4.34; dua TF wajib berbeda |
| `InpRequireM5ContainedInM15` | `true` | M5 harus subset M15 (`⊆`) | `false` = overlap + toleransi ATR (perilaku pre-4.34) |
| `InpMinFVG_ATR_Mult` | `0.30` | Lebar minimum FVG = ATR(TF,14)×ini | Satu-satunya input minimum gap FVG di seluruh layer |
| `InpMaxFVGBarAge` | `36` | Usia maksimum FVG (bar di TF-nya) | Naikkan untuk menjaga FVG lama |
| `InpFVGImpulseBodyRatio` | `0.70` | Body/range candle-2 FVG | `0.60` = perilaku impulse M5 lama |
| `InpRequireFVGStructureOverlap` | `true` | FVG entry wajib potong swing / SBR-RBS / HTF / psych | `false` = mekanis saja |
| `InpMaxEquityDDPct` | `20.0` | Peak-equity circuit breaker untuk entry baru; `0` = disabled | Existing positions tetap dikelola |
| `InpNewsTesterSimulate` | `true` | Synthetic NFP/CPI/FOMC calendar in tester | `false` hanya untuk reproduksi run lama |
| `InpLogLevel` | `INFO` | Controls ERROR/WARN/INFO/DEBUG log volume. Sejak audit 2026-09-07 gate ini **juga diberlakukan** pada `LogTradeError`/`LogSystemError`/`LogSystemWarning` (sebelumnya ketiganya bypass gate → penyebab utama file log 50GB saat retry `SafeModifySL` di-throttle broker). `DEBUG` only for focused diagnosis | — |
| `InpOOSStart` | `0` | UTC/server timestamp separating IS and OOS attribution in the final report | `0` disables the split |
| `InpMilestoneTriggerR` / `InpMilestoneLockR` | `1.50` / `0.50` | Milestone lock berbasis initial R | Set `TriggerR=0` atau `LockR=0` untuk fallback pip legacy |
| `AI_MIN_DECISION_SAMPLE` | `1` | Ambang baca bucket, dalam unit bukti **penuh** (§15.1 (b)) | Menaikkan ke 8 mengembalikan aturan min-8 trade yang sudah dihapus dari spec |
| `InpPOIScanBars` | `1200` | Kedalaman maksimum scan POI M5. Saat `InpZoneMaxBars>0`, EA memuat konteks tambahan untuk struktur/RVOL tetapi hanya mengevaluasi kandidat yang basis OB-nya masih berada dalam umur zona. Default 96 tidak lagi mengevaluasi kandidat yang pasti ditolak oleh age gate. | Set `ZoneMaxBars=0` untuk mengizinkan kedalaman penuh; turunkan `InpPOIScanBars` bila memang tidak memerlukan sejarah panjang. |
| Lot minimum broker | `0.01` | `CalcLotSize()` menaikkan hasil valid ke minimum legal (`LOT_CLAMP`) atau fallback metadata (`LOT_FALLBACK`) | Bukan penolak entry |
| `InpAllowSingleExitFallback` | `true` | **(baru)** Lot yang tidak bisa split 50/25/25 tetap ditradingkan dengan single exit | `false` = reject di pintu masuk seperti H4 semula |
| `InpScanAllPOIsWhenNoTrigger` | `true` | **(baru)** Tanpa CHoCH M3, tetap pindai semua POI untuk limit | `false` = perilaku lama (limit butuh konfirmasi market-execution) |
| `InpMinSLPips` / `InpMaxSLPips` | `0.0` / `0.0` | `0` = pagar pip mati; SL mengikuti struktur + ATR | Isi >0 hanya untuk lantai/atap pip cadangan. `Init` tidak boleh mengubah 0 menjadi 30/60. |
| `InpMinRunnerInitialLot` | `0.04` | Volume awal minimum agar split 50/25/25 menghasilkan tiga volume legal pada broker dengan langkah 0.01 lot | Posisi yang lebih kecil memakai `InpAllowSingleExitFallback=true` dan keluar sebagai satu volume |
| `InpMultiPosMinDistPips` | `40.0` | **(diubah)** Jarak minimum antar sinyal independen | 120 (= $12 di XAUUSD) membatasi EA ke ~1 posisi per sesi saat multi-layer OFF |
| `InpAsiaSessionSizeMult` | dihapus v4.46 | Sesi tidak mengubah lot | Input dan setter SessionManager dihapus |
| `InpBrainEventJournal` | `true` | Tulis raw-event journal biner per TAKE/SKIP resolve. Sejak audit 2026-09-07 **di-suppress otomatis di tester non-visual** (tidak ada operator yang replay; in-memory learning tetap). Live/forward/visual-tester tetap menulis. | `false` = mati total |
| `InpBrainJournalSegmentMB` | `64` | Ukuran maksimum satu segmen journal sebelum rotasi. Sejak audit 2026-09-07 jumlah segmen dibatasi `AI_JOURNAL_MAX_SEGMENTS=12`; segmen tertua dihapus saat rotasi (sebelumnya tumbuh tanpa batas → kontributor 50GB). | 1–2048, divalidasi di `OnInit` |

Jarak SL alami berasal dari **struktur + buffer eksekusi**. Jika hasilnya 10–70 pip, jarak tersebut dipakai apa adanya. Jika lebih dari 70 pip, setup tetap entry dan SL akhir menjadi 70 pip. Telemetry tetap merekam jarak alami sebelum cap.

### 15.4 Backlog terbuka

| Item | Isi | Kenapa belum |
|---|---|---|
| **R4b — SELESAI V11** | Strict tester read-only sekarang memakai resolver fusion yang sama dengan live. Historical strict menggabungkan RT+OHLC masing-masing satu kali; forward/demo/live menggabungkan LIVE+RT+OHLC. Matrix learning tetap source-isolated. | Diverifikasi melalui cabang `m_useFallback` dan `sourceIsLive` di `SmartBrain.mqh` |
| Beban rebuild Brain | `RebuildHierarchyFor()` menyapu seluruh 3.456 bucket per trade yang dipelajari. Shadow processor sudah dihapus total di audit 2026-09-09 (sebelumnya sudah tidak dipanggil karena Brain tidak memveto entry dan tidak ada sinyal SKIP untuk diregistrasikan). | Rebuild incremental hanya diperlukan bila profiling masih menunjukkan bottleneck |
| **Dua formula skor — SELESAI V13** | `YANSTD.mq5` dan `SignalEngine.mqh` dulu punya formula skor kandidat berbeda: `SignalEngine.mqh` masih memanggil `IsSetupApproved()` (veto dead-code) dan mem-blend confidence ke `finalScore`, `YANSTD.mq5` sudah tidak. Sekarang keduanya identik: tidak ada veto, `finalScore = smcScore` murni, sizing lewat `GetSizingMultiplier()` yang sama. | Diverifikasi lewat kedua blok BUY/SELL di `SignalEngine.mqh` dan blok sizing bersama di `YANSTD.mq5` |
| News di tester | **SELESAI M4** — `InpNewsTesterSimulate=true` membangun kalender sintetis NFP/CPI/FOMC; NFP/CPI near-exact, FOMC approximate | Set false hanya untuk reproduksi run legacy |
| Phase-2 M5 rescan | **SELESAI audit:** dengan age limit aktif, konteks scan dibatasi, lalu kandidat dengan basis OB di luar `InpZoneMaxBars` tidak dievaluasi. POI tidak dihapus hanya karena retrace; invalidasi struktur memerlukan `InpPOIInvalidationCloses` close M3 berturut-turut di luar sisi jauh + `InpPOIInvalidationBufferPips`. Wick saja tidak membatalkan zona. Pending order terkait direkonsiliasi saat invalidasi M3. | Tidak ada perubahan definisi retest parsial. |
| Exit ladder unit | `TP1ProfitLock=25`, `Milestone 120/60`, `EarlyBEP=50` masih pip sementara TP pakai R | Perubahan semantik input user-facing; perlu keputusan produk (input mode "pip vs R") |
| **R2c** | Jadikan swing-trail M5 sebagai manajer runner sejak **TP1** (bukan TP2) dan matikan override trail M3 | Butuh field `tp1Time` + ubah 2 modul. Simpan sebagai varian kalau buffer §15.3 belum cukup |
| **Pilihan B** | Filter regime ADX/volatilitas untuk melewati tahun regime ekstrem | Ekspektansi terbesar **tapi risiko overfit tertinggi** — jangan dikerjakan sebelum lever lain habis |
| Guard tambahan | Max consecutive losses / weekly drawdown | Ide, belum diprioritaskan |
| **Kosmetik — SELESAI (line ending) 2026-09-05** | Line ending campuran CRLF/LF (`SmartBrain.mqh`, `SignalEngine.mqh`, `YANSTD.mq5`, `ZigZagEngine.mqh`) dinormalisasi ke LF di seluruh source. Tidak ada perubahan fungsional. | Cukup diff-noise fix, tidak butuh keputusan produk |
| Kosmetik (masih terbuka) | ZigZag `dev` no-op di gold; session-classifier inline di `UpdateStatsFromHistory` belum ikut US DST (statistik tampilan saja) | Input spread dinamis sudah dihubungkan ke pemilihan cap efektif pada audit ini. |
| Proyek terpisah | Sparse bucket storage · model slippage limit-fill di tester · harness walk-forward | Bukan fix, butuh perencanaan sendiri |
| **Leak file 50GB & handle leak — SELESAI audit 2026-09-07** | (a) `LogTradeError`/`LogSystemError`/`LogSystemWarning` kini di-gate `g_logLevel` (sebelumnya bypass → penyebab utama file log 50GB saat retry `SafeModifySL` di-throttle broker); (b) log retry `SafeModifySL`/`ClosePosition`/`PartialClose` di-throttle per (ticket,retcode) per 60s; (c) journal raw-event + snapshot periodik di-suppress di tester non-visual, segmen dibatasi `AI_JOURNAL_MAX_SEGMENTS=12`; (d) handle ATR static `GetCachedATR` di-release di `OnDeinit` lewat `ReleaseCachedATRHandles()`; (e) `m_tracks` di-shrink di `Init`. Detail lengkap §19. Tidak ada perubahan logika trading. | Murni resource/telemetri hygiene; verifikasi compile + run backtest untuk konfirmasi volume file turun dari puluhan GB ke beberapa MB |
| **Win Rate reset tidak persisten — SELESAI audit 2026-09-07** | Tombol `BTN_CLEAR_WR` menulis `lastDayReset`/`lastSessionReset` yang tidak pernah dibaca; `UpdateStatsFromHistory()` menghitung ulang total all-time tanpa baseline, jadi statistik "kembali" begitu ada deal/hari/sesi/posisi baru. Diganti satu field `resetEpoch` yang benar-benar dikonsumsi (filter di akumulasi daily + finalisasi posisi selesai), plus handler tombol memaksa rebuild segera lewat `g_statsHistoryDirty=true`. Detail §20.1. | — |
| **`GetPosition()` O(n²) & dead-code `ControlPanel.mqh` — SELESAI audit 2026-09-07** | `GetPosition(index,...)` di-cache per-ticket (rebuild hanya saat `PositionsTotal()` berubah) alih-alih re-scan `PositionsTotal()` akun-wide tiap panggilan; `GUI_DrawControlPanel`/`_CP_Btn`/`_CP_Rect` (dead code, tidak pernah dipanggil) dihapus dari `ControlPanel.mqh`. Nomor versi (`4.31`/`4.12`/`"4.0-HYBRID"`) disatukan ke `4.32`. `PointsToPips`/`SafeObjName`/`FormatMoneyWithPips`/`YANSTD_MAGIC` (tidak terpakai) dihapus. Detail §20.2–§20.5. | — |
| **`CMTFTrendMeter` dead code + `SMTFResult()` bare default — SELESAI audit 2026-09-08** | `SMTFResult()` dipanggil sebagai struct temporer default (bukan hasil live) di 3 titik, termasuk sebagai dimensi bucket key `g_brain.GetBucketIndex()` — BUY selalu `bullPct=0.0`, SELL selalu `100.0`, jadi setiap setup jatuh ke sudut tetap yang sama di sumbu MTF-confluence, dan Trend Card dashboard selalu kosong/netral. `CMTFTrendMeter` (`Modules/MTFTrendMeter.mqh`) sudah lengkap tapi tidak pernah diinstansiasi. Diperbaiki: instance global `g_mtf`, `g_mtf.Init()` + `g_mtf.Calculate()` sekali di `OnInit()`, `g_mtf.Calculate()` di-refresh tiap bar M3 baru (cadence tercepat dari 6 TF yang dikonsumsi) di `OnTick()`, ketiga situs `SMTFResult()` diganti `g_mtf.GetResult()`. Detail §21.1. | — |
| **`effectiveRefinementTF` dihitung ulang identik di 4 titik — SELESAI audit 2026-09-08** | Ekspresi ternary `InpUseM5Refinement ? inp_mtf_period : inp_htf_period` diduplikasi di `OnInit()`, `OnTick()`, dan dua helper — nilainya konstan sepanjang run. Di-cache satu kali ke global `g_effectiveRefinementTF` di awal `OnInit()`, keempat situs pemakaian diarahkan ke global itu. Murni dedup, tidak ada perubahan perilaku. Detail §21.2. | — |
| **Log spam RISK GUARD + FIFO POI O(n) — SELESAI audit 2026-09-08 (v4.33)** | `LogThrottled()` generik per-tag; FIFO POI jadi circular buffer O(1); compact expire satu pass O(n); cache SymbolInfo/ATR di loop kandidat; dead `OnTimer` lastMTF dihapus; properti visual statis hanya di-set saat create. Detail §22. | — |
| Scan MSNR incremental penuh | `Scan()`/`ScanQML()`/`ScanKingSNRTF()` masih rebuild lookback penuh tiap bar HTF baru. Sudah ada skip same-bar. Incremental (proses hanya bar baru + revalidasi window aktif) adalah perubahan arsitektural. | Kerjakan hanya jika profiling backtest multi-tahun menunjukkan ini bottleneck nyata |
| **Sweep M3 opsional vs spek joint-gate — SELESAI v4.34** | Spek Tahap 4: sweep **dan** CHoCH wajib. Kode hanya memakai CHoCH sebagai veto, sweep sebagai booster. Ditambah `InpRequireM3Sweep=true` yang men-AND-kan `m3SweepConfirmed` ke `isBullReversal`/`isBearReversal`, reject `REJECT_SWEEP_NOT_CONFIRMED`. Detail §23.1. | Revert: `InpRequireM3Sweep=false` |
| **Default King SNR M30/H1 vs spek H4/H1 — SELESAI v4.34** | Default input + komentar stale dikembalikan ke H4 primary / H1 fallback. Logic scan tidak diubah. Detail §23.2. | Set M30/H1 untuk reproduksi run pre-4.34 |
| **M5 vs M15 overlap vs ⊆ — SELESAI v4.34** | `EvaluatePrimaryGate` default containment ketat (`InpRequireM5ContainedInM15=true`). Overlap+ATR tetap tersedia. Detail §23.3. | `false` untuk reproduksi overlap |
| **Definisi OB M3 + containment M3⊆M5 — diperbarui v4.47.9** | OB M3 dapat valid tanpa FVG selama syarat refinement/trigger M3 terpenuhi. FVG valid menambah profil/confluence `OB_FVG`, bukan gerbang wajib untuk `OB_45`. Refined M3 harus di dalam parent M5. Detail §24 dan §48. | Tidak ada input revert; ini kontrak aktif |

Yang **sengaja tidak** dikerjakan (keputusan, bukan kelalaian): invalidasi zona MSNR berbasis
**close** (wick ≠ invalidasi) — mengubahnya ke intrabar menaikkan false-invalidation; RVOL tetap
`OR` karena leg OB tetap wajib body ≥ 0,60 di baris berikutnya; footprint memori SmartBrain
fixed-size (bukan leak); clamp senyap `RoundLotToStep` **ke arah `VOLUME_MAX`** (§7 — arah
`minLot` memakai lantai keras 0,01; lihat §32).

### 15.5 Jebakan saat menafsirkan hasil backtest

Baca ini **sebelum** menyimpulkan sesuatu dari run tester.

1. **Strict mode membekukan Brain.** `strictHistoricalValidation = MQL_TESTER && !MQL_FORWARD &&
   InpTesterExecutionMode == TESTER_LIVE_STRICT`, dan `effectiveBrainLearning = InpAILearning &&
   (!strictHistoricalValidation || InpStrictValidationLearning)`. Keempat preset mengirim
   `InpStrictValidationLearning=false` ⇒ di strict, brain **read-only**
   (log `[YANSTD TEST SAFETY] SmartBrain learning is READ-ONLY during strict validation`).
   Artinya brain fresh **tidak akan pernah** menumpuk `winWeight` di strict, jadi multiplier tetap
   netral 1,0x dan `[YANSTD LOT LADDER]` tidak pernah muncul. **Urutan yang benar:** jalankan
   MATRIX (learning ON) untuk melatih → simpan brain → jalankan STRICT memakai brain itu.
   EA sekarang mencetak `[YANSTD TEST VALIDITY]` kalau kombinasi ini terdeteksi (§12).
2. **Brain FRESH vs TERLATIH.** Leakage guard hanya memicu bila `TimeCurrent() <= learnedMax`,
   jadi pada OOS murni brain lama **tetap dimuat lengkap dengan `isBanned`-nya**. Untuk run
   "bersih", hapus dulu file di `Common\Files\YANSTD\SmartBrain\REALTICK\`. Untuk menguji nilai
   overlay-nya, biarkan file-nya.
3. **Win-rate di layar tester menyesatkan.** Tiap partial TP1/TP2 dihitung sebagai satu "profit
   deal", jadi layar bisa menunjukkan ~56 % padahal WR **per posisi** ~41 %. Pakai angka
   per-posisi dari log `Learned closed position`.
4. **Counter funnel bernilai 0 bisa berarti "tidak pernah tercapai"** — lihat catatan di §8.
5. **Decay 0,5^(umur/90)** membuat bukti latih yang berjarak > 1 tahun dari periode uji praktis
   tidak berpengaruh. Jangan simpulkan "brain tidak bekerja" tanpa mengecek umur buktinya.
6. **Sebaran bukti.** ~1.000 trade dibagi 3.456 bucket = ~0,29 sampel/bucket, jadi mayoritas
   keputusan datang dari level hierarki kasar (CORE/MITIGATION/PROFILE), bukan EXACT. Hanya
   state EXACT tetap tipis. Jangan menebak angkanya — baca
   `[YANSTD BRAIN DENSITY]` di awal dan akhir run (§12).
7. **Reason string sizing yang menandai desain bekerja (bukan error):** bucket dengan bukti
   kurang dari `AI_MIN_SIZING_EVIDENCE` tetap 1,0x. **[Dikoreksi audit 2026-09-09, lihat §9 &
   §31]:** klaim sebelumnya bahwa "`reward potential … < required …R` menurunkan sizing pola
   yang sudah memiliki bukti cukup" **tidak akurat** — tidak ada reason string semacam itu di
   kode saat ini (dicek lewat grep, nihil), dan `InpBrainMinRewardRisk`/`avgMFER`/`isBanned`
   terkonfirmasi diagnostik-only: `bestView` di `YANSTD.mq5` diisi lalu tidak pernah dibaca
   untuk sizing. Kalau melihat lot berkurang di log, penyebabnya adalah `SetupGradeLotMultiplier()`
   (grade) atau overlay Brain 0,50×, bukan reward-potential dan bukan pengali sesi (sudah dihapus).
8. **Jangan tafsirkan run 0-trade sebagai "filter kelewat ketat"** sebelum memastikan gerbang
   terminal dan reject counter. Brain 4.39 tidak dapat mengurangi jumlah entry.
9. **`sizing-capable = 0` berarti Brain masih netral di run itu.** Tidak ada bucket yang lolos
   `AI_MIN_SIZING_EVIDENCE`, sehingga hasil mengukur SMC+MSNR dengan sizing dasar.
10. **Hasil sebelum dan sesudah batch fix HIGH tidak sebanding.** Empat fix mengubah perilaku
    Brain (semantik sampel jadi unit penuh, `winWeight` untuk tangga lot kini ikut decay, veto
    Q-SKIP sekarang wajib punya bukti nyata, shadow tidak lagi mereset jam decay — subsistem
    shadow itu sendiri sudah dihapus total di audit 2026-09-09, lihat §15.1(e) & §31). Fix lainnya
    murni kecepatan/kebersihan dan tidak mengubah keputusan. Jadi kalau angka berubah setelah
    batch ini, itu **memang harusnya berubah** — bukan regresi.

### 15.6 Status Pembaruan Sistem (Rumus Teknis MSNR-SMC ATR & SmartBrain)

Pembaruan arsitektur sistem MSNR + SMC Simplified (berdasarkan `Changelog-Sistem-MSNR-SMC.md` dan `Rumus-Teknis-MSNR-SMC-ATR.md`):

1. **Tahap 0 — King SNR H4 & H1 Dual Scan (Filter Bias Arah):**
   - Pemindaian independen pada `InpKingSNR_PrimaryTF` / `InpKingSNR_SecondaryTF` (default `PERIOD_H4` lalu `PERIOD_H1`, `lookback = InpKingSNR_LookbackBars`).
   - Invalidation Buffer = `0.10 × ATR(TF, 14)`.
     - King Support gugur jika: `Close < Low[2] - Buffer`.
     - King Resistance gugur jika: `Close > High[2] + Buffer`.
   - Validasi Sweep:
     - King Support: `Close[2] > Low[1]`.
     - King Resistance: `Close[2] < High[1]`.
   - Hierarki Bias: Prioritas **H4**. Jika H4 netral / unmitigated habis, fallback ke King SNR H1. King SNR bukan zona entry presisi, melainkan filter arah izin trade.

2. **Tahap 1A & 1B — M15 Order Flow OB & FVG (Zona Kandidat Utama):**
   - **M15/M5 FVG Gap**: Lebar minimum gap imbalance = `InpMinFVG_ATR_Mult × ATR(TF,14)` (default `0.30`; satu input konsisten di semua layer).
   - **M15 Order Flow OB**:
     - Warna candle basis bebas (candle sebelum displacement).
     - Wajib dikonfirmasi oleh candle displacement yang menghasilkan FVG valid.
     - Batas zona memakai seluruh range wick candle OB: `[Low, High]` untuk Demand maupun Supply. Warna candle tidak menentukan arah OB.

3. **Tahap 1C — M15 QML Tolerance Band:**
   - Deteksi pola 4-titik (H-L-LL-HH untuk Buy, L-H-HH-LL untuk Sell).
   - Toleransi zona Left Shoulder = `0.10 × ATR(M15, 14)`.
   - Zona Entry: `[LL1 - Tol, LL1 + Tol]` (Buy QML) atau `[HH1 - Tol, HH1 + Tol]` (Sell QML).
   - **Konfirmasi breakout (v4.47.3):** candle di antara swing `j+2` dan `j+3` harus **close** menembus first high (BUY: `close > firstHigh + sigDist`) atau first low (SELL: `close < firstLow - sigDist`). Wick pivot ke-4 saja tidak cukup.
   - Wajib overlap dengan OB/FVG M15 (Overlap Gate).

4. **Tahap 2 — Dealing Range Fibo OTE:**
   - Default berlaku sekarang: `InpRequireZoneOTE=true`, midpoint di band **0.618–0.786** (`InpMSNROTEFibMin=0.618`, `InpMSNROTEFibMax=0.786`). Sebelum v4.47.3 far ratio tertulis 0.790.
   - Preset Very High Risk boleh mematikan OTE untuk frekuensi. `false` = mode v4.39 (OTE hanya bonus skor).

5. **Tahap 3 — M5 Refinement OB Width Cap + containment:**
   - Mempersempit POI M15 ke OB M5 yang belum termitigasi.
   - Default v4.34: `Zona_OB_M5 ⊆ Zona_M15` (`InpRequireM5ContainedInM15=true`, slack 1 point untuk rounding). `false` mengembalikan overlap + toleransi ATR.
   - Lebar zona OB M5 dibatasi: `(Top - Bottom) <= 1.5 × ATR(M5, 14)`. OB yang melebihi batas ini di-reject.

6. **Tahap 4 — M3 Trigger Tunggal (Sweep **dan** CHoCH):**
   - **Liquidity Sweep**: Buffer penembusan level swing = `0.05 × ATR(M3, 14)`.
   - **CHoCH Confirmation**:
     - Buy: `Close[1] > SwingHigh + 0.05 × ATR(M3, 14)` dengan validasi `Close[2] <= SwingHigh`.
     - Sell: `Close[1] < SwingLow - 0.05 × ATR(M3, 14)` dengan validasi `Close[2] >= SwingLow`.
   - **Syarat gabungan untuk trigger M3:** sweep terkonfirmasi **lalu** CHoCH. Gagal sweep → `REJECT_SWEEP_NOT_CONFIRMED`. Gagal CHoCH → `REJECT_CHOCH_NOT_CONFIRMED`. `InpRequireM3Sweep=false` mengembalikan CHoCH-only; `InpUseLiquiditySweep` tetap hanya bonus skor. Bila direct-zone aktif, kegagalan trigger hanya berarti tidak ada refinement M3; POI parent tetap dipindai untuk pending limit.
   - Waktu konfirmasi disinkronkan dengan bar open time (`m3Rates[1].time >= anchorTime`). Anchor memakai `m3SweepTime` jika sweep sudah ada, selain itu `firstTouchTime`.
   - **Definisi OB M3 (v4.35):** `ENTRY_TYPE_OB_45` hanya jika candle `m3Rates[2]` (base sebelum CHoCH) **sendiri** melakukan sweep (`0.05×ATR M3`) **dan** candle displacement `m3Rates[1]` meninggalkan FVG 3-candle vs `m3Rates[3]`. Tanpa itu, fallback `ENTRY_TYPE_FVG_50` jika FVG valid; jika keduanya gagal → `REJECT_OB_NO_FVG`. `m3SweepConfirmed` (window 3 bar) **bukan** syarat label OB.
   - **Containment M3 ⊆ M5 (v4.35):** refined OB/FVG M3 harus berada di dalam POI M5 induk, slack `0.05×ATR(M3,14)`. Gagal → `REJECT_M3_OUTSIDE_PARENT_ZONE`.
   - 10 varian entry dan Layer 6 ICT Booster Score telah dibersihkan secara tuntas dari sistem.

7. **Harmonisasi dengan SmartBrain (AI Q-Learning 3.456 State):**
   - **Zone Width Bucket (`zIdx`)**: Skala diskretisasi zona Brain (`<0.5*ATR`, `0.5-1.0*ATR`, `>=1.0*ATR`) secara native selaras dengan batasan ATR M15 & M5 baru.
   - **POI Profile (`poiProfile`)**: Berlaku untuk M5, M15, H1, H4 dan lebih tinggi — semua OB yang valid di timeframe itu berpasangan dengan FVG, sehingga secara konsisten terklasifikasi sebagai `POI_PROFILE_OB_FVG` (lihat §48, H3). **Pengecualian: M3.** OB M3 boleh valid tanpa FVG (refinement/trigger), sehingga `POI_PROFILE_OB_ONLY` hanya bisa muncul dari jalur M3.
   - **Fibonacci Confluence (`fibLevel`)**: Area Dealing Range OTE memetakan fitur diskon/premium ke tabel Q-learning tanpa merusak struktur memori.
   - **Single Trigger Weight**: Sinyal CHoCH tunggal memberikan bobot observasi bersih (`1.0`) ke update reward Q-learning.

8. **SL / TP Sistem Existing:** Tetap dipertahankan (SL swing/ATR, TP1 0.9 RR partial close + BEP, TP2 1.6 RR, runner trailing).

**Status Kompilasi:** 0 errors, 0 warnings dikompilasi via MetaEditor 64-bit (X64 Regular).

File yang paling sering disentuh: `YANSTD.mq5`, `Modules/MSNREngine.mqh`, `Modules/SMCLayerM15.mqh`, `Modules/SignalEngine.mqh`, `Modules/Defines.mqh`, `Modules/SmartBrain.mqh`, dan keempat file `.set`.

---

## 16. Cara Pakai Dokumen Ini di Sesi Baru / Vendor AI Lain

Saat mulai sesi baru (apalagi di vendor AI berbeda), lampirkan file ini bersama source
code, lalu instruksikan singkat, misalnya:

> "Ini EA MT5 saya (SMC + MSNR hybrid). Ikuti `YANSTD_EA_SYSTEM_GUIDE.md` untuk konvensi
> arsitektur, penamaan, dan pola yang sudah ada — jangan refactor pola yang sudah
> berjalan kecuali diminta eksplisit. Baca §15.1 sebelum menyentuh SmartBrain."

Ini membantu AI manapun langsung "nyambung" dengan struktur project tanpa menebak dari nol,
dan menjaga hasil kerja antar-vendor tetap konsisten. Kalau sebuah aturan di dokumen ini
ternyata sudah tidak benar, **perbaiki dokumennya** — file ini adalah sumber kebenaran tunggal,
jadi dokumen yang basi lebih berbahaya daripada dokumen yang pendek.

---

## 17. Changelog — Audit 2026-09-05

> **Implementation update — audit fixes applied (2026-09-06)**
>
> The following behaviour is now enforced in the source. Sections 05 (backtest
> advice) and 06 (personal advice) of the audit remain intentionally out of scope.
>
> - **H1 — variable SL (diperbarui v4.46).** Bound aktif = ATR 0,35–2,50× pada market dan limit. `InpMinSLPips`/`InpMaxSLPips` default 0 = off. `InpNarrowSLPolicy` / `InpWideSLPolicy` legacy, tidak dibaca.
> - **H2 — variant whitelist and cluster separation.** `InpEntryVariants` accepts CSV or pipe-separated names (`OB_15`, `OB_45`, `FVG_50`, `FIB_618`, `FIB_705`, `FIB_790`; `ALL` means all six active IDs). Sibling pending prices must be at least `InpVariantClusterMinATR × ATR(M5)` apart.
> - **H3 — managed time invalidation.** Stagnant-position closes use an idempotent request state machine: one initial request per ticket, a five-second escalation, then an explicit unmanaged error. Repeated per-tick close spam is suppressed and counted.
> - **H4 — staged exits are an entry contract.** When TP1/TP2 is enabled, a lot is rejected unless the broker can express the configured staged split. The late fallback is explicit (`HOLD_FULL` in the EA) and is counted as an integrity event rather than silently presented as a valid runner.
> - **H5 — risk is normalized.** In explicit matrix/collection mode the configured collection risk is treated as a signal-cluster budget and divided across the allowed variants before lot calculation. Strict/live mode places one selected candidate.
> - **H6 — reachable exits.** Defaults are TP1 `0.9R` and TP2 `1.6R`. When staged TP1/TP2 exits are enabled, the effective structural requirement is `1.6R`, so the runner is not deliberately targeted through opposing structure. Milestone trigger/lock are R-relative (`InpMilestoneTriggerR=1.5`, `InpMilestoneLockR=0.5`) with legacy pip inputs only as an explicit fallback.
> - **H7 — SL/TP ordering invariant.** Protective SL modifications are rejected before send when they would cross the position TP; failed protection is logged as an error and counted.
> - **H8 — safe tester mode.** `InpTesterExecutionMode=TESTER_MATRIX_OFF` is the default. `TESTER_MATRIX_COLLECTION` is explicit research mode; `TESTER_LIVE_STRICT` remains single-candidate validation.
> - **M4 — tester news parity.** `InpNewsTesterSimulate=true` builds a rule-generated synthetic NFP/CPI/FOMC calendar in the Strategy Tester. NFP/CPI are near-exact; FOMC dates are approximate within a few days. Setting it false intentionally restores the bypass.
> - **M2 — weekend boundaries.** Friday close is logged with UTC timestamp and requested-position count. `InpBlockSundayOpen=true` blocks new entries during the first `InpSundayOpenBlockHours` simulated-UTC hours after Sunday open. Both use `CSessionManager`'s configured broker-offset/DST conversion.
> - **M5/M8 — attribution telemetry.** Pending placements, fills, expirations and cancellations are captured from trade transactions. Completed positions are attributed by variant, direction, session, year and optional IS/OOS segment independently of Brain learning, so strict/read-only runs still produce directional diagnostics.
> - **M6 — POI age.** The default age limit is now 96 M5 bars; `0` disables age expiry.
> - **L2/L4/L5/L6 — run telemetry and protection.** `InpMaxEquityDDPct=20` adds a peak-equity drawdown breaker for new entries. `InpOOSStart` enables direct IS/OOS attribution. `PrintFinalSummary()` includes integrity counters, pending lifecycle, equity drawdown, detected intraday data gaps, per-variant, per-session, per-direction and per-year confidence intervals.

### 17.1 Current implementation notes

All stop, sizing and exit documentation below this point must be read with the update above: the old statements that the matrix always clamps SL, that fresh Brain buckets are globally sized at 0.50x, and that tester news is always bypassed are obsolete.


Dokumen ini sengaja bukan riwayat perubahan (lihat catatan pembuka), tapi pass ini mengubah
**dua keputusan produk** yang sebelumnya didokumentasikan eksplisit di §9/§12/§15.4, jadi
dicatat di sini sebagai satu-satunya pengecualian — supaya sesi berikutnya tidak menganggap
§12 versi lama masih berlaku. Tabel/paragraf terkait di §9, §12, dan §15.4 sudah diupdate
langsung; bagian ini hanya rangkuman kenapa.

### 17.1 Kebijakan baru — pending-order capacity ikut `InpMaxActivePositions` di STRICT/LIVE
- **File:** `YANSTD.mq5` (`TryAutoEntry()`, `ManageAutoLimitOrders()`)
- **Sebelumnya (didokumentasikan §12 versi lama):** pending cap hardcoded `1` di eksekusi
  live/strict, terlepas dari `InpMaxActivePositions`/`InpMultiLayerEntry` — dianggap "by
  design" karena STRICT dimaksudkan hanya memegang satu kandidat berkonviksi tertinggi.
- **Sekarang:** `maxPendingSlots = g_multiLayerAllowed ? max(1, g_effectiveMaxPositions -
  openCount) : 1`, sama seperti ceiling yang sudah dipakai untuk open position (§2). Ini
  **keputusan yang disengaja untuk diterima sebagai kebijakan baru**, bukan revert ke versi
  lama. Efek: akun netting atau `InpMultiLayerEntry=false` tidak berubah (tetap cap = 1). Akun
  hedging dengan `InpMultiLayerEntry=true` + `InpMaxActivePositions>1` sekarang bisa memegang
  beberapa kandidat/posisi independen sekaligus di STRICT/LIVE — bukan cuma di MATRIX seperti
  sebelumnya. Kalau Anda ingin kembali ke perilaku single-slot-only tanpa syarat, set
  `InpMaxActivePositions=1` di preset live/strict (§12).

### 17.2 Enam input retired dihapus total (bukan sekadar ditandai deprecated)
- Konvensi umum proyek (§15.4) tetap: input dead **default**-nya ditandai `[DEPRECATED]` di
  komentar, bukan dihapus, demi kompatibilitas `.set` lama. Enam input di bawah ini adalah
  **pengecualian yang disengaja** terhadap konvensi itu, karena masing-masing sudah dikonfirmasi
  eksplisit **nol efek** di gate manapun (bukan sekadar dugaan):
  - `InpMultiPosMinConf` (V12 — Brain tidak pernah memblokir scale-in)
  - `InpBrainProbeEveryNRejects`, `InpBrainProbeRiskPct` (V13 — tidak ada veto/probe entry Brain)
  - `InpBrainAsiaThreshold`, `InpBrainOverlapThreshold` (V13 — threshold sesi di Brain dihapus;
    `InpAsiaSessionSizeMult` kemudian juga dihapus v4.46 — lihat §9)
  - `InpMaxSpreadATRFrac` (R1b — digantikan `InpMaxSpreadATRMult` + `InpSpreadCapFloorPips`)
- Dihapus dari declaration, `ValidateInputs()`, dan signature `CSmartBrain::Init()` (4 parameter
  lebih sedikit; satu call-site di `YANSTD.mq5` ikut diupdate). `.set` lama yang masih menulis
  key ini akan di-*ignore* diam-diam oleh MT5 saat load — perilaku normal untuk unknown key,
  tidak memengaruhi setting lain di file.
- **Item backlog `InpUseDynamicSpread*` (§15.4) TIDAK termasuk** dalam pengecualian ini — masih
  ikut konvensi default (tandai deprecated, jangan hapus) sampai ada audit terpisah yang
  mengonfirmasi nol efeknya.

### 17.3 Ditambahkan — `OnTester()` (kriteria optimasi kustom)
Sebelumnya tidak ada `OnTester()` sama sekali, sehingga Strategy Tester report selalu
menunjukkan "OnTester result: 0" dan genetic optimization tidak punya sinyal fitness custom.
Formula yang ditambahkan:

```
score = NetProfit × max(0, RecoveryFactor) × sqrt(TotalTrades) × min(1, TotalTrades / 30)
```

Menghargai profit hanya kalau didukung Recovery Factor (drawdown-adjusted) yang sehat **dan**
sample trade yang cukup besar untuk bermakna statistik. Run di bawah 30 trade diskalakan turun,
bukan di-exclude keras, supaya genetic optimization tetap dapat gradien, bukan tebing. Sesuaikan
konstanta lantai sample `30` kalau dataset/timeframe Anda mengubah definisi "sample bermakna".

### 17.5 Kebijakan baru — `InpMaxSpreadATRMult` dinaikkan 0.15 → 0.25
- **File:** `YANSTD.mq5` (input declaration saja, tidak ada logic yang berubah)
- **Alasan:** funnel diagnostics kumulatif 15 tahun (2007-2021, run realtick/matrix) menunjukkan
  `SPREAD_GT_ATR_CAP` adalah kategori penolakan **terbesar**: 38,33% dari seluruh
  category-minute occurrence (3.478.175 dari 9.075.459), bahkan sempat 53-58% di
  bulan-bulan awal 2007. Ini gate tunggal paling restriktif di seluruh funnel.
- **Caveat yang belum diverifikasi:** kualitas data spread historis broker untuk tahun
  2007-2012 belum dicek — MT5 kadang merekonstruksi spread lama secara tidak akurat untuk
  data setua itu (History Quality 100% cuma menjamin fidelity **harga**, bukan spread).
  Kalau setelah 0.25 funnel `SPREAD_GT_ATR_CAP` masih dominan di tahun-tahun awal secara
  tidak wajar, curigai data spread-nya dulu sebelum menaikkan mult lagi.
- **Lever terkait (§15.3):** `InpSpreadCapFloorPips=3.5` tidak diubah di pass ini.

### 17.6 Kebijakan OTE Fibo — opsional secara menyeluruh, strict mode opt-in
- **File:** `YANSTD.mq5` (input baru), `Modules/MSNREngine.mqh` (`AddZone()`, `Init()`)
- **Input:** `InpRequireZoneOTE` (default **`true`**), `InpMSNROTEFibMin=0.618`, `InpMSNROTEFibMax=0.786` (v4.47.3; sebelumnya far 0.790). Very High Risk preset = `InpRequireZoneOTE=false`.
- **Sebelumnya:** `AddZone()` di `MSNREngine.mqh` punya hard gate — `if(!formationOTE)
  return false;` — zona yang midpoint-nya di luar band Fibo 61.8%-86.6% **tidak pernah
  dibuat sama sekali**. Ini kontributor langsung ke `NO_ACTIVE_POI` (18,21%) dan
  `PRICE_NOT_IN_POI` (16,46%) di funnel — hampir 35% dari seluruh occurrence adalah
  "tidak ada zona untuk dievaluasi".
- **Sekarang (OR mode, default):** gate formation menjadi `if(m_requireOTE && !formationOTE) return false;` — ketika `InpRequireZoneOTE=false`, zona di luar OTE tetap terbentuk dan `isInOTE` disimpan sebagai nilai asli. Zona OTE tetap mendapat bonus +15 melalui `InpUseOTEFilter`; OTE juga tidak lagi memblokir QML overlap, primary gate, atau fallback.
- **Set `InpRequireZoneOTE=true`** untuk strict hard-AND pada formation, QML overlap OTE, primary gate, dan fallback.
- **Kebijakan final (v4.41):** default kode `InpRequireZoneOTE=true`. Set `false` hanya lewat preset Very High Risk atau A/B sadar. Layer 1 tetap wajib overlap OB/FVG M15 jika `InpUseLayer2M15Gate=true`. `InpUseOTEFilter` hanya bonus skor.

### 17.7 Perbaikan + kebijakan baru — King SNR HTF: `InpKingSNR_HTF` dead code, diganti dua input yang benar-benar terpakai (default kini H4/H1, lihat §23.2)
- **File:** `YANSTD.mq5` (input, `ValidateInputs()`, call site), `Modules/MSNREngine.mqh`
  (`ScanKingSNR()`, `GetKingSNRBias()`, `Init()`)
- **Temuan sebelum fix:** `InpKingSNR_HTF` (dulu `input ENUM_TIMEFRAMES ... = PERIOD_H1`)
  **tidak pernah benar-benar mengontrol apa pun**. `ScanKingSNR()` hardcode memanggil
  `ScanKingSNRTF(PERIOD_H4, ...)` lalu `ScanKingSNRTF(PERIOD_H1, ...)` tanpa syarat, dan
  `GetKingSNRBias()` hardcode membaca `kingSourceTF == PERIOD_H4` lalu fallback
  `PERIOD_H1` — keduanya mengabaikan total nilai input. `m_kingTF` di-set di `Init()` tapi
  tidak pernah dibaca di tempat lain. `ValidateInputs()` sebelumnya memvalidasi input yang
  dead ini seolah-olah berlaku (`"King SNR must use H1 or H4..."`) — validasi yang valid
  untuk parameter yang tidak berpengaruh.
- **Fix + kebijakan baru sekaligus:** diganti dua input yang genuinely wired —
  `InpKingSNR_PrimaryTF` dan `InpKingSNR_SecondaryTF`. Keduanya dipakai di
  `ScanKingSNR()` dan `GetKingSNRBias()` (prioritas primary, fallback secondary).
  `Init()` menjaga kedua TF berbeda.
- **Riwayat default:** hardcoded H4/H1 → percobaan M30/H1 (pre-4.34) →
  **factory default aktif sejak v4.34: `PERIOD_H4` primary / `PERIOD_H1` fallback**
  sesuai Rumus-Teknis Tahap 0. Logic scan tidak berubah; hanya nilai default +
  komentar member/audit yang diselaraskan.
- **Caveat (historis, 2026-09-05):** M30/H1 mengurangi bias yang self-referential
  dibanding M30/M15, tetapi dapat menaikkan `M15_DIRECTION_BIAS` reject.
  Reproduksi run lama: set input kembali ke M30/H1. Validasi pakai
  expectancy/PF/DD, bukan jumlah entry.
Seluruh file `.mq5`/`.mqh` yang tadinya campuran CRLF/LF dinormalisasi ke LF, untuk menghindari
diff noise di version control. Tidak ada perubahan fungsional.

### Tidak diubah di pass ini
- Arsitektur confluence-gate serial (King SNR × Layer2 geometric overlap × optional OTE condition × ADX × RRR × spread × time filter) tetap dipertahankan; OTE hanya menjadi hard gate saat `InpRequireZoneOTE=true`.
- `InpLimitExpirationBars` (default 30) dibiarkan di nilai lamanya; §17.1 menandai ini sebagai
  kandidat untuk direvisit sekarang beberapa slot pending konkuren sudah memungkinkan.
- Input `InpUseDynamicSpread*` sekarang memilih cap spread rolling bila gate ATR dimatikan;
  ia bukan lagi input tanpa efek.

---

## 18. Riwayat perubahan

Riwayat audit dan alasan perbaikan telah dipindahkan ke [CHANGELOG.md](CHANGELOG.md). Source hanya menyimpan komentar yang menjelaskan kontrak dan rumus aktif.

## 26. Tooling operator (v4.39)

| Item | Lokasi | Kontrak aktif |
|---|---|---|
| Riwayat audit | `CHANGELOG.md` | Bukan di badan fungsi |
| Push alert | `InpEnablePushAlerts` + `SendCriticalAlert` | Unprotected position, daily-loss / equity-DD halt, `NEWS_ERROR`. Tabel throttle maks 64 key, evict `sentAt` tertua (v4.47.5) |
| Sinkron versi | `Tools/sync_version.py`, `Tools/Sync-Version.ps1` | Baca `YANSTD_VERSION`, validasi/tulis 3 literal di `YANSTD.mq5` |
| Unit test | `Tests/RunUnitTests.mq5` | Script chart kosong; Print PASS/FAIL |
| Paket real-tick | `Presets/YANSTD_20`–`YANSTD_25` + `REAL_TICK_BACKTEST_SEQUENCE.md` | Train 2010–2018, validation 2019–2022, final holdout 2023–2026, lalu stress 500 ms |
| Cache FVG | `FVGCollectCachedFractalSwings` | Kunci `(symbol, tf, bar TF dari formationTime, lookback, wing)` |
| FOMC override | `InpFomcDatesOverride` | CSV `YYYY-MM-DD`; jika suatu tahun punya override, daftar tahun itu dianggap lengkap dan menggantikan ordinal otomatis |
| Snapshot Brain | `RotateDatedSnapshot` | `.bak` + rotasi `.snapshotN_YYYYMMDD` tiap `AI_ARCHIVE_INTERVAL_DAYS` |
| Ringkasan OnInit | `[YANSTD CONFIG]` | Mode, collection/matrix, spread cap, max positions, lot, risk, flags |
| Bahasa operator | Journal / dashboard | Inggris. Istilah rumus-teknis tetap di komentar |
| DST FOMC | `FomcStatementUTCHour` | Satu pemanggilan; tidak perlu umpan `MakeUTC(...,18,0)` |

## 27. GUI theme (v4.39 tokens, branding v4.44)

Hanya `GUI/ControlPanel.mqh`, `GUI/StatsDashboard.mqh`, dan hook UI di `YANSTD.mq5`
(`OnInit` dashboard, `OnDeinit` cleanup, `OnTimer` layer toggle, `OnChartEvent` klik).
Modul strategi **read-only**.

- Title: brand `YANSTD`, subtitle `YANSTD · MSNR + SMC` (bukan OKX).
- Prefix objek panel: `YANSTD_UI_` (OnDeinit juga hapus sisa `OKX_UI_`). Tombol eksekusi tetap `YANSTD_BTN_*`.
- Theme toggle `☀/☾`. Layer SMC toggle `◉/○` — `OnTimer` tidak memanggil
  `RenderAllSMCVisuals()` saat layer off, lalu menghapus `POI_` / `MACRO_`.
- Anti-flicker: rebuild penuh hanya jika `m_dirty`; tick 1 detik `SetText` live.

---

## 28. v4.41 — Setup grade + paket risk preset

Lot live = `InpRiskPercent × SetupGradeLotMultiplier × sessionMult`, lalu di-clamp
`InpMaxAggregateRiskPct`. D+/D tidak dikirim ke broker (jalur live). Sejak v4.42,
Data Collection/Matrix exploration mode **tidak** ikut kena reject D+/D ini — lihat
CHANGELOG 4.42 dan §29 di bawah.

Empat preset risk v4.41 adalah arsip. Paket aktif v4.46 memakai peta lengkap input sumber (saat ini **190**).
Bedanya hanya tuas risiko + seberapa longgar C-grade / OTE / counter-trend.
Peta MSNR + overlap Layer 2 + 1 posisi tetap hidup di keempatnya.

| File | Base risk | Cap agregat | Daily loss | Equity DD | OTE ketat | Limit tanpa CHoCH | Counter-trend |
|---|---|---|---|---|---|---|---|
| `YANSTD_v441_VeryHighRisk.set` | 2.50% | 8.0% | 8.0% | 40% | OFF | ON | ON (skor 60) |
| `YANSTD_v441_HighRisk.set` | 1.50% | 5.0% | 4.5% | 25% | ON | ON | ON (skor 75) |
| `YANSTD_v441_MediumRisk.set` | 1.00% | 3.0% | 3.0% | 18% | ON | OFF | ON (skor 75) |
| `YANSTD_v441_LowRisk.set` | 0.40% | 1.2% | 1.5% | 10% | ON | OFF | OFF |

Detail operator: `Presets/PRESETS.md`.
Magic number unik per preset agar histori tidak tercampur.

---

## 29. v4.42 — Audit fix: exploration mode & dead sizing code

- **`REJECT_SETUP_GRADE` scope diperjelas.** Reject grade D+/D sekarang murni
  jalur live (`!explorationMode` / `!m_brainExplorationMode`) di tiga tempat:
  `YANSTD.mq5` (`ExecuteBestLimit`) serta cabang BUY dan SELL di
  `CSignalEngine::GenerateSignal()`. Sebelum v4.42, reject ini juga menembak
  Data Collection/Matrix exploration mode meski `gradeMult` sudah tidak
  dipakai untuk sizing di mode itu — akibatnya exploration mode kehilangan
  contoh negatif (setup kelas C/D) untuk pelatihan SmartBrain. Sizing
  exploration tetap memakai `InpCollectionRiskPct` seperti biasa, tidak
  berubah.
- **`CSmartBrain::GetSizingMultiplier()` dihapus** (dead code peninggalan
  perubahan kebijakan sizing v4.41 — lihat §28 dan CHANGELOG 4.41).
  `BrainLotMultiplier(winWeight)` tetap ada, hanya dipakai untuk laporan
  diagnostik `LogEvidenceDensity()`.

Tidak ada input baru, tidak ada perubahan pada jalur live/real-money.
Detail penuh: CHANGELOG.md § 4.42.

---

## 30. v4.43 — Deep-audit fixes: symmetric trend score, ticket-safe position loop, DST edge case

- **`CMTFTrendMeter::ScoreTF()` (`Modules/MTFTrendMeter.mqh`) dibuat simetris
  di sekitar 50.** Formula lama mulai dari base 10 dan hanya PERNAH menambah
  skor untuk bukti bullish (momentum/struktur/posisi), tanpa pengurangan
  setara untuk bukti bearish — tape yang benar-benar netral/choppy bisa
  turun jauh di bawah 50 (titik yang dipakai `GetBias()`/`GetBiasLabel()`
  sebagai NEUTRAL), membuat skor konfluensi MTF bias ke SELL saat sideways.
  Tiap komponen sekarang memberi swing +/- simetris untuk kondisi
  berlawanan; endpoint (100 full bullish, 0 full bearish) tidak berubah.
  **Lakukan backtest ulang untuk frekuensi entry yang di-gate MTF** karena
  klasifikasi zona netral bergeser.
- **Position management loop di `OnTick()` (`YANSTD.mq5`) sekarang berbasis
  ticket, bukan index.** Ditambah `COrderManager::GetPositionByTicket()`
  (dibangun dari `FillPositionByTicket()` yang dipakai bersama
  `GetPosition()` lama). Loop mengambil snapshot semua ticket di awal tick,
  lalu memproses tiap ticket satu-satu — kalau ada posisi yang tertutup
  penuh di tengah loop (mis. TP1 undersized), posisi lain yang belum
  diproses di tick yang sama tidak lagi ter-skip akibat reindex cache.
- **`CSmartBrain::DynamicThresholdForBucket()` dihapus** — dikonfirmasi dead
  code, tidak dipanggil dari mana pun di codebase; fungsi ini hanya
  mengembalikan `m_minConfidence` dan menyiratkan perilaku dinamis yang
  sebetulnya tidak pernah ada.
- **`NewsFilter::FromUTC()` — DST edge case diperbaiki.** Sebelumnya verdict
  DST diturunkan langsung dari timestamp UTC yang sedang dikonversi, padahal
  `IsEuropeanSummer()`/`TesterOffsetHours()` seharusnya dievaluasi terhadap
  nilai waktu *server*. Ditambah refinement satu langkah (estimasi waktu
  server dulu, baru re-derive offset DST dari estimasi itu) untuk
  menghilangkan potensi salah beberapa jam tepat di sekitar 2 hari transisi
  DST per tahun.
- **`ZigZagEngine::ScanLoaded()` — `backstep` didokumentasikan, bukan
  diubah.** Komentar baru menjelaskan bahwa `backstep` di sini hanya dipakai
  sebagai jumlah bar konfirmasi, bukan filter jarak-minimum-antar-pivot ala
  ZigZag klasik. Ini simplifikasi yang disengaja, supaya tidak "diperbaiki"
  jadi perubahan perilaku tak sengaja oleh developer berikutnya.
- **Tidak diubah (dievaluasi, sengaja dibiarkan):** duplikasi pemanggilan
  `GenerateSignal()` antara jalur live `OnTick()` dan jalur dashboard
  `OnTimer()`. Menyatukan keduanya berarti menghubungkan keputusan eksekusi
  order live dengan pembacaan display-only — risiko: perubahan timing
  dashboard bisa memengaruhi entry live, untuk penghematan CPU marginal
  (refresh kartu sinyal dashboard 1 detik/bar M3, `mutateState=false`,
  terpisah dari throttle auto-entry). Tetap dua
  panggilan independen; revisit hanya jika profiling menunjukkan ini benar-
  benar berdampak.

Tidak ada input baru, tidak ada perubahan pada jalur live/real-money selain
fix #2 (ticket-safe loop, murni perbaikan robustness eksekusi yang sudah
ada). Detail penuh: CHANGELOG.md § 4.43.

---

## 31. v4.43 — Second-pass audit fixes: TP2 override, CPI/DST calendar, dead code

Audit lanjutan pada codebase 4.43 yang sama (lihat §30 untuk pass pertama).

**Bug fungsional (mempengaruhi perilaku trading nyata):**

- **`RegisterNewTrack()` (`OrderManager.mqh`) tidak lagi menimpa TP struktural.**
  Sebelumnya fungsi ini mengganti `tp1Level`/`tp2Level` dengan `actualOpen +
  actualRisk * RR` secara tanpa syarat di hampir setiap entry, sehingga TP2
  hasil `SignalEngine.mqh` dari zona MSNR lawan terdekat tidak pernah benar-
  benar dipakai manajemen posisi live. Sekarang fallback RR hanya berlaku
  kalau caller memang mengirim `tp1Level`/`tp2Level` `<= 0` (kasus restart-
  reconstruction di `Init()`).
- **CPI calendar off-by-one diperbaiki** (`NewsFilter::BuildSyntheticCalendar()`):
  roll Minggu→Senin sekarang `cpiDay = 14`, bukan `15`.
- **Dua implementasi DST disatukan.** `CSessionManager::IsEuropeanDST()`
  (hour-aware) sekarang public dan dipakai oleh `CNewsFilter` lewat
  `SetSessionManager()`, menggantikan implementasi day-only `NewsFilter`
  sendiri.
- **Label sesi di Signal Card (`StatsDashboard.mqh`) tidak lagi dihitung dari
  `TimeGMT()` mentah** — implementasi sesi ke-3 yang salah di backtest/visual
  mode dan tidak sinkron dengan sesi yang dipakai untuk sizing. `Render()`
  sekarang menerima `sessionLabel` dari `SessionManager::GetCurrentSession()`.

**Dead code / cabang tak terjangkau:**

- `MSNREngine::ScanQML()` — deteksi FVG confluence QML diperbaiki, sekarang
  memakai `m_smcM15.FindOverlap()` + `FVGRangeOverlapsZone()` yang sebelumnya
  sudah ada tapi tidak pernah dipanggil, menggantikan pencarian
  `MSNR_FRESH_DEMAND`/dst yang tidak pernah diisi zona manapun.
- `ClassifySetupGrade()` fallback `GRADE_D_PLUS` didokumentasikan sebagai
  unreachable-by-construction (tidak dihapus, demi keamanan defensif).
- `MSNREngine::IsKingDirectionAllowed()` dihapus — gate King SNR pra-v4.40
  yang sudah digantikan soft gate v4.40, tidak dipanggil dari mana pun.
- Subsistem "shadow trade" (counterfactual SKIP learning) di `SmartBrain.mqh`
  dihapus total — tidak pernah aktif (`shadowEnabled` selalu `false` di
  `Init()`), tidak pernah dipanggil dari `YANSTD.mq5`. **Catatan:**
  `ReplayJournal()` (tidak disentuh) tetap bisa memutar ulang record SKIP
  lama dari journal biner di disk; guard `action==1 ||
  BucketEvidence(...)<=0.0` di situ tetap wajib dipertahankan — lihat
  §15.1(e).
- `InpBrainMinRewardRisk`/`m_minRewardRisk`/`isBanned` dikonfirmasi
  diagnostik-only, tidak pernah ditegakkan di sizing manapun — tooltip dan
  komentar kode diperjelas, input dipertahankan (dipakai 4 file preset).
- `LoadV3Dataset()`/`LoadV4Dataset()` dihapus — wrapper mati di sekitar
  `RejectLegacyDataset()` yang selalu `return false`; caller sekarang
  memanggil `RejectLegacyDataset()` langsung.
- 11 getter publik tak terpakai di `SignalDiagnostics.mqh` dihapus (counter
  internalnya tetap aktif, dibaca langsung oleh `PrintSummary()`).
- Dokumentasi ini sendiri (`YANSTD_EA_SYSTEM_GUIDE.md`) dikoreksi di enam
  tempat yang ternyata masih menggambarkan mekanisme yang sudah dihapus/tidak
  pernah aktif seolah masih berlaku: §9 dan dua spot di §15.1(a) (masih
  menyebut `GetSizingMultiplier()` seolah aktif, padahal dihapus total di
  v4.42/§29); §15.1(e) (aturan shadow-SKIP masih mengacu ke
  `ProcessShadowTrades()` sebagai fungsi hidup, padahal baru dihapus di pass
  ini); §15.3 tabel lever dan §15.5 butir 7 (dua-duanya mengklaim
  `InpBrainMinRewardRisk`/`avgMFER` benar-benar men-gate/menurunkan sizing,
  bertentangan dengan temuan di atas bahwa nilai itu diagnostik-only); serta
  tabel modul (baris `SmartBrain.mqh`) dan §15.4 backlog yang masih bilang
  "shadow tidak diaktifkan" padahal sekarang dihapus total.

**Minor/cosmetic:** `RefreshHistory()`'s pemicu rebuild berbasis
`HistoryDealsTotal()` global didokumentasikan (bukan diubah) — ledger
sengaja mencatat semua deal akun (deposit/withdrawal/EA lain), jadi tidak
bisa diganti jadi dirty-flag-only tanpa membuat ledger basi. Ternary
`tp1Enabled ? "TP1" : "TP1"` dikonfirmasi konsisten dengan pola tombol
toggle lain (CUT50, HAPUS) — bukan bug.

Tidak ada input baru selain klarifikasi tooltip `InpBrainMinRewardRisk`,
tidak ada perubahan pada urutan/jumlah parameter publik kecuali
`CStatsDashboard::Render()`/`DrawSignalCard()` (tambah `sessionLabel`) dan
`CSmartBrain::Init()` (hapus parameter `shadowEnabled` yang tidak pernah
dipakai — satu-satunya call site di `YANSTD.mq5` sudah disesuaikan). Detail
penuh: CHANGELOG.md § 4.43 (Second-pass audit fixes).

---

## 32. v4.43 — Lantai lot broker 0,01 (custom symbol Dukascopy / Exness)

Entry yang sudah lolos filter **tidak boleh gagal** hanya karena risk calculator
menghasilkan lot di bawah minimum broker.

- Lantai keras: `YANSTD_HARD_MIN_LOT = 0.01`.
- `NormalizeLotToBrokerLimits()` (alias `EnforceBrokerMinLot()`) menaikkan lot positif yang `< 0,01` menjadi `0,01`
  dan memotong ke `SYMBOL_VOLUME_MAX` bila terlampaui (snap ke `SYMBOL_VOLUME_STEP`; jika step/min symbol = 0, fallback 0,01).
- Titik penegakan: `CalcLotSize()` / `RoundLotToStep()`, assignment `sig.lotSize`
  di `SignalEngine`, resize market fill + pending limit di `YANSTD.mq5`, dan
  keempat send di `OrderManager`.
- Lot di bawah minimum broker selalu di-clamp ke `0,01` (`LOT_CLAMP`).
- Metadata sizing hilang memakai fallback `0,01` (`LOT_FALLBACK`).
- Posisi 0,01 di mode struktural tidak di-split; di +80 pip hanya SL ke BE.
- `CheckMarginSafety()` tetap bisa memblokir jika margin tidak cukup.

Versi Journal aktif: `4.45-HYBRID`. Lihat §33–§34.

## 33. v4.44 — Exit struktural, SL 25–70, grade, preset rolling

Kontrak yang harus diikuti maintainer (selaras `CHANGELOG.md` § 4.44, diperbarui §34):

| Item | Perilaku |
|---|---|
| Mode exit | `EXIT_STRUCTURAL_POI` |
| Target TP | `GetStructuralTarget` = MSNR lawan M15, fallback swing M15, lalu emergency 4R |
| Step 80 pip | Tutup sampai sisa 0,01 + SL BE; runner ke target atau emergency TP |
| Tanpa target M15 | Tetap entry; step 80 + emergency 4R; tidak mengubah grade |
| SL | v4.44 historis: 25–70 pip. v4.46 aktif: ATR 0,35–2,50×; pagar pip 0 = off |
| RRR gate | Default OFF. Di `EXIT_STRUCTURAL_POI` input ini diabaikan meski di-set true |
| Sesi → lot | Tidak dipakai |
| Grade | C–S+ mengubah lot; D/D+ ditolak |
| Brain | Overlay 0,50× saja |
| Preset | `Presets/YANSTD_RT_01` … `_08` + `REAL_TICK_BACKTEST_V444.md` |
| Dashboard | Subtitle `YANSTD · MSNR + SMC`, prefix `YANSTD_UI_` |

Compile sampai Journal menulis `version=4.46-HYBRID` dan `exit=EXIT_STRUCTURAL_POI`.
Holdout v4.43 2023–2026 tidak berlaku. Holdout v4.45 adalah 2025–2026.08.

## 34. v4.45 — Holdout independen, recovery target, throttle sinyal

Kontrak maintainer yang berlaku sekarang (selaras `CHANGELOG.md` § 4.45):

- Runbook serial: `Presets/BACKTEST_RUNBOOK.md`. Protokol backtest aktif 8 tahap (`Presets/YANSTD_RT_01`–`08`, rincian `Presets/REAL_TICK_BACKTEST_V444.md`):
  `01_SMOKE_2022Q4` → `02_TRAIN_DEV_2010_2022` → `03_VALIDATE_BASELINE_2023_2024` → `04_VALIDATE_BRAIN_2023_2024` → `05_TRAIN_FINAL_2010_2024` → `06_HOLDOUT_BASELINE_2025_2026` → `07_HOLDOUT_BRAIN_2025_2026` → `08_STRESS_BRAIN_2025_2026`.
  `.set` hanya input EA. Tester manual: XAUUSD.FXSPREAD M3, every tick based on real ticks, deposit 10000, leverage 1:2000, delay 0 kecuali tahap 8 = 500 ms. Daily/equity breaker 0. Risk 1%, aggregate 3%, exit struktural. Antar tahap hanya magic + Brain/Learn/Strict yang berubah. Tidak ada file deployment terpisah.
- Recovery target setelah restart/terminal, urutan wajib: TP broker/track valid arahnya (`PERSISTED`) → opposing MSNR terbaru (`RECALCULATED_MSNR`) → swing M15 terkonfirmasi (`M15_SWING`) → emergency 4R (`EMERGENCY_RR`). Journal: `TARGET_SOURCE=...`.
- Label source pada entry market dan fill pending harus sama dengan hasil `PlanStructuralTP` saat itu. Jangan hardcode `RECALCULATED_MSNR`.
- `GenerateSignal()` jalur auto-entry: tester nonvisual sekali per bar M3; live maksimal 1 Hz; segera jika bar M3, revisi POI, atau pending berubah. Kartu sinyal dashboard boleh refresh 1 detik / bar M3 dengan `mutateState=false` dan tidak boleh memanggil `MarkGenerateSignalRan()`.
- `InpUseMinimumRRRGate` default OFF. Di `EXIT_STRUCTURAL_POI` gate ini inert (bukan penolak entry). Structural RR Mode 0 menaikkan status S→S+ / A→A+ (kualitas saja); lot tetap 2.00x — sempat naik ke 2.25x di v4.47.4–v4.47.7, dikoreksi kembali ke 2.00x di v4.47.8 (§47).
- Data gap: `UNEXPECTED_DATA_GAP` vs `NORMAL_SESSION_BREAK` vs `WEEKEND_OR_HOLIDAY` lewat `SymbolInfoSessionTrade()`.
- Setelah fill, risk awal, jarak target, partial, dan atribusi Brain dihitung ulang dari harga aktual (`RecalcTrackFromFill`).
- Audit preset menghitung input dari source (saat ini dihitung dari source), bukan angka 184/185 yang di-hardcode.
- `Tests/CheckGraphifyFreshness.ps1` menandai peta Graphify stale; panggil dari `compile_mt5.cmd`.
- Test unit: simetri geometri BUY/SELL, `ClassifyFibLevel` demand dan supply, emergency 4R, classifier data-gap.


## 35. v4.46 — Perbaikan setelah audit 8 tahap

- Filter jam: default **baru** (live / LIVE_BT / EXP mode 1–2 / input `YANSTD.mq5`) = `TIME_FILTER_ROLLOVER_HOLE` blok **20–23 UTC** (03:00–06:00 WIB). `YANSTD_RT_01`–`08` sekarang juga HOLE 20–23 UTC (sama live/EXP). Tes 01–08 yang sudah jalan dulu memakai WINDOW. Jumat cutoff 15 UTC dan block 2 jam buka Minggu tetap.
- SL: `InpUseATRStopBounds` memakai ATR min/max (0,35–2,50×) pada market dan limit. `InpMinSLPips`/`InpMaxSLPips` default **0 = off**; `SignalEngine::Init` tidak mengubah 0 menjadi 30/60. Semua `.set` aktif 0/0 + ATR on.
- `RoundLotToStep(<=0)` = `0.0`. `LastSundayOfMonth` / `IsUSDST` di `Defines.mqh` (dipakai NewsFilter + SessionManager). Parser comment bucket: `_B` lalu `SMC_B`. Komentar `OnTick`: `GAP_PAUSE` menahan entry.
- `InpAsiaSessionSizeMult` dihapus. `InpNarrowSLPolicy` / `InpWideSLPolicy` legacy tidak dibaca. Dashboard sinyal memakai `ShouldRunGenerateSignal()` tanpa `MarkGenerateSignalRan()`.
- Unexpected gap: `InpPauseBarsAfterUnexpectedGap` (default 4 bar M3) menahan entry baru. Weekend/session break tidak pause.
- Time-invalidation di kode dan `.set` v4.46: 16 bar M5 / 0.7R / 0.35 ATR.
- Brain overlay 0.50x hanya evidence >= 10 dan ExpR < -0.10.
- Event journal tester: `InpBrainEventJournalInTester` (default off; jangan nyala di train panjang).
- FINAL: varian + grade dari track + comment `SMC_T…G…` di depan. Jeda gap funnel = `GAP_PAUSE`, bukan `TIME_FILTER`.
- Journal dijaga: Friday close tidak print tiap tick; `TIME_INV` max 60 detik/tiket; `redundant_modify` tidak di-print, counter per bar M3.
- Semua `.set` aktif = **190+ input** (`InpSetupMode` ikut). `YANSTD_RT_01`–`08`: jam HOLE 20–23 UTC, mode HYBRID. Live / LIVE_BT / EXP_MODE1 / EXP_MODE2: jam HOLE 20–23 UTC. `YANSTD_EXP_HOURS_ROLLOVER.set` tetap file eksperimen hole lama (magic 8889460).
- Komentar entry memakai parameter `isMatrix`; fill pending dikenali lewat `setupFromComment`. Keduanya wajib tetap compile-safe karena dipakai untuk atribusi varian/grade/Brain.
- Gap intraday Jumat tidak otomatis dianggap weekend. `SymbolSessionOpenAt()` memeriksa sesi hari aktif serta bagian overnight dari hari sebelumnya. Pause 4 berarti empat bar M3 penuh setelah gap.
- Structural RR memakai `abs(target-entry)/abs(entry-SL aktual)` dan hanya telemetry. ATR SL wajib memenuhi `0 < min multiplier < max multiplier`.
- Recovery memilih target sekali dengan urutan §34; server TP dan partial +80 pip diturunkan dari target final yang sama.
- Rebuild dashboard/history memakai binary search untuk position identifier terurut dan fallback linear untuk history broker nonmonoton.
- `Tests/CheckGraphifyFreshness.ps1` memeriksa hash source dan fingerprint review `GRAPH_REPORT.md`. Unit test gap mencakup input invalid, intraday Jumat, weekend, dan penutupan multi-hari.

## 36. v4.46 — Minor cleanup pasca-review

Tiga temuan non-blocking, tidak mengubah perilaku runtime:

- Deinit `YANSTD.mq5`: dead call `ObjectsDeleteAll(0, "OKX_UI_")` dihapus (literal tidak pernah match — makro `OKX_UI_PREFIX` di `GUI/ControlPanel.mqh` sudah bernilai `"YANSTD_UI_"`, sisa rebranding tema lama). Cleanup objek tetap berjalan lewat baris `"YANSTD_UI_"` yang sudah ada.
- `YANSTD.mq5` sekitar baris 573: cast magic number disamakan ke pola dominan `PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber` (sebelumnya satu titik memakai `(ulong)PositionGetInteger(...) != InpMagicNumber`). Konsistensi gaya saja, tidak ada perubahan hasil.
- `Modules/OrderManager.mqh::ClosePositionWithRetry`: ditambah komentar pada pengecekan `TradeResultOK()` ganda setelah `PositionClose()` — menjelaskan bahwa ini menangani edge-case retcode OK meski `PositionClose()` return `false` (diverifikasi ulang via `PositionSelectByTicket`), bukan duplikasi yang bisa disederhanakan.

## 37. v4.47 — Structured code audit: CRITICAL + HIGH + MEDIUM + LOW fixes & Compile Verification (2026-09-11)

Audit 6-subagen paralel terhadap 19 berkas sumber. 20 temuan (3 Critical / 7 High / 3 Medium / 6 Low + pembersihan dead code) tuntas diperbaiki dan lolos kompilasi bersih (0 errors, 0 warnings). Detail per item ada di `CHANGELOG.md` v4.47.

### Perubahan konvensi/arsitektur yang perlu diikuti maintainer:

1. **Destruktor POI wajib cleanup objek chart.** `~CSignalEngine()` kini iterasi `m_poiCount` dan menghapus 4 objek per slot (`objName`, `objName+"_LBL"`, `fvgObjName`, `fvgObjName+"_LBL"`). Pola ini **wajib dipertahankan** jika menambah jenis objek chart baru di `AddPOI`.

2. **`SPositionInfo` inisialisasi wajib total.** `FillPositionByTicket` kini menjamin semua field ter-assign: `info.type = info.posType` (alias backward-compat), `info.entryType = ENTRY_TYPE_OB_15`, `info.setupGrade = GRADE_D` (default konservatif pada jalur untracked). **Jangan tambah field ke `SPositionInfo` tanpa menambahkan inisialisasi di kedua jalur** (tracked path baris ~1645 dan untracked path baris ~1718).

3. **`CheckAndExecuteTP1` kini memvalidasi remainder.** Logika: jika `pos.lots - closeLot < minLot`, lakukan full close alih-alih partial (mirror persis `CheckAndExecuteTP2` baris 133). **Konvensi: setiap partial close baru wajib memeriksa remainder vs `SYMBOL_VOLUME_MIN`.**

4. **`ApplyServerTP` kini memakai retry loop.** Sama dengan `SafeModifySL`: `m_maxRetryAttempts` + `RetryBackoff` + `IsTransientTradeRetcode`. **Konvensi: setiap method baru yang memanggil `PositionModify` atau `OrderSend` wajib memakai pola retry yang sama.**

5. **Milestone lock kini memakai broker distance check.** `CheckMilestoneLock` menghitung `brokerDist = MathMax(stopsLvl, freezeLvl) * point + spread + 2 * tickSize` dan clamp `newSL` agar tidak terlalu dekat dengan harga, persis seperti `ExecuteBEP`. **Konvensi: setiap SL modification wajib memperhitungkan broker stops/freeze level.**

6. **POI object naming memakai monotonic counter.** `m_poiObjSeq` (member `long`, init 0) menggantikan `m_poiCount` dalam `uniqueId` objek chart. `m_poiCount` berfluktuasi karena eviction; `m_poiObjSeq` hanya naik. **Jangan gunakan `m_poiCount` untuk penamaan objek.**

7. **M3 FVG decoupled dari OB_45 gate.** `displacementCreatesFVG` dihapus dari syarat wajib `OB_45` (BUY baris ~1778, SELL baris ~2113). FVG tetap ada sebagai enhancement opsional yang menghasilkan `ENTRY_TYPE_FVG_50` jika valid. **Perubahan ini meningkatkan jumlah entry OB_45 — wajib divalidasi via backtest.**

8. **`LOT_STATUS_CLAMP` kini cek `rawLot` bukan `rounded`.** `rounded` selalu `>= minLot` karena `EnforceBrokerMinLot` di dalam `RoundLotToStep`. Warning sekarang aktif saat risiko yang dihitung lebih kecil dari minimum broker.

9. **ArrayResize `reserve_size = 512`** di `UpdateStatsFromHistory` untuk 9 array paralel. Konvensi: selalu pakai `reserve_size` pada `ArrayResize` di dalam loop yang ukurannya tidak diketahui di muka.

10. **`StatsDashboard.mqh` compile fix:** redefinisi `int rx` dihapus. Variabel cukup di-reassign tanpa deklarasi ulang.

11. **`MSNREngine.mqh` early exit buffer full:** ditambahkan pemeriksaan `if(m_count >= 200) break;` pada semua loop pembentukan zona (`CommitKeyLevel`, `ScanKeyLevels`, `ScanQML`, `ScanKingSNRTF`). Menghilangkan overhead O(N) yang sia-sia saat kapasitas zona sudah penuh tanpa mengubah determinisme per-bar M15.

12. **`OrderManager.mqh` state delta check:** `UpdateTrackState()` kini membandingkan seluruh field signifikan posisi (`stateChanged`) sebelum memanggil `SaveTracks()`. Mencegah penulisan file biner ke disk secara berulang pada tick yang tidak mengalami perubahan state.

13. **`TrailingStop.mqh` swing equality relaxation:** perbandingan pivot swing low/high dilonggarkan ke `>` dan `<` (strictly greater/less). Mengakui candle kembar / double bottom / double top sebagai titik pivot terkonfirmasi untuk trailing stop runner.

14. **`NewsFilter.mqh` hour-aware DST fallback:** fallback transisi DST Eropa saat `m_session == NULL` kini memeriksa jam transisi, selaras penuh dengan `SessionManager`.

15. **`FVGValidator.mqh` default `maxBarAge`:** nilai `<= 0` kini mengembalikan default 36 bukannya dipaksa menjadi 1 bar.

16. **`YANSTD.mq5` input & parsing hygiene:** input legacy `InpNarrowSLPolicy` / `InpWideSLPolicy` dibersihkan dari deklarasi EA dan validasi parameter. Parsing komentar entry `ParseEntryComment` modular tanpa coupling `else if`.

17. **`ApplyM3StructureProtection` pivot symmetry:** perbandingan pivot dilonggarkan ke `>` dan `<` agar double bottom/top diakui sebagai struktur valid.

18. **`MSNREngine.mqh` public `GetKingSNRBias()`:** method dipindahkan ke section `public:` agar dapat diakses langsung oleh modul eksternal seperti `CSignalEngine` (`SignalEngine.mqh:1462`) tanpa compiler error hak akses.

### Status Audit:
- Seluruh temuan yang dapat diperbaiki (3 Critical, 7 High, 3 Medium, 6 Low) dan pembersihan dead code internal telah **100% selesai**.
- Public getter API di `SignalEngine` dan `MSNREngine` tetap dipertahankan untuk integritas antarmuka modul.
- **Kompilasi MetaEditor64 terverifikasi bersih:** 0 errors, 0 warnings, biner `YANSTD.ex5` (593 KB) berhasil digenerate.
- **Preset Full:** 12 file di `Presets/`: `YANSTD_HYBRID_*`, `YANSTD_SMC_SOFTMSNR_*`, `YANSTD_MSNR_SOFTSMC_*` × LIVE/BT × MEDIUM/HIGH. Input EA **195** setelah audit lanjutan (§38).

## 38. v4.47 — Audit lanjutan laporan SMC/MSNR

Diterapkan dari list H/M/L laporan audit (bukan scope “belum diaudit”). Detail baris: `CHANGELOG.md` bagian *Audit lanjutan laporan SMC/MSNR*.

| Item | Perilaku di kode |
|---|---|
| Impulse FVG = Layer-2 OB | `InpFVGImpulseBodyRatio` ke `CSMCLayerM15`. Clamp 0.50–0.95. |
| Umur OB | `InpMaxOBBarAge=0` = tanpa batas. `>0` = cap bar M15 di `AddZone` untuk OB saja. FVG tetap `InpMaxFVGBarAge`. |
| ADX | Soft default. Hard Mode 0 hanya `InpADXHardGateOnMode0`. +DI/−DI soft ±5. |
| OTE dealing range | Satu leg (`PairFormationSwingLeg`). Tanpa pasangan valid → OTE zona `false`. |
| King SNR | Sweep hanya jika level swing/equal tervalidasi. |
| OB base color | `InpOBRequireOppositeColor=false` (klasik opposite color opt-in). |
| Prior structure OB | Window 12 bar mulai `i+3` (base candle tidak ikut). |
| Fractal | `IsFractalPivot` di `Defines.mqh`. |
| OrderSend | `OpenBuy`/`OpenSell` menolak SL/TP salah sisi. |
| Skor 0.705 | `msnrScore` naik jika midpoint zona dekat 0.705 di dalam band OTE. |

Input baru (default tidak mengubah backtest lama): `InpADXHardGateOnMode0=false`, `InpMaxOBBarAge=0`, `InpOBRequireOppositeColor=false`.

## 39. v4.47.1 — Freshness/touch-count diselaraskan dengan retest manual MSNR & SMC

Dari audit eksternal terpisah (bukan bagian dari 6-subagen §37/§38 di atas). Hanya item ini yang sudah ditambal dari laporan audit tersebut — item H1/H2/H3/H4/M3/M5/L1/L2 dari laporan yang sama ditambal di §40 (v4.47.2). M1 (far OTE = 0.786) dan M2 (QML breakout close-based) ditambal di §41 (v4.47.3).

**Masalah lama:** status Freshness (`MSNR_VIRGIN` → `MSNR_SINGLE_TOUCH` → `MSNR_PARTIAL`) dan `touchCount` Layer-2 SMC (OB/FVG) dihitung dari sekadar wick candle yang overlap dengan zona (`inside && !wasInside`), tanpa peduli bagaimana candle itu close. Candle yang wick masuk lalu ditolak (close kembali keluar) dihitung sama dengan candle yang benar-benar menembus — padahal secara praktik trading manual, keduanya punya arti berbeda: yang pertama adalah retest yang valid (level "dihormati"), yang kedua adalah percobaan break (biasanya sudah berujung mitigasi lewat counter invalidasi terpisah).

**Perbaikan:** fungsi baru `IsZoneHeldTouch(isDemand, candle, zTop, zBot)` di `Defines.mqh` — touch hanya dihitung kalau `close` candle kembali di sisi yang menghormati level (`close >= zBot` untuk demand/support, `close <= zTop` untuk supply/resistance).

| Modul | Titik yang diubah |
|---|---|
| `MSNREngine.mqh` | `CommitKeyLevel` (level normal + level ter-flip SBR/RBS), `ScanQML` (QML_BUY & QML_SELL), King SNR (King Support & King Resistance) — 6 titik `touches`/`flipTouches` |
| `SMCLayerM15.mqh` | FVG Bullish, OB Demand, FVG Bearish, OB Supply — 4 titik `touches`/`obTouches` |

Logika mitigasi/invalidasi penuh (`ZoneInvalidatedByClosedBars`, consecutive-close invalidation, FVG full-fill) **tidak diubah** — perubahan ini murni pada penghitungan touch untuk status Freshness/`touchCount`, bukan pada keputusan zona hidup/mati atau flip SBR/RBS.


## 40. v4.47.2 — Audit master list (H1–H4, M3, M5, L1, L2)

Patch di atas 4.47.1. Default input baru = nilai hardcoded lama, jadi backtest lama tidak bergeser hanya karena input baru muncul.

### 40.1 Definisi swing antar-layer (H2)

Ketiga layer **tidak** memakai satu angka wing yang sama, dan itu disengaja:

| Layer | Fungsi | Wing / depth | Input |
|---|---|---|---|
| QML + King SNR validasi pivot | `MSNREngine::ScanQML`, `IsSwingHigh/LowValidated` | default **2** | `InpStructureSwingWing` |
| FVG structure overlap | `FVGValidator` native TF + H1 | default **3** | `InpFVGSwingWingLTF` |
| FVG structure overlap H4 | `FVGValidator` H4 | default **2** | `InpFVGSwingWingHTF` |
| ZigZag BOS/CHoCH | `CZigZagEngine` `halfD = max(2, depth/2)` | M15 depth 12 → 6; M5 8 → 4; M3 5 → 2 | `inp_m15_depth` / `inp_m5_depth` / `inp_m3_depth` |

ZigZag mengukur *skala struktur* per TF. QML butuh pivot lebih sensitif (shoulder kiri). FVG LTF memakai wing 3 supaya overlap struktur tidak terlalu berisik di M15. Jangan mengganti `halfD` ZigZag dengan `InpStructureSwingWing` tanpa keputusan desain terpisah.

### 40.2 Overlap vs containment di `EvaluatePrimaryGate` (L2)

`InpRequireM5ContainedInM15` **tidak** berlaku seragam ke semua jenis zona Layer-1.

Kode (`MSNREngine.mqh::EvaluatePrimaryGate`):

- Jika `m_requireM5Contained && !zone.isKeyLevel` → **containment**: kotak area (M5/POI) harus `⊆` zona MSNR (slack 1 point untuk rounding). Ini jalur QML yang lebar.
- Selain itu (key level tipis A/V/OCL/SBR/RBS, atau toggle `false`) → **overlap** + toleransi `max(tolerancePips, DynamicProximityPips())`.

Alasan: band A/V/OCL/SBR/RBS sering hanya beberapa pip. Memaksa containment membuat hampir semua OB M5 gagal gate. QML shoulder `±0.10 ATR` cukup lebar untuk menampung OB M5 di dalamnya, jadi containment masuk akal.

King SNR dilewati di loop ini (`isKingSNR continue`) — King tetap filter bias, bukan zona entry primary gate.

### 40.3 Guard eksekusi & fail-closed OTE

- `IsInOTEZone`: swing invalid (`high <= low`) = **bukan** di dalam OTE.
- `IsFractalPivot`: sayap kiri tidak boleh berakhir di bar 0.
- Entry baru ditolak (bukan di-shift) jika SL/TP < `max(StopsLevel, FreezeLevel) * point + spread`.


## 41. v4.47.3 — M1 OTE 0.786 + M2 QML close confirmation

Keputusan desain dari audit master list (maintainer pilih opsi 2 untuk keduanya). Ini aturan yang berlaku sekarang, bukan catatan sejarah saja.

### M1 — far OTE = 0.786

| Item | Nilai berlaku |
|---|---|
| Window OTE ketat | midpoint zona di **0.618–0.786** jika `InpRequireZoneOTE=true` |
| Input | `InpMSNROTEFibMin=0.618`, `InpMSNROTEFibMax=0.786` |
| Klasifikasi Fib POI | jarak terdekat ke 0.618 / 0.705 / **0.786** (`FIB_LEVEL_790` = rasio 0.786) |
| Entry deep | `ENTRY_TYPE_FIB_790` diparkir di 0.786 dari dealing range |
| Chart | label `FIB 0.786` |
| Preset | semua `.set` `InpMSNROTEFibMax=0.786` |

Jangan rename token `FIB_790` / `ENTRY_TYPE_FIB_790` / whitelist `FIB_790` tanpa migrasi komentar order + brain bucket.

File: `YANSTD.mq5`, `Modules/SignalEngine.mqh`, `Modules/MSNREngine.mqh`, `Modules/Defines.mqh`, `Presets/*.set`.

### M2 — QML breakout close-based

`MSNREngine.mqh::ScanQML` (BUY dan SELL):

1. Kumpulkan fractal pivot dengan `InpStructureSwingWing` (default 2).
2. Bentuk 4-titik tetap: BUY `LL → H → lower LL → swing high`; SELL `HH → L → higher HH → swing low`.
3. Shoulder vs ekstrem kedua tetap diuji dari **harga pivot** + `sigDist`.
4. Tembus first high/low **wajib close** pada bar `swingBars[j+2] - 1` … `swingBars[j+3]`:
   - BUY: `rates[cb].close > firstHigh + sigDist`
   - SELL: `rates[cb].close < firstLow - sigDist`
5. Zona tetap pita left shoulder `± 0.10 × ATR(M15,14)`.

Wick pivot ke-4 yang menembus tanpa ada close di sisi itu **bukan** QML sah sejak v4.47.3. Ini menyamakan standar konfirmasi QML dengan BOS/CHoCH close-based di `SignalEngine.mqh`.

Mitigasi/touch setelah formasi QML (v4.47.4): jangan loop inline mundur dari bar 1. Pakai `ZoneInvalidatedByClosedBars` + `CountHeldTouchesAfter` (arah sama, tertua → terbaru, skip `time <= confirmTime`).

## 42. v4.47.4 — Freshness Mode 2, FVG fill, guard init

Aturan yang berlaku sekarang setelah audit ronde v4.47.3. Riwayat item: `CHANGELOG.md` 4.47.4. **H-2 = opsi 1 (saat itu):** S+/A+ lot 2.25x, S/A lot 2.00x (bukan pelaporan saja). Modul eksekusi yang belum diaudit (`OrderManager.mqh`, `SmartBrain.mqh`, `NewsFilter.mqh`, `PartialClose.mqh`) tidak diubah di rilis ini.

> **Dikoreksi di §47 (v4.47.8):** angka 2.25x untuk S+/A+ di bagian ini adalah riwayat v4.47.4–v4.47.7,
> **bukan** kontrak yang berlaku sekarang. Plafon final adalah 2.00x, sama dengan S/A — lihat tabel
> source-of-truth di §15.2 dan §47.

### Grade & sizing

| Item | Aturan berlaku |
|---|---|
| Mode 2 S+ | map premium + inOTE + King OK + `VIRGIN` → lot 2.00x *(sempat 2.25x, lihat catatan di atas)* |
| Mode 2 S | map premium + inOTE + King OK + `SINGLE_TOUCH` → lot 2.00x |
| Mode 2 A+ | map key + inOTE + King OK + `VIRGIN` → lot 2.00x *(sempat 2.25x, lihat catatan di atas)* |
| Mode 2 A | map key + inOTE + King OK + `SINGLE_TOUCH` → lot 2.00x |
| Mode 2 B | ada map tapi PARTIAL / tidak inOTE / King lawan → 1.00x |
| Mode 2 C / D | tidak ada map: C jika POI inOTE (0.50x), D jika tidak (tolak) |
| Mode 0 `+` | S+/A+ dari structural RR (`healthyR` ≥ 1.50 / `usableR` ≥ 1.20) — status saja, lot tetap 2.00x *(sempat 2.25x, lihat catatan di atas)* |
| B+ / C+ | lot sama dengan B / C (B+ = jalur terdegradasi Mode 0, bukan size-up) |
| Mode 1 | tetap S/A/B/D tanpa `+`; kontrak `hasMap` ⇒ premium/key |

`EvaluateSetupGrade()` wajib meneruskan `map.freshStatus` ke `ClassifySetupGradeSMCPrimary`.

### FVG Layer-2 / validator

> **Dikoreksi di §49 (v4.47.10):** baris "Soft filter: `fillRatio >= 0.80`" di bawah ini adalah
> riwayat v4.47.4–v4.47.9, **bukan** kontrak yang berlaku sekarang. Gerbang final adalah
> `fillRatio >= 0.50` (CE) di `FVGValidator.mqh` **dan** `SMCLayerM15.mqh` — lihat §49.

- `FVGFillRatio`: 0 = belum masuk gap, 0.50 = CE, 1.0 = full fill. Bull diukur dari top gap ke bawah; bear dari bottom ke atas. Hanya closed bar setelah C3.
- Full fill (`>= 1.0`) tetap hard reject (zona tidak masuk buffer) — tapi sejak §49 tidak pernah tercapai lewat gerbang ini karena CE 50% sudah menutup lebih dulu.
- ~~Soft filter: `fillRatio >= 0.80` tidak lolos `CSMCLayerM15` dan `IsFVGValidFromRates`.~~ Digantikan `fillRatio >= 0.50` di §49.
- `SSMCM15_Zone.status`: `ZONE_FRESH` jika fill 0, `ZONE_PARTIAL` jika `0 < fill < 0.50` (zona dengan fill `>= 0.50` sekarang tidak pernah dibuat).
- `FindOverlap`: skor = `touchCount * 1000 + fillRatio * 200 + jarak pip` (FVG yang lebih termakan kalah dari yang lebih fresh) — tetap berlaku untuk kandidat yang lolos gerbang 0.50.

### Init, buffer, lot, diagnostik

- Desync `g_fvgVal.impulseBodyRatio` vs `g_msnr.GetLayer2MinDispBodyRatio()` (`> 0.0001`) → `OnInit` `INIT_PARAMETERS_INCORRECT`. Jangan lanjut trading.
- Kapasitas Layer-1 MSNR: `MSNR_MAX_ZONES` (200) di `Defines.mqh`. Jangan tulis literal `200` lagi di `MSNREngine.mqh`.
- Eviction `FindWorstZoneIndex` (SMC + MSNR): tidak ada cabang `isMitigated`. Scan membangun ulang buffer dari zona hidup saja.
- Lot: `NormalizeLotToBrokerLimits()` clamp min + max + step; `EnforceBrokerMinLot()` alias kompatibilitas.
- ADX funnel: lihat overlay `InpSetupMode` di atas. Soft penalty tidak menaikkan `REJECT_ADX_GUARD`.
- Eviction Layer-2: `FindWorstZoneIndex` = touch count → fill depth → oldest.
- ATR dinamis: `GetCachedATR` mengembalikan `0.0` bila handle/buffer gagal; caller memakai pip. Journal `⚠️ [YANSTD] ATR fallback active` sekali per bar TF sampai ATR hidup. Karakter sinyal bisa beda selama fallback.
- Lot-sizing end-to-end (`RiskCalculator.mqh`, `OrderManager.mqh`, `PartialClose.mqh`, `SmartBrain.mqh`, `ManageAutoLimitOrders` / `ResizeLotForMarketFill`) **belum** diaudit di v4.47.4 — ronde terpisah. Item lot clamp vs reject (`InpRejectBelowMinLot`) ditambah di §43 tanpa audit end-to-end penuh.

## 43. v4.47.5 — Audit listing v4.47.4 (fail-closed ADX, timer, alert, lot)

Aturan yang berlaku sekarang setelah menerapkan laporan audit `YANSTD_v4.47.4_Audit_Report.md`. Riwayat item: `CHANGELOG.md` 4.47.5.

File yang berubah di ronde ini: `YANSTD.mq5`, `Modules/Defines.mqh`, `Modules/RiskCalculator.mqh`, `Modules/FVGValidator.mqh`, `Modules/PartialClose.mqh`, `Modules/OrderManager.mqh`, `CHANGELOG.md`, `YANSTD_EA_SYSTEM_GUIDE.md`.

| Item | Aturan berlaku |
|---|---|
| Baca indikator | `ReadIndicatorValueSafe(handle, buffer, shift, ok)` — `ok=false` = gagal handle/`CopyBuffer`, bukan nilai 0.0. `ReadIndicatorValue()` tetap wrapper lama (gagal → 0.0) untuk ATR/jalur lain |
| ADX hard gate | Mode 0 + `InpADXHardGateOnMode0`: gagal baca = `REJECT_ADX_GUARD` (fail-closed). Cache bar tidak maju sampai baca sukses |
| ADX soft | Gagal baca di-log sekali per bar lewat `WarnIndicatorReadFailed`. Bukan "tren kuat" diam-diam |
| OnTimer sinyal | Setelah `GenerateSignal(..., mutateState=false)` wajib `MarkGenerateSignalRan()` |
| Push alert table | `YANSTD_ALERT_TABLE_MAX` = 64; evict slot `sentAt` tertua |
| Lot < broker min | Default clamp (`InpRejectBelowMinLot=false`). `true` → lot 0 / `LOT_STATUS_INVALID` |
| Lot helper | `NormalizeLotForRisk()` = clamp penuh; `RoundLotToStep()` alias |
| Journal event | PartialClose / ExitPlan track memakai `LogMsg`, bukan `Print` mentah |
| FVG init warn | "Uninitialized config" maksimal sekali per 60 detik |

## 44. v4.47.6 — Mode 2 SMC primary, MSNR soft overlay

Hanya `SETUP_SMC_PRIMARY`. Jangan terapkan ke Hybrid atau `SETUP_MSNR_PRIMARY`. Riwayat: `CHANGELOG.md` 4.47.6.

| Item | Aturan berlaku |
|---|---|
| Lahir POI | OB/FVG SMC tetap masuk buffer tanpa overlap MSNR |
| Bind map | `FindBestOverlappingMapZone` — overlap geometris, tanpa OTE / Layer-2. Gagal → index `-1`, POI tetap hidup |
| Bukan bind | Jangan panggil `EvaluatePrimaryGate` sebagai syarat Mode 2 (itu gerbang Hybrid) |
| Grade tanpa map | `mitigated=false`. C jika `poi.isOTE`, D jika bukan OTE |
| Grade dengan map | S+/S/A+/A/B dari `ClassifySetupGradeSMCPrimary` seperti semula |
| Limit | `EvaluateSetupGrade(..., bestPoiInOTE)` wajib |

## 45. v4.47.7 — Overlay struktur di chart

`InpShowStructureLines=true` (default). Tidak memengaruhi sinyal.

| Objek | Isi |
|---|---|
| `YANSTD_STR_M15_*` | Pivot ZigZag M15: `HH`/`LH`/`HL`/`LL` di waktu candle swing |
| `YANSTD_STR_M3_*` | Pivot ZigZag M3, label sama |
| `YANSTD_M15_STRUCTURE_EVENT` | Event makro terakhir: BOS atau CHoCH di level break |
| `YANSTD_M15_SWING_H/L` | Garis likuiditas (sudah ada) |
| `YANSTD_M15_EQ` | Equilibrium 50% |

QML/SBR/RBS tetap di `YANSTD_MAP_MSNR_*` (`InpShowMSNRMap`).

## 46. Preset v4.47.7

File di `Presets/` di-generate ulang 2026-09-12. Load lewat Tester/Inputs.

| Mode | File utama |
|---|---|
| 0 Hybrid | `YANSTD_HYBRID_{BT,LIVE}_{MEDIUM,HIGH}.set` |
| 1 MSNR + soft SMC | `YANSTD_MSNR_SOFTSMC_{BT,LIVE}_{MEDIUM,HIGH}.set` |
| 2 SMC + soft MSNR | `YANSTD_SMC_SOFTMSNR_{BT,LIVE}_{MEDIUM,HIGH}.set` |

MEDIUM: 1% / 5% daily. HIGH: 2% / 10% daily. Mode 1 `InpMinimumSoftScore=55`. Mode 2 `InpMaxEntryDistanceATR=2.50`.

## 47. v4.47.8 — Kontrak sizing grade maksimum 2.00x (koreksi H-2)

Perbaikan risiko wajib + dokumentasi tidak konsisten. Hybrid dan `SETUP_SMC_PRIMARY` paling
terdampak; `SETUP_MSNR_PRIMARY` tidak pernah menghasilkan rung `+` jadi tidak berubah. Riwayat:
`CHANGELOG.md` 4.47.8. Identitas: `YANSTD_VERSION = "4.47.8-HYBRID"`.

**Masalah.** `Modules/Defines.mqh::SetupGradeLotMultiplier()` mengembalikan 2.25x untuk
`GRADE_S_PLUS`/`GRADE_A_PLUS` — 12.5% lebih tinggi dari kontrak S/A 2.00x yang sudah dinyatakan di
§1 (ringkasan sistem). Pada base risk 2%, S+/A+ jadi 4.5% sebelum cap agregat/overlay lain. §15.2,
§34, dan §42 ikut menyebut 2.25x, sehingga dokumen ini kontradiksi dengan dirinya sendiri.

**Kontrak final (menggantikan 2.25x yang sempat berlaku v4.47.4–v4.47.7):**

| Grade | Multiplier |
|---|---|
| S+ / S / A+ / A | 2.00x |
| B+ / B | 1.00x |
| C+ / C | 0.50x |
| D+ / D | 0 (tolak) |

Tanda `+` (Mode 0: `healthyR`/`usableR`; Mode 2: `VIRGIN` vs `SINGLE_TOUCH`) hanya menyimpan
kualitas/statistik setup — tidak pernah membentuk rung lot sendiri. Tabel §15.2 adalah source of
truth tunggal; `SetupGradeLotMultiplier()` wajib sinkron dengannya untuk seluruh 10 nilai
`ENUM_SETUP_GRADE`.

| Item | Aturan berlaku |
|---|---|
| `SetupGradeLotMultiplier()` | `GRADE_S_PLUS` dan `GRADE_A_PLUS` = 2.00 (turun dari 2.25) |
| `MaxSetupGradeLotMultiplier()` (baru) | Iterasi 10 enum grade, kembalikan multiplier maksimum — dipakai log startup, bukan angka hardcode terpisah |
| Startup log | `YANSTD.mq5::OnInit()` mencetak `[YANSTD SIZING]`: base risk (`InpRiskPercent`), grade multiplier maksimum, dan risk maksimum efektif per posisi sebelum cap agregat/Brain overlay |
| Unit test | `Tests/Test_SetupGradeLotMultiplier.mq5` (script baru) memeriksa seluruh 10 enum grade terhadap tabel di atas + `SetupGradeRejects()` |
| Preset | `Presets/SET - CLAUDE SONNET 5 HIGH/README.md`: baris `InpRiskPercent` / `InpMaxAggregateRiskPct` diperbarui dari "≈2.25%" ke "2.00%" |

§1, §15.2, §34, dan §42 diselaraskan ke kontrak ini. §34 dan §42 tetap menyimpan catatan bahwa
2.25x pernah berlaku sah di v4.47.4 (keputusan maintainer saat itu) sampai dikoreksi di sini —
riwayat lengkap ada di `CHANGELOG.md` 4.47.4 dan 4.47.8. Modul eksekusi lot end-to-end
(`OrderManager.mqh`, `SmartBrain.mqh`, `NewsFilter.mqh`, `PartialClose.mqh`, `RiskCalculator.mqh`)
tidak diaudit ulang di rilis ini — perubahan terbatas ke tabel multiplier, komentar, log startup,
dan dokumentasi.

## 48. v4.47.9 — FVG wajib pada OB M5+, opsional pada M3 (H3-FVG)

Kontradiksi dokumentasi/kode + satu jalur kode yang bisa mendemosi OB M5 menjadi
`POI_PROFILE_OB_ONLY` diam-diam. `SETUP_SMC_PRIMARY` dan Hybrid paling terdampak. Riwayat:
`CHANGELOG.md` 4.47.9. Identitas: `YANSTD_VERSION = "4.47.9-HYBRID"`.

File: `Modules/SignalEngine.mqh` (rebuild M5 POI), `Modules/SMCLayerM15.mqh` (scan Layer-2),
`Modules/Defines.mqh` (`POI_PROFILE_OB_ONLY`), `YANSTD.mq5` (identitas versi), plus dokumen ini
dan `CHANGELOG.md`.

**Masalah.** Komentar di atas blok rebuild M5 (`SignalEngine.mqh`) menyatakan *"FVG is confluence;
it is not mandatory for an OB"*, padahal scanner M5/M15 memakai gerbang AND
(`bullishLeg && bullishFVG` / `bearishLeg && bearishFVG`) yang justru sudah sesuai keputusan final.
Yang salah bukan gerbang AND itu sendiri, tapi:

1. Komentar/dokumentasi yang menyebut FVG optional/confluence untuk OB M5+.
2. Satu jalur nyata di dalam gerbang AND itu sendiri: setelah lolos gerbang gap ATR
   (`bullishFVG`/`bearishFVG`), kode lama menjalankan validasi struktur yang lebih dalam
   (`IsFVGValidWithStructureFromRates`) — dan jika validasi itu **gagal**, `fvgTop/fvgBot/fvgMid`
   di-nol-kan tapi `AddPOI(...)` tetap dipanggil. Hasilnya: zona Supply/Demand M5 tetap terdaftar
   sebagai OB valid dengan `hasFVG=false`, yaitu `POI_PROFILE_OB_ONLY` — persis kontradiksi yang
   mestinya tidak boleh terjadi di M5+.
3. `SMCLayerM15.mqh` Layer-2 ternyata sudah benar: `AddZone(SMCM15_OB_DEMAND/...SUPPLY, ...)`
   memang bersarang di dalam `if(hasBullFVG)` / `if(hasBearFVG)`, jadi FVG memang sudah menjadi
   syarat untuk OB M15. Hanya belum terdokumentasi eksplisit sebagai kontrak yang tidak boleh
   diubah oleh maintainer berikutnya.
4. M3 refinement (`SignalEngine.mqh`, blok `haveValidM3OB`/`haveValidM3FVG` ~baris 1830) sudah
   benar sejak audit "FVG decoupled dari OB_45 gate" (lihat §40 riwayat) — FVG tetap opsional di
   M3, tidak diubah oleh fix ini.

**Keputusan final.**

- M5, M15, H1, H4, dan timeframe lebih tinggi: Supply/Demand + displacement **harus** diikuti FVG
  impulsif (gap ATR **dan** `IsFVGValidWithStructureFromRates`) agar diklasifikasikan sebagai OB
  berkualitas/valid. FVG bukan bonus skor di level ini — ia bagian dari validasi OB itu sendiri.
- M3: FVG tetap **tidak wajib**. OB M3 boleh dipakai sebagai refinement/trigger selama syarat
  struktur M3 lainnya (sweep + CHoCH, lihat §40/§15.5) terpenuhi — tidak berubah oleh fix ini.
- `POI_PROFILE_OB_ONLY` (`Modules/Defines.mqh`) sekarang hanya bisa tercapai lewat jalur refinement
  M3; setiap zona yang dibangun oleh rebuild M5 (`SignalEngine.mqh`) atau scan Layer-2 M15
  (`SMCLayerM15.mqh`) wajib membawa `hasFVG=true`, jadi selalu `POI_PROFILE_OB_FVG`.

**Perubahan kode.**

- **`Modules/SignalEngine.mqh`** — kedua sisi (demand & supply) di blok rebuild M5: baris yang
  dulu menjadi
  ```
  if(!obMitigatedPrior)
  {
     if(fvgMitigatedPrior || !IsFVGValidWithStructureFromRates(...))
        { fvgTop = 0; fvgBot = 0; fvgMid = 0; }
     AddPOI(ZONE_DEMAND/ZONE_SUPPLY, ...);
  }
  ```
  sekarang menjadi
  ```
  if(!obMitigatedPrior && !fvgMitigatedPrior && IsFVGValidWithStructureFromRates(...))
     AddPOI(ZONE_DEMAND/ZONE_SUPPLY, ...);
  ```
  — kandidat yang gagal validasi FVG tidak lagi didaftarkan sebagai OB (bukan lagi didemosi jadi
  OB tanpa FVG). Komentar yang menyebut "FVG is confluence; it is not mandatory" diganti dengan
  rujukan eksplisit ke keputusan H3 ini.
- **`Modules/SMCLayerM15.mqh`** — tidak ada perubahan perilaku (gerbang sudah benar); ditambahkan
  komentar di atas `Scan()` yang menandai bahwa `AddZone(SMCM15_OB_DEMAND/...SUPPLY, ...)`
  **harus** tetap bersarang di dalam `if(hasBullFVG)`/`if(hasBearFVG)` — jangan diangkat keluar
  jadi `if` sejajar di audit berikutnya.
- **`Modules/Defines.mqh`** — komentar di atas `enum ENUM_POI_PROFILE` menandai bahwa
  `POI_PROFILE_OB_ONLY` hanya sah dari jalur M3; kemunculannya dari jalur M5+ adalah bug, bukan
  varian sah.

**Dampak populasi trade.** Fix ini bisa **mengurangi** jumlah OB M5/M15 yang lolos dibanding
v4.47.8, karena kandidat yang sebelumnya lolos sebagai `POI_PROFILE_OB_ONLY` (FVG gagal validasi
struktur) sekarang ditolak sepenuhnya alih-alih didaftarkan tanpa FVG. Bandingkan populasi
trade sebelum/sesudah per mode (`SETUP_SMC_PRIMARY`, Hybrid) sebelum menambah filter pengganti —
lihat §15.1 butir 10 untuk pola perbandingan serupa dari audit sebelumnya.

**Diagnostik.** `REJECT_OB_NO_FVG` (`M3_OB_MISSING_DISPLACEMENT_FVG`, §15.5 butir 6) tetap khusus
M3 dan tidak berubah. Untuk M5+, kandidat yang gagal validasi FVG sekarang tidak menghasilkan POI
sama sekali (tidak lewat `AddPOI`), sehingga secara statistik tidak muncul sebagai
`POI_PROFILE_OB_ONLY` di `ClassifyPattern()` — setiap POI M5+ yang tercatat otomatis
`POI_PROFILE_OB_FVG`, sementara M3 tetap bisa menghasilkan keduanya (`POI_PROFILE_OB_ONLY` /
`POI_PROFILE_OB_FVG`) tergantung `haveValidM3FVG`.

Catatan §15.6 butir 7 ("Semua OB yang valid berpasangan dengan FVG, sehingga secara konsisten
terklasifikasi sebagai `POI_PROFILE_OB_FVG`") berlaku untuk M5+; ditambahkan pengecualian M3 di
sana — lihat pembaruan pada §15.6.

## 49. v4.47.10 — FVG lifecycle: satu aturan CE 50%, hapus grace 80%

Kontrak tidak konsisten: tiga modul memakai tiga aturan lifecycle FVG berbeda pada titik yang sama
(mitigasi/eligibility di CE). `SETUP_SMC_PRIMARY`, Hybrid, dan `SETUP_MSNR_PRIMARY` (lewat Layer-2
M15) semuanya terdampak. Riwayat: `CHANGELOG.md` 4.47.10. Identitas:
`YANSTD_VERSION = "4.47.10-HYBRID"`.

File: `Modules/FVGValidator.mqh` (gerbang eligibility), `Modules/SMCLayerM15.mqh` (scan Layer-2),
`Modules/SignalEngine.mqh` (komentar saja — logika M5 sudah benar), `Modules/Defines.mqh`,
`YANSTD.mq5` (identitas versi), plus dokumen ini dan `CHANGELOG.md`.

**Masalah.** `FVGFillRatio()` (`Defines.mqh`) sudah punya kontrak yang jelas: `0.0` = belum masuk
gap, `0.50` = CE (consequent encroachment), `1.0` = full fill — diukur dari closed bar setelah C3
memakai wick (`low`/`high`), bukan `close`. Tiga konsumen memakainya secara tidak konsisten:

1. **`SignalEngine.mqh`, rebuild M5 POI** (`fvgMitigatedPrior`) — benar sejak awal. Begitu closed
   bar M5 menyentuh `fvgMid` (CE 50%), FVG dianggap termitigasi dan kandidat OB+FVG itu tidak lagi
   didaftarkan lewat `AddPOI()` (lihat §48/H3 untuk kenapa gagal FVG = kandidat OB gugur total di
   M5+, bukan didemosi jadi OB tanpa FVG).
2. **`FVGValidator.mqh::IsFVGValidFromRates`** — salah. Full fill (`fillRatio >= 1.0`) memang hard
   reject, tapi ada jendela toleransi tambahan: FVG masih dianggap eligible sampai
   `fillRatio >= 0.80`. Artinya FVG yang sudah lewat CE (50%–80% consumed) masih bisa lolos sebagai
   entry POI baru lewat validator ini.
3. **`SMCLayerM15.mqh` scan Layer-2** — salah dengan cara yang sama: `AddZone(SMCM15_FVG_BULL/BEAR,
   ...)` memakai gerbang `fillRatio < 0.80`, bukan `< 0.50`.

Efeknya: pada candle/tick yang sama, `SignalEngine.mqh` M5 sudah menolak sebuah FVG (CE tersentuh),
sementara `FVGValidator.mqh` dan `SMCLayerM15.mqh` masih bisa menerimanya sebagai valid selama fill
belum mencapai 80% — tiga sumber kebenaran untuk satu keputusan yang seharusnya tunggal. Dashboard,
diagnostik, dan Brain feature encoding (`SmartBrain.mqh` bucket index) semuanya membaca `hasFVG` /
status zona yang dihasilkan modul-modul ini, jadi ketidaksepakatan itu ikut menjalar ke sana tanpa
logika tambahan di lapisan mereka sendiri.

**Keputusan final.**

1. CE 50% tetap menjadi titik entry FVG (`ENTRY_TYPE_FVG_50` / `FVG_MITIGATION_50` di
   `SignalEngine.mqh` tidak berubah).
2. Begitu harga pertama kali mencapai/melewati CE 50%, FVG berubah menjadi selesai/termitigasi dan
   **tidak boleh** menghasilkan entry FVG baru — berlaku sama di validator, Layer-2, dan M5.
3. Eligibility sampai 80% dihapus dari `FVGValidator.mqh` dan `SMCLayerM15.mqh`. Gerbang keduanya
   sekarang `fillRatio >= 0.50 → reject`, sama seperti aturan CE yang sudah dipakai M5.
4. Full fill (`fillRatio >= 1.0`) tetap boleh dicatat sebagai informasi/invalidation penuh — di
   `SMCLayerM15.mqh` variabel `fvgMitigated` dipertahankan sebagai penanda eksplisit — tapi status
   entry sudah nonaktif sejak CE 50%, bukan sejak full fill. Secara struktural cabang full-fill
   sekarang tidak pernah tercapai lewat gerbang 0.50 karena CE sudah menutup lebih dulu; ini bukan
   kode mati yang perlu dihapus, melainkan dokumentasi eksplisit bahwa full fill masih berarti
   sesuatu bagi konsumen yang membaca `fillRatio` mentah, bukan hasil gerbang gate saja.
5. Sentuhan CE diukur pakai harga yang causal dan seragam: closed-bar wick untuk historical
   rebuild, bukan `close` di satu modul dan tick intrabar di modul lain tanpa label berbeda.
   `FVGFillRatio()` sudah menegakkan ini (parameter `rates[]` closed-bar, `low`/`high`, dipanggil
   identik dari `FVGValidator.mqh` dan `SMCLayerM15.mqh`); `SignalEngine.mqh` M5 memakai pola yang
   sama (`m5Rates[k].low`/`high`, closed bar, mundur dari bar tertutup terakhir). Pemakaian
   `curAsk`/`curBid` (tick) di `SignalEngine.mqh` untuk memicu entry pada POI yang **sudah**
   terdaftar (live touch trigger) adalah lapisan yang berbeda — bukan bagian dari keputusan
   eligibility-saat-rebuild ini — dan sudah dilabeli implisit lewat nama variabel (`curAsk`/`curBid`
   vs `rates[]`), jadi tidak diubah di sini.

**Perubahan kode.**

- **`Modules/FVGValidator.mqh`** (`IsFVGValidFromRates`) — dua baris terpisah
  (`if(fillRatio >= 1.0) return false;` lalu `if(fillRatio >= 0.80) return false;`) disatukan jadi
  satu gerbang: `if(fillRatio >= 0.50) return false;`. Komentar di atasnya diganti untuk
  menjelaskan CE sebagai satu-satunya titik keputusan.
- **`Modules/SMCLayerM15.mqh`** — kedua sisi (`SMCM15_FVG_BULL` dan `SMCM15_FVG_BEAR`):
  `fillRatio < 0.80` menjadi `fillRatio < 0.50`. `fvgMitigated` (`fillRatio >= 1.0`) tidak dihapus,
  hanya jadi kondisi yang secara struktural tidak pernah lagi tercapai lewat gerbang ini (lihat
  butir 4 di atas).
- **`Modules/SignalEngine.mqh`** — tidak ada perubahan perilaku. Ditambahkan komentar di kedua sisi
  (`fvgMitigatedPrior`, demand & supply) yang menandai logika CE 50% closed-bar wick di sini
  sebagai referensi kontrak yang diikuti `FVGValidator.mqh` dan `SMCLayerM15.mqh`.
- **`Modules/Defines.mqh`** / **`YANSTD.mq5`** — `YANSTD_VERSION` naik ke `4.47.10-HYBRID`; header
  `Version` comment dan `#property copyright` diselaraskan (`#property version` tetap `"4.47"`,
  major.minor saja — lihat `Tools/sync_version.py`).

**Dampak populasi trade.** Berpotensi **mengurangi** jumlah FVG entry POI yang lolos dari
`FVGValidator.mqh` dan Layer-2 M15 dibanding v4.47.9: kandidat dengan `fillRatio` di rentang
0.50–0.80 yang sebelumnya masih lolos sekarang ditolak sejak CE. Karena `SMCM15_OB_DEMAND`/
`SMCM15_OB_SUPPLY` di `SMCLayerM15.mqh` tetap bersarang di dalam `if(hasBullFVG)`/`if(hasBearFVG)`
(kontrak §48), OB M15 yang FVG pasangannya jatuh di rentang 0.50–0.80 tadi ikut tidak terbentuk
meski gerbang OB itu sendiri tidak diubah. M5 (`SignalEngine.mqh`) tidak berubah karena sudah
memakai CE 50% sejak awal. Bandingkan populasi trade sebelum/sesudah per mode
(`SETUP_SMC_PRIMARY`, Hybrid, `SETUP_MSNR_PRIMARY`) sebelum menambah filter pengganti.

**Diagnostik.** Tidak ada reject code baru. FVG yang gagal gerbang 0.50 di `FVGValidator.mqh` atau
`SMCLayerM15.mqh` berhenti di `IsFVGValidFromRates`/`IsFVGValidWithStructureFromRates` seperti FVG
lain yang gagal validasi struktur — tercermin sebagai kandidat yang tidak pernah menjadi
`SMCM15_FVG_BULL`/`SMCM15_FVG_BEAR` atau tidak pernah membuat `hasFVG=true` pada POI, bukan lewat
reject code tersendiri. Kriteria lulus: pada candle/tick yang sama, `FVGValidator.mqh`,
`SMCLayerM15.mqh`, `SignalEngine.mqh` (M5), dashboard, diagnostik, dan Brain feature encoding
sekarang semuanya menyatakan status eligibility yang sama untuk satu FVG — CE 50% ke atas = tidak
eligible untuk entry baru — karena ketiganya membaca `hasFVG`/status zona yang dihasilkan dari
gerbang tunggal ini, bukan tiga gerbang terpisah.

## 50. v4.47.11 — ATR historis per-shift, bukan ATR "sekarang", untuk klasifikasi zona (H1)

> **Snapshot v4.47.11; proximity pada pembangunan zona di bawah disupersede oleh §53/v4.47.14.**
> `EvaluatePhase2_M5POIs()` dan `AddPOI()` sekarang menyimpan zona secara causal tanpa ATR/harga live.
> `InpMaxEntryDistanceATR` hanya diterapkan saat pemilihan/penempatan limit.

Bug causal/validitas backtest: `GetCachedATR()` (`Defines.mqh`) selalu membaca ATR candle tertutup
terbaru (shift=1). Beberapa scanner memakai satu nilai itu untuk seluruh kandidat historis di dalam
satu pemindaian, padahal tiap kandidat terbentuk pada shift yang berbeda-beda. Riwayat:
`CHANGELOG.md` 4.47.11. Identitas: `YANSTD_VERSION = "4.47.11-HYBRID"`.

File: `Modules/Defines.mqh` (`ReadATRAtShift()` baru), `Modules/FVGValidator.mqh`
(`IsFVGValidFromRates`), `Modules/SMCLayerM15.mqh` (`Scan()`), `Modules/MSNREngine.mqh`
(`ScanKeyLevels`, `ScanQML`, `ScanKingSNRTF`), `Modules/SignalEngine.mqh`
(`EvaluatePhase2_M5POIs`), plus dokumen ini dan `CHANGELOG.md`.

**Masalah.** Semua fungsi di atas memindai riwayat closed-bar dengan sebuah loop `for(int i = ...)`
di mana `i`/`shift` menunjuk ke candle formasi kandidat yang berbeda-beda (lama ke baru). Sebelum
perbaikan ini, ATR yang dipakai untuk menghitung ambang lebar FVG/OB/SNR (`minFVGWidth`, `minGap`,
`kingBuffer`, `minZoneWidth`, `sigDist`, `qmlTol`, dst.) dibaca **sekali** lewat `GetCachedATR()` di
luar loop, artinya candle volatilitas *hari ini* dipakai untuk menilai kandidat yang terbentuk
berminggu-minggu lalu. Akibatnya:

- Rekonstruksi historis tidak stabil — menjalankan ulang scan yang sama pada waktu berbeda (dengan
  ATR "sekarang" yang sudah berubah) bisa menghasilkan set zona lama yang berbeda meski candle
  pembentuknya identik dan tidak berubah.
- Isi POI (FVG/OB M15, key level, QML, King SNR, M5 POI) bisa berubah tanpa ada bar baru yang
  relevan terbentuk.
- Backtest tidak sepenuhnya causal: keputusan tentang bar `t` bisa dipengaruhi oleh data yang baru
  tersedia setelah `t`.
- Perbandingan mode/periode berpotensi bias karena dua rerun pada rentang historis yang sama tidak
  dijamin memberi populasi zona yang sama.

**Keputusan final.**

1. `Modules/Defines.mqh` mendapat `ReadATRAtShift(symbol, tf, period, shift)` baru: fungsi ini
   men-cache satu buffer ATR kontinu per `(symbol, tf, period)` sehingga sebuah scan yang menyentuh
   banyak kandidat tetap hanya memicu satu `CopyBuffer()` per rentang yang dibutuhkan, bukan satu
   panggilan per kandidat. Cache hanya tumbuh (tidak pernah dipotong) dalam satu bar dan disegarkan
   ulang saat bar baru terbentuk.
2. Setiap scanner sekarang membaca ATR pada shift candle pembentukan/displacement zona yang
   bersangkutan (didefinisikan oleh rumus masing-masing jenis zona), bukan `GetCachedATR()`
   (shift=1/"sekarang"), untuk keputusan **validitas formasi**:
   - `FVGValidator.mqh::IsFVGValidFromRates` — ATR di `shift+1` (candle displacement C2).
   - `SMCLayerM15.mqh::Scan()` — `minFVGWidth` dan ambang lebar OB dihitung ulang per kandidat `i`
     dari ATR di `i+1` (displacement) / kandidat base `i+2`, di dalam loop, bukan sekali di atasnya.
   - `MSNREngine.mqh::ScanKeyLevels` — ATR per kandidat pada shift `i` (candle c2).
   - `MSNREngine.mqh::ScanQML` — `sigDist`/`qmlTol` per kombinasi swing dari ATR pada shift bahu
     kiri (`swingBars[j]`).
   - `MSNREngine.mqh::ScanKingSNRTF` — `kingBuffer`/`minZoneWidth` per kandidat pada shift `i`
     (candle c2, King SNR).
   - `SignalEngine.mqh::EvaluatePhase2_M5POIs` — `minGap` dan ambang lebar OB M5 (`1.5*ATR`) per
     kandidat `i` dari ATR di `i+1` (displacement).
3. ATR "sekarang" (`GetCachedATR()`, shift=1) **tetap** dipakai untuk semua yang memang menilai
   kondisi saat ini, bukan validitas formasi historis: proximity harga-sekarang-ke-zona di
   `EvaluatePhase2_M5POIs`/`AddPOI` (`pxNow`/`SYMBOL_BID`), `DynamicProximityPips()` (toleransi
   sentuh/mitigasi live di `MSNREngine.mqh`), `TrailingStop.mqh`, `SpreadMonitor`-adjacent bound di
   `ComputeStopBoundPips`/`GetDynamicSLBuffer` (`SignalEngine.mqh`), dan `SmartBrain.mqh`. Tidak ada
   perubahan pada jalur-jalur ini.
4. Nilai ATR historis per shift **deterministik**: karena candle tertutup tidak pernah berubah,
   `ReadATRAtShift(symbol, tf, period, shift)` mengembalikan angka yang sama setiap kali dipanggil
   untuk shift yang sama, tanpa perlu menyimpan `formationATR` terpisah di dalam struct zona —
   cache di `Defines.mqh` sudah menjamin hasil identik pada rerun mana pun selama history candle
   tidak berubah, tanpa menambah field baru ke `SMSNRZone`/`SSMCM15_Zone`/POI array yang dipakai
   lintas modul (GUI, diagnostics, Brain) dan berisiko pecah kompatibilitas.

**Perubahan kode.**

- **`Modules/Defines.mqh`** — `ReadATRAtShift()` baru (struct cache `SATRShiftCache` +
  `g_atrShiftCache[]`), dipanggil `ReleaseCachedATRHandles()` juga membersihkannya di `OnDeinit`.
  `GetCachedATR()` tidak diubah — tetap dipakai apa adanya oleh semua konsumen live/eksekusi.
- **`Modules/FVGValidator.mqh`** — `GetCachedATR(symbol, tf, ...)` diganti
  `ReadATRAtShift(symbol, tf, ..., shift + 1)`.
- **`Modules/SMCLayerM15.mqh`** — `atrM15`/`minFVGWidth` dipindah dari sekali-di-atas-loop menjadi
  `atrFormation`/`minFVGWidth` dihitung ulang per kandidat `i` di dalam loop; kedua ambang lebar OB
  (`0.05*atrM15` → `0.05*atrFormation`) ikut disesuaikan.
- **`Modules/MSNREngine.mqh`** — `ScanKeyLevels`: `atr`/`band`/`invBuf`/`minBody`/`minGap` dipindah
  ke dalam loop per `i`. `ScanQML`: `atrQ`/`sigDist`/`qmlTol` dipindah ke dalam loop per `j`, dari
  shift `swingBars[j]`. `ScanKingSNRTF`: `atrKing`/`kingBuffer`/`minZoneWidth` dipindah ke dalam
  loop per `i`. `DynamicProximityPips()` (live) tidak diubah.
- **`Modules/SignalEngine.mqh`** — `EvaluatePhase2_M5POIs`: ATR "sekarang" dipecah jadi dua
  variabel — `atrM5Live` (dari `GetCachedATR()`, dipakai murni untuk filter proximity harga-sekarang
  `pxNow`) dan `atrM5` per kandidat (dari `ReadATRAtShift(..., i + 1)`, dipakai untuk `minGap` dan
  ambang lebar OB `1.5*ATR`). `AddPOI()` (proximity harga-sekarang saat commit) tidak diubah.
- **`Modules/Defines.mqh`** / **`YANSTD.mq5`** — `YANSTD_VERSION` naik ke `4.47.11-HYBRID`; header
  `Version` comment dan `#property copyright` diselaraskan (`#property version` tetap `"4.47"`,
  major.minor saja — lihat `Tools/sync_version.py`).

**Dampak populasi trade.** Kandidat FVG/OB/key-level/QML/King SNR historis yang ambang lebarnya
sebelumnya lolos/gugur karena ATR "sekarang" kebetulan lebih longgar/ketat dari ATR saat formasi
kini dinilai konsisten terhadap ATR pembentukannya sendiri. Pada periode volatilitas yang stabil
dari awal sampai akhir backtest, dampak populasi trade minimal. Pada periode dengan lonjakan
volatilitas (mis. rilis berita besar di tengah rentang test), populasi zona historis di sekitar dan
setelah lonjakan tersebut dapat berbeda dari v4.47.10 karena sekarang dinilai terhadap ATR saat
masing-masing candle terbentuk, bukan ATR akhir rentang. Bandingkan populasi trade sebelum/sesudah
pada rentang dengan volatilitas tidak stabil sebelum menambah filter pengganti.

**Diagnostik.** Tidak ada reject code baru. Kandidat yang gagal ambang ATR per-shift berhenti di
tempat yang sama seperti sebelumnya (`IsFVGValidFromRates`, `Scan()`, `ScanKeyLevels`, `ScanQML`,
`ScanKingSNRTF`, `EvaluatePhase2_M5POIs`) — hanya nilai ATR yang dipakai untuk ambang itu yang
berubah. Kriteria lulus: menjalankan ulang scan pada history yang sama beberapa bar kemudian
memberi hasil validitas identik untuk kandidat lama; mengubah volatilitas setelah formasi tidak
mengubah status pembentukan zona lama; test yang membandingkan dua rangkaian candle dengan riwayat
formasi identik tapi volatilitas masa depan berbeda menghasilkan status formasi yang sama.

## 51. v4.47.12 — Target STAGED/FIXED_RR tidak pulih dengan benar setelah restart (H4)

Bug proteksi/manajemen posisi. Mode exit terdampak: `STAGED` dan `FIXED_RR` (`STRUCTURAL` tidak
berubah). Riwayat: `CHANGELOG.md` 4.47.12. Identitas: `YANSTD_VERSION = "4.47.12-HYBRID"`.

File: `Modules/OrderManager.mqh` (`RegisterNewTrack()`), `YANSTD.mq5`
(`RecoverOpenPositionTargets()`).

**Kenapa STAGED/FIXED_RR rapuh terhadap restart tapi STRUCTURAL tidak.** `STRUCTURAL` selalu
memasang TP di broker (`ApplyServerTP()`), jadi `POSITION_TP` bertahan lintas restart terlepas dari
state track lokal. `STAGED` dan `FIXED_RR` tidak pernah memasang TP broker — lihat pemanggilan
`RegisterNewTrack()` di jalur fill (`YANSTD.mq5`, sekitar deal `DEAL_ENTRY_IN`): `serverTPFill`
hanya diisi untuk `IsStructuralExitMode()`. Kedua mode ini murni mengandalkan `SPosTrack.tp1Level`/
`tp2Level` yang dicek tiap tick oleh `CPartialClose` (`IsTP1Hit`/`IsTP2Hit`). Kalau field itu 0.0,
tidak ada apa pun yang menutup posisi berdasarkan target — posisi jadi liar sampai ditutup manual
atau oleh trailing stop.

**Bug 1 — gerbang terbalik di `RegisterNewTrack()`.** Fallback price-level
(`open ± actualRisk × m_defaultTP1RR/TP2RR`) sudah dilindungi per-field
(`if(tp1Level <= 0.0) ...`) supaya tidak menimpa target valid yang sudah dihitung caller (mis. TP2
zona berlawanan MSNR dari `SignalEngine`). Tapi guard tambahan `&& !reconstructed` membuat fallback
itu justru berhenti persis saat `reconstructed == true` — yaitu satu-satunya jalur yang memang
membutuhkannya: rekonstruksi posisi terbuka di `COrderManager::Init()` ketika track file lama
diabaikan (mis. setelah upgrade format). Fix: hapus `&& !reconstructed`; guard per-field yang sudah
ada cukup untuk melindungi target valid, terlepas dari asal panggilan.

**Bug 2 — `RecoverOpenPositionTargets()` tidak menangani mode non-struktural sama sekali.**
Fungsi lama langsung `return` kalau `InpExitMode != EXIT_STRUCTURAL_POI`. Dipecah jadi dispatcher +
tiga fungsi per mode (dipanggil sekali di `OnInit()`, setelah `g_orders.Init()` — sama seperti
sebelumnya):

- `RecoverStructuralTargets()` — logika lama dipindah apa adanya: persisted TP → opposing MSNR →
  M15 swing → emergency RR, lewat `ApplyServerTP()` + `UpdateTrackTarget()`.
- `RecoverFixedRRTargets()` — validitas dicek pada `tp2Level` (field yang dipakai `IsTP2Hit()` untuk
  full close; `tp1Level` tidak relevan karena `g_tp1Enabled` selalu `false` di `FIXED_RR`). Kalau
  tidak valid, satu target dihitung ulang dari `open ± initialRiskPrice × InpFixedRR` dan ditulis ke
  `tp1Level`+`tp2Level` (disamakan) lewat `UpdateTrackState()`.
- `RecoverStagedTargets()` — `tp1Level` dan `tp2Level` dicek dan dihitung ulang **independen**, dari
  `open ± initialRiskPrice × InpTP1RR`/`InpTP2RR`, hanya untuk sisi yang tidak valid.

`initialRiskPrice` diambil dari track (`SPositionInfo.initialRiskPrice`, yang untuk track yang
sudah ada sejak sebelum restart bernilai benar); kalau nol, di-fallback ke jarak SL server saat itu
(`SPositionInfo.sl`, sudah diisi `FillPositionByTicket()`) — sama seperti pola fallback initial-risk
yang sudah dipakai di jalur "untracked/orphan position" di `OrderManager.mqh`.

Persentase/volume close (`tp1CloseLots`/`tp2CloseLots`/`runnerLots`, dari
`m_defaultTP1ClosePct`/`TP2ClosePct` lewat `BuildScaleOutPlan()`) **tidak** ikut rusak oleh bug ini
— nilai itu sudah benar sejak `RegisterNewTrack()` dipanggil di jalur restart-reconstruction
`COrderManager::Init()`, karena parameter itu diteruskan langsung, tidak melalui gerbang
`!reconstructed` yang salah. Jadi §51 hanya memperbaiki harga target (`tp1Level`/`tp2Level`), bukan
ukuran partial.

**Tidak menimpa target valid.** Ketiga fungsi recovery hanya menghitung ulang saat
`TargetPriceValid()` gagal (target `<= 0.0` atau arahnya salah relatif entry) — target yang sudah
valid, baik dari broker (`STRUCTURAL`) maupun dari track lokal (`STAGED`/`FIXED_RR`), tidak pernah
ditimpa.

**Kriteria lulus.** Test restart BUY dan SELL pada ketiga mode exit. TP server yang valid sebelum
restart tidak berubah tanpa alasan. Track setelah restart punya `initialRiskPrice`, target
(`tp1Level`/`tp2Level`, atau `serverTP` untuk `STRUCTURAL`), atribusi (`entryVariant`/`setupGrade`),
dan partial state (`tp1Done`/`tp2Done`/`scaleOutEnabled`) yang benar.

---

## 52. v4.47.13 — Parser pending order disatukan ke ParseEntryComment() (M2)

Bug parser/deduplikasi. Mode setup terdampak: ketiganya. Riwayat: `CHANGELOG.md` 4.47.13.
Identitas: `YANSTD_VERSION = "4.47.13-HYBRID"`.

File: `YANSTD.mq5` (`ReconcilePOIPendingFlags()`, `HasEquivalentPendingOrder()`,
`ParseEntryComment()`).

**Satu penulis, dulu tiga pembaca.** `FormatEntryComment()` adalah satu-satunya fungsi yang menulis
komentar order, dengan format tetap: `SMC_T<variant>G<grade>_B<bucket36>_E<event36>`, ditambah
sufiks `_M` untuk order matrix/eksplorasi (lihat §6 untuk skema comment order secara umum).
Sebelum perbaikan ini, tiga fungsi berbeda membaca format itu dengan cara yang berbeda-beda:
`ParseEntryComment()` sendiri (jalur "resmi", dipakai `OnTradeTransaction` untuk atribusi deal), plus
`ReconcilePOIPendingFlags()` dan `HasEquivalentPendingOrder()` yang masing-masing punya pencarian
literal `"_T"` sendiri. `ParseEntryComment()` juga masih menyimpan cabang fallback untuk format lama
(`"_T"`/`"_G"` tanpa prefiks `SMC_`, dan `"SMC_B"` terpisah dari `"_B"`) yang tidak lagi ditulis oleh
`FormatEntryComment()` mana pun.

**Kenapa ini berbahaya meski tampak "biasanya jalan".** Selama komentar berformat aktif dan tidak
ada perubahan lanjutan, kebetulan substring `"_T"` di dalam `"SMC_T"` bisa saja masih memberi hasil
yang tampak benar. Tapi tiga jalur baca yang independen untuk satu format berarti kalau
`FormatEntryComment()` berubah lagi (mis. prefiks baru, delimiter baru), hanya `ParseEntryComment()`
yang perlu disentuh secara desain — tapi dua pembaca lain yang tidak memakainya akan diam-diam
berbeda perilaku tanpa ada yang mendeteksi saat kompilasi. Kelas bug ini (parser paralel untuk satu
format) adalah yang paling mahal untuk diauditulang, karena "benar secara kebetulan" tidak sama
dengan "benar by construction".

**Solusi — satu jalur baca, pakai di semua tempat.**

1. `ParseEntryComment()` disederhanakan: hanya mengenali `SMC_T<variant>G<grade>_B<bucket36>
   _E<event36>`. Fallback parser format lama dihapus sepenuhnya, bukan dipertahankan berdampingan
   dengan jalur baru (menjaga dua parser untuk satu format hanya memindahkan risiko divergensi ke
   dalam satu fungsi, bukan menghilangkannya). Kalau komentar tidak diawali `SMC_T` — order manual,
   sisa order dari versi lama, atau string yang korup — semua output dikembalikan ke sentinel
   "tidak diketahui" (`bucket=-1, variant=-1, grade=-1, eventId=0`) dan satu warning ter-throttle
   per menit dicatat lewat `LogThrottled("PARSE_ENTRY_COMMENT", 60, ...)` (pola throttle yang sama
   dipakai `PassEntryMarketQuality()`/`ManageAutoLimitOrders()`, lihat §13) — supaya jurnal tidak
   dibanjiri saat banyak order lama diproses sekaligus, tapi kegagalan parse tetap terlihat, bukan
   diam-diam ditelan.
2. `ReconcilePOIPendingFlags()` dan `HasEquivalentPendingOrder()` tidak lagi mem-parsing komentar
   sendiri. Keduanya memanggil `ParseEntryComment()` dan memakai hasilnya persis seperti variabel
   lokal yang tadinya diisi manual — logika pencocokan sesudahnya (event ID exact match → layer by
   variant+price → price-only last resort di `ReconcilePOIPendingFlags()`; variant-gate + toleransi
   harga di `HasEquivalentPendingOrder()`) tidak berubah.

**Efek ke deduplikasi pending order.** Sebelumnya, kalau variant gagal terbaca (`-1`) karena jalur
parser yang berbeda-beda, kedua fungsi ini jatuh ke pencocokan price-only — dua variant berbeda
(mis. OB15 vs FVG50) pada harga yang sama bisa dianggap ekuivalen: `HasEquivalentPendingOrder()`
akan melaporkan "sudah ada" padahal setup-nya berbeda, atau `ReconcilePOIPendingFlags()` mencocokkan
pending ke POI yang salah. Dengan satu parser yang konsisten, `variant` (dan `eventId`) terbaca
benar dari komentar berformat valid, sehingga dua variant pada harga berbeda — atau bahkan pada
harga yang sama — tidak lagi saling memblokir atau saling menimpa status pending secara keliru.

**Kriteria lulus.**

- Round-trip `FormatEntryComment()` → `ParseEntryComment()` mengembalikan `bucket`/`variant`/
  `grade`/`eventId` yang identik dengan nilai yang di-encode — termasuk `bucket` negatif (lihat
  `EncodeBase36Signed()`/`DecodeBase36Signed()`) dan komentar bersufiks `_M`.
- `ReconcilePOIPendingFlags()` menemukan `variant`, `grade`, `bucket`, dan event ID yang benar dari
  komentar order pending yang aktif, bukan jatuh ke `-1`/price-only untuk komentar berformat valid.
- Dua variant pada harga berbeda (dan pada harga yang sama) tidak saling memblokir atau saling
  menimpa status pending secara salah di `HasEquivalentPendingOrder()`/
  `ReconcilePOIPendingFlags()`.

---

## 53. v4.47.14 — Validitas zona SMC Primary dipisah dari jarak ke harga sekarang (M6)

Bug desain state/scan. Mode setup terdampak: SMC Primary. Riwayat: `CHANGELOG.md` 4.47.14.
Identitas: `YANSTD_VERSION = "4.47.14-HYBRID"`.

File: `Modules/SignalEngine.mqh` (`EvaluatePhase2_M5POIs()`, `AddPOI()`).

**Dua gerbang jarak-ke-harga yang keliru tempat.** Sebelum perbaikan ini, mode `SETUP_SMC_PRIMARY`
punya dua tempat yang menolak sebuah kandidat/zona kalau midpoint-nya lebih jauh dari
`2.5 × ATR(M5)` terbaru terhadap harga saat ini:

- Di loop scan `EvaluatePhase2_M5POIs()`, sebuah `continue` melewatkan kandidat sepenuhnya —
  sebelum satu pun cek struktural (displacement, FVG, lebar OB, mitigasi prior) dijalankan.
- Di dalam `AddPOI()`, sebuah `return` menolak zona yang **sudah lolos** semua cek struktural itu,
  tepat sebelum baris yang menyimpannya ke `m_poiStore`.

Keduanya memakai konstanta `2.5` yang di-hardcode, terpisah dari `InpMaxEntryDistanceATR` (default
`1.50`, lihat tabel parameter) yang memang dirancang sebagai gerbang jarak-ke-harga — tapi
`InpMaxEntryDistanceATR` sudah benar diterapkan di tempat lain: `YANSTD.mq5::ManageAutoLimitOrders()`,
tepat saat memilih harga limit untuk ditempatkan (`curAsk - limitP` / `limitP - curBid`, lihat
REJECT_ENTRY_TOO_FAR di `Defines.mqh`). Dua gerbang di `SignalEngine.mqh` ini adalah filter kedua
yang tidak terkoordinasi, dan diterapkan di tempat yang salah: saat *membangun* daftar zona, bukan
saat *memilih* entry darinya.

**Kenapa ini membuat POI berkedip.** `m_poiStore` bersifat persisten lintas panggilan
`EvaluatePhase2_M5POIs()` — `m_poiCount` hanya di-reset di konstruktor, dan `CompactExpiredPOIs()`
membuang zona berdasarkan umur bar, bukan jarak ke harga. Karena harga bergerak di antara satu
rebuild dan rebuild berikutnya, kandidat yang gagal salah satu gerbang jarak itu tidak pernah sampai
tersimpan pada rebuild tersebut — padahal formasinya (displacement/FVG/OB) tidak berubah sama
sekali. Begitu harga mendekat lagi, kandidat yang sama akhirnya lolos dan tersimpan. Kalau harga
tidak sempat mendekat sebelum kandidat itu keluar dari jendela scan (`m_zoneMaxBars`/
`candidateLimit`, lihat `EvaluatePhase2_M5POIs()`), zona itu tidak pernah tersimpan sama sekali —
sebuah POI yang struktural valid bisa lenyap permanen semata karena kebetulan jarak harga saat
jendela scan-nya masih terbuka.

**Solusi — pisahkan "apakah zona ada" dari "apakah entry masih layak dari sini".**

1. `EvaluatePhase2_M5POIs()` — blok pengecekan jarak (`if(m_setupMode == SETUP_SMC_PRIMARY &&
   atrM5Live > 0.0 && pxNow > 0.0) { ... continue }`) dihapus dari loop scan, beserta variabel
   `atrM5Live`/`pxNow` yang cuma dipakai di situ. Setiap kandidat sekarang selalu dievaluasi murni
   dari rate formasinya sendiri, tanpa melihat harga sekarang.
2. `AddPOI()` — blok `if(m_setupMode == SETUP_SMC_PRIMARY) { ... return; }` (gerbang
   `MathAbs(px - mid) > 2.5 * atr`) dihapus. Zona yang lolos filter lebar (`widthPips`) dan gerbang
   MSNR/dedup di bawahnya sekarang selalu tersimpan — penyimpanan sepenuhnya causal (ditentukan oleh
   riwayat rate yang membentuknya), tidak lagi bergantung posisi harga saat panggilan terjadi.
3. `InpMaxEntryDistanceATR` tidak disentuh dan tetap satu-satunya gerbang jarak-ke-harga yang aktif
   di sistem, diterapkan hanya di jalur penempatan limit order (`ManageAutoLimitOrders()`) — persis
   seperti sebelum perbaikan ini.

**Prinsip pemisahan yang dipertahankan ke depan.** Optimasi scan boleh menghentikan evaluasi atau
rendering yang mahal (mis. melewati kandidat yang jelas tidak akan lolos filter lebar/umur), tapi
tidak boleh mengubah status validitas permanen sebuah zona berdasarkan kondisi harga sesaat.
Kalau di masa depan diperlukan optimasi CPU tambahan pada `EvaluatePhase2_M5POIs()`, syaratnya:
hasil akhir *penyimpanan* zona untuk kandidat yang sama harus identik terlepas dari harga saat
optimasi itu dievaluasi — kalau tidak, itu adalah filter validitas yang menyamar sebagai optimasi,
persis bug yang diperbaiki §53 ini.

**Cakupan yang tidak berubah.** Kriteria struktural (lebar OB, mandatory FVG H3-FVG §48, aturan
mitigasi 2-close, CE 50% §49, ATR formasi per-kandidat §50) tidak disentuh. Gerbang
`InpMaxEntryDistanceATR` di jalur penempatan entry — nilai default, mode di mana ia aktif, dan cara
kerjanya menolak limit yang terlalu jauh — tidak berubah.

**Kriteria lulus.**

- Zona SMC Primary yang lolos semua cek struktural tersimpan di `m_poiStore` terlepas dari seberapa
  jauh midpoint-nya dari harga saat rebuild terjadi.
- Rebuild ulang pada riwayat rate yang sama dengan harga simulasi berbeda-beda tidak mengubah hasil
  penyimpanan zona (POI tidak hilang/muncul hanya karena harga berbeda antar rebuild).
- Penolakan penempatan limit order yang terlalu jauh dari harga tetap terjadi seperti sebelumnya,
  hanya lewat `InpMaxEntryDistanceATR` di jalur penempatan entry, bukan di jalur pembangunan zona.

---

## 54. v4.47.15 — Rebuild statistik history dari O(N²) jadi incremental per-deal (M4)

Bottleneck, terutama pada backtest panjang. Riwayat: `CHANGELOG.md` 4.47.15. Identitas:
`YANSTD_VERSION = "4.47.15-HYBRID"`.

File: `YANSTD.mq5` (`UpdateStatsFromHistory()`, `OnTradeTransaction()`, dan fungsi-fungsi baru
`ApplyStatsDeal()`, `TryFinalizeStatsPosition()`, `FindOrCreateStatsPos()`,
`RollDailySessionWindows()`, `AddTodayCompletedTrade()`, `ResetStatsHistoryState()`,
`RebuildStatsHistoryFull()`, `OnStatsDealArrived()`).

**Masalah.** `UpdateStatsFromHistory()` punya guard `g_statsHistoryDirty` (H9, lihat §-nya sendiri)
yang mencegah pemanggilan berulang dari OnTimer/OnNewHTFBar/tester-visual-sync memicu kerja berat
kalau tidak ada deal baru. Tapi guard itu hanya menunda kapan kerja berat dijalankan — begitu ada
satu deal baru (entry atau exit) untuk EA ini, `OnTradeTransaction()` men-set dirty flag lalu
langsung memanggil `UpdateStatsFromHistory()`, yang menjalankan `HistorySelect(0, now)` diikuti loop
penuh atas **seluruh** `HistoryDealsTotal()` untuk membangun ulang agregat per-posisi dari nol. Pada
backtest dengan N deal, ini terjadi kira-kira sekali per deal, sehingga total kerja sepanjang test
adalah 1+2+3+...+N ≈ O(N²). Tester yang menghasilkan ribuan deal jadi terasa melambat drastis
mendekati akhir riwayat panjang, persis gejala yang dilaporkan di M4.

**Solusi — pisahkan hot path dari fallback penuh.**

1. **State per-posisi jadi persisten**, bukan array lokal yang dibangun ulang tiap panggilan:
   `g_statsPosIds[]`, `g_statsPosProfit[]`, `g_statsPosCloseTime[]`, `g_statsPosHasExit[]`,
   `g_statsPosCounted[]`, `g_statsPosType[]`, dan pasangan `*PxVolSum[]`/`*Vol[]` untuk rata-rata
   harga entry/exit berbobot volume (dipakai untuk pip TP1/TP2/runner). Semuanya hidup selama
   EA/test berjalan dan tumbuh dengan `ArrayResize(..., n, 512)` (pre-alokasi chunk, konsisten
   dengan pola AUDIT FIX yang sudah ada di kode lama).
2. **`ApplyStatsDeal(ticket, startOfDayUTC, currentSess)`** — satu fungsi yang menerapkan efek SATU
   deal ke state persisten di atas (akumulasi profit harian, cari/buat slot posisi via
   `FindOrCreateStatsPos()`, update entry/exit volume-weighted sum, update cursor
   `g_statsLastDealTime`/`g_statsLastDealTicket`), lalu memanggil `TryFinalizeStatsPosition()`.
   Dipakai oleh KEDUA jalur (hot path dan fallback penuh) supaya keduanya tidak pernah punya logika
   yang berbeda.
3. **`TryFinalizeStatsPosition(idx, ...)`** — begitu deal exit terakhir sebuah posisi mendarat (tidak
   ada lagi ticket terbuka dengan `POSITION_IDENTIFIER` yang sama), posisi itu dilipat SEKALI ke
   `g_stats.totalTrades/totalWins/totalProfit/totalPips`, dan kalau trade itu ditutup hari ini, juga
   ke `g_stats.dailyPips` dan (kalau sesi cocok) `sessionWins/sessionLosses`. Flag
   `g_statsPosCounted[idx]` mencegah posisi yang sama terhitung dua kali.
4. **`OnStatsDealArrived(dealTicket)`** — hot path baru yang dipanggil `OnTradeTransaction()` untuk
   setiap deal `DEAL_ENTRY_*` milik EA ini (magic+symbol sudah difilter sebelum dipanggil). Fungsi
   ini TIDAK PERNAH memanggil `HistorySelect(0, now)` atau melakukan loop atas deal lama — ia hanya
   menggulirkan jendela hari/sesi (`RollDailySessionWindows()`, O(1) kecuali saat sesi berubah, lihat
   poin 5) lalu memanggil `ApplyStatsDeal()` untuk deal yang baru saja masuk. Biaya per deal sekarang
   O(1) teramortisasi, bukan O(total deal sejauh ini).
5. **`RollDailySessionWindows(startOfDayUTC, currentSess)`** — pergantian hari me-nol-kan
   `dailyProfit`/`dailyPips`/`sessionWins`/`sessionLosses` dan daftar `g_statsTodaySess[]`/
   `g_statsTodayWin[]` (trade yang sudah selesai hari ini, dipakai untuk `AddTodayCompletedTrade()`).
   Pergantian sesi TANPA deal baru (mis. EA idle waktu jam sesi berganti) menghitung ulang
   `sessionWins/sessionLosses` hanya dari daftar `g_statsTodaySess[]`/`g_statsTodayWin[]` — dibatasi
   jumlah trade per hari, bukan seluruh riwayat deal — sehingga tetap O(trade hari ini), bukan
   O(total history).
6. **`RebuildStatsHistoryFull()`** — SATU-SATUNYA fungsi yang masih memanggil `HistorySelect(0, now)`
   plus loop penuh atas semua deal (`ResetStatsHistoryState()` lalu `ApplyStatsDeal()` untuk tiap deal
   secara berurutan). Dipertahankan sebagai fallback/verifikasi, dipanggil HANYA di tiga tempat:
   startup (`g_statsHistoryBuilt == false` pertama kali dari `UpdateStatsFromHistory()`/
   `OnStatsDealArrived()`), recovery (kondisi yang sama setelah terminal/tester restart), dan reset
   manual (`BTN_CLEAR_WR`, lihat poin 7) — bukan lagi hot path per-deal.
7. **`OnChartEvent()` — tombol `BTN_CLEAR_WR`**: sebelumnya hanya men-set `g_statsHistoryDirty = true`
   dan menunggu panggilan `UpdateStatsFromHistory()` berikutnya untuk membangun ulang secara lazy.
   Sekarang memanggil `RebuildStatsHistoryFull()` langsung di tempat, supaya dashboard langsung
   mencerminkan reset dan supaya akumulator persisten per-posisi (yang menyimpan profit dari SEBELUM
   `resetEpoch` baru) tidak tertinggal stale di dalamnya.
8. **`UpdateStatsFromHistory()`** sekarang ringan: kalau `g_statsHistoryBuilt` masih `false` atau
   `g_statsHistoryDirty` sedang `true` (hanya terjadi di startup/reset), panggil
   `RebuildStatsHistoryFull()`; selain itu hanya menggulirkan jendela hari/sesi dan menghitung ulang
   `dailyProfitPct` dari `AccountInfoDouble(ACCOUNT_BALANCE)` — keduanya O(1), tidak bergantung
   ukuran history. Semua titik panggilnya yang lama (OnInit, cek pergantian hari, sinkronisasi
   tester-visual, timer dashboard 60 detik, `OnNewHTFBar()`) tidak berubah tempat/frekuensi
   panggilnya, hanya jadi jauh lebih murah untuk dipanggil sesering itu.

**Kenapa hasil akhirnya tetap sama.** `ApplyStatsDeal()` menerapkan urutan logika yang identik
dengan loop lama (filter magic/symbol di pemanggil, akumulasi profit harian dengan gerbang
`resetEpoch`, pencarian/pembuatan slot posisi, akumulasi volume-weighted price untuk pip, deteksi
exit) — bedanya hanya WAKTU logika itu dijalankan (satu deal saat itu juga, bukan seluruh riwayat
tiap kali ada satu deal baru) dan DI MANA hasilnya disimpan (state persisten, bukan array lokal yang
dibuang tiap panggilan). `TryFinalizeStatsPosition()` mereplikasi pengecekan "masih ada posisi
terbuka dengan `POSITION_IDENTIFIER` ini?" yang sama seperti loop finalisasi lama — bedanya
dijalankan tepat saat deal exit terakhir mendarat, bukan menyisir ulang seluruh `posCount` di setiap
panggilan.

**Cakupan yang tidak berubah.** Definisi "trade selesai" (semua leg tertutup, `posCloseTime` setelah
`resetEpoch`), perhitungan pip berbobot volume untuk TP1/TP2/runner, filter magic+symbol, dan semua
titik panggil `UpdateStatsFromHistory()` yang sudah ada tidak diubah.

**Kriteria lulus.** Waktu proses per 10.000 deal tidak tumbuh linear terhadap seluruh history pada
setiap close — biaya per deal baru konstan, tidak bergantung berapa banyak deal yang sudah ada
sebelumnya. Nilai akhir `g_stats` (totalTrades, totalWins, totalProfit, totalPips, dailyProfit,
dailyPips, sessionWins, sessionLosses) identik dengan hasil `HistorySelect(0, now)` penuh atas
riwayat yang sama, baik lewat jalur incremental maupun lewat `RebuildStatsHistoryFull()`.

---

## 55. v4.47.16 — Konversi UTC live memakai offset broker "sekarang" untuk timestamp lama (M5)

Bug atribusi waktu. Mode terdampak: live/demo dan rebuild statistik. Riwayat: `CHANGELOG.md`
4.47.16. Identitas: `YANSTD_VERSION = "4.47.16-HYBRID"`.

File: `Modules/SessionManager.mqh` (`ConvertServerToUTC()`), `YANSTD.mq5` (pemanggil tidak berubah,
tapi diuntungkan langsung: `RebuildStatsHistoryFull()`/`ApplyStatsDeal()` §54, dan atribusi sesi
Brain di `OnTradeTransaction()`).

**Masalah.** Di jalur live/demo (`!MQLInfoInteger(MQL_TESTER)`), `ConvertServerToUTC(serverTime)`
mengukur `TimeTradeServer() - TimeGMT()` — offset broker-ke-GMT **saat fungsi dipanggil** — lalu
memakai angka itu untuk mengonversi `serverTime` APA PUN, termasuk timestamp deal yang jauh di masa
lalu. Ini benar selama `serverTime` dekat dengan "sekarang" (mis. `GetSimulatedUTC()` untuk deteksi
sesi/hari berjalan), tapi salah satu jam penuh untuk deal historis yang berada di sisi DST yang
berbeda dari hari EA dijalankan — misalnya EA di-restart bulan Januari (winter, tanpa DST) lalu
`RebuildStatsHistoryFull()` (§54) memproses deal dari bulan Juli (summer, DST aktif) memakai offset
Januari, sehingga `dailyProfit`/atribusi sesi hari itu bergeser satu jam. Cabang tester sudah benar
sejak awal: `GetConfiguredTesterOffsetHours(serverTime)` memakai kalender DST (`IsEuropeanDST()`)
yang dievaluasi untuk `serverTime` itu sendiri, bukan untuk hari test berjalan — jadi bug ini murni
di cabang live.

**Solusi.** Cabang live tidak lagi memakai bacaan `TimeTradeServer() - TimeGMT()` langsung sebagai
offset historis universal. Sebagai gantinya:

1. Bacaan live itu (`liveOffsetSeconds`) dilucuti dulu ke baseline musim dingin (non-DST) broker,
   dengan menguji `IsEuropeanDST(brokerNow)` — kalender DST konfigurasi yang sama persis dipakai
   cabang tester, bukan bacaan ad-hoc baru.
2. Baseline musim dingin itu lalu di-DST-adjust ULANG khusus untuk `serverTime` yang sedang
   dikonversi (`IsEuropeanDST(serverTime)`), bukan untuk `brokerNow`.
3. Hasil akhirnya: `serverTime - (winterOffsetSeconds + (IsEuropeanDST(serverTime) ? 3600 : 0))`.

**Kenapa "sekarang" tidak berubah perilakunya.** Untuk pemanggilan yang paling umum —
`GetSimulatedUTC()` (dipakai deteksi sesi, pergantian hari/sesi §54, filter jam trading) —
`serverTime` yang dikonversi ADALAH `TimeCurrent()`, sehingga `IsEuropeanDST(serverTime)` dan
`IsEuropeanDST(brokerNow)` mengevaluasi tanggal yang (hampir) sama dan saling meniadakan: hasilnya
identik dengan bacaan live lama. Selisih hanya muncul persis saat `serverTime` adalah timestamp
historis yang beda status DST-nya dari hari ini — target bug yang diperbaiki.

**Cakupan yang tidak berubah.** Cabang tester (`GetConfiguredTesterOffsetHours()`) tidak disentuh
sama sekali — sudah historically-correct sejak awal. `GetSessionAtUTC()`/`NYShift()`/`IsUSDST()`
(pergeseran batas sesi NY musim dingin AS) tidak disentuh — itu perhitungan terpisah dari offset
broker-ke-GMT. Tidak ada pemanggil di `YANSTD.mq5` yang perlu diubah; semuanya otomatis memakai
konversi yang sudah benar begitu `ConvertServerToUTC()` diperbaiki di satu tempat ini.

**Kriteria lulus.** Konversi `ConvertServerToUTC(historicalTime)` di live/demo tepat baik untuk
timestamp tepat sebelum maupun sesudah transisi DST, untuk tahun yang berbeda dari tahun EA sedang
berjalan — tidak lagi bergeser satu jam hanya karena status DST hari ini berbeda dari status DST
pada `historicalTime` tersebut.


## 56. v4.48.0 — Kalibrasi Tangga Lot GRADE Berbasis Bukti Gen-6C..6H + Unblock Mode 0

### Latar Belakang & Bukti Nyata

Sebelum v4.48.0, tangga lot setup grade menempatkan `S`, `S+`, `A`, dan `A+` seluruhnya
di pengali maksimum **2.00x**. Data atribusi lintas-generasi Gen-6C hingga Gen-6H
(periode patokan inti 2020 s.d. 2026-08-31) menunjukkan bahwa klasifikasi grade
belum menghasilkan pemisahan monoton pada pengali tersebut:

- **Mode 1 (MSNR Primary, Soft SMC):**
  - **Grade S:** n = 16.773, Net = +$22.846, Expectancy = **+$1.36 / trade**, WinRate = 45.4% (edge positif solid)
  - **Grade A:** n = 25.183, Net = -$17.433, Expectancy = **-$0.69 / trade**, WinRate = 37.9% (**bucket rugi terbesar**)
  - **Grade B:** n = 16.262, Net = -$22.990, Expectancy = **-$1.41 / trade**, WinRate = 34.6% (rugi)

Memberi pengali 2.00x (risiko maksimum) pada Grade A yang ber-expectancy negatif
memperbesar drawdown sistem secara sistematis saat mode dynamic risk / %risk aktif.

### Tangga Lot Baru (v4.48.0)

| Grade | Multiplier | Peran |
|---|---|---|
| **S+ / S** | **2.00x** | Tertinggi tunggal — edge positif terbukti |
| **A+ / A** | **1.50x** | Tertinggi kedua — diturunkan dari 2.00x agar tidak menyentuh plafon risiko |
| **B+ / B** | **1.00x** | Tidak terlalu tinggi (baseline lot 1.0) |
| **C+ / C** | **0.50x** | Low quality |
| **D+ / D** | **0.00x** | Harus dilewatkan (reject otomatis via `SetupGradeRejects()`) |

Source of truth kode: `Modules/Defines.mqh::SetupGradeLotMultiplier()`.
Unit test: `Tests/Test_SetupGradeLotMultiplier.mq5`.

### Unblock Mode 0 (Hybrid MSNR + SMC)

Di `Modules/SignalEngine.mqh`, Mode 0 sebelumnya dikenai hard gate `EvaluatePrimaryGate()`
yang membuang 55% POI (`NO_ACTIVE_POI`), menyisakan hanya 114 trade dalam 7 tahun.
Mulai v4.48.0, hard gate ini dikhususkan hanya untuk Mode 1 (`SETUP_MSNR_PRIMARY`).
Untuk Mode 0 dan Mode 2, MSNR berfungsi sebagai **soft scoring overlay** via
`FindBestOverlappingMapZone()` tanpa membatalkan pembentukan POI.

## 57. v4.48.1 — Perbaikan Defect Keras Sizing Jalur Market (2026-09-17)

Audit 60 run Gen-7 Full menemukan tiga defect yang saling memperkuat, semuanya hanya muncul di
Mode 1 (`SETUP_MSNR_PRIMARY`) dengan sizing risk-% dinamis:

1. **`SSignal.riskPct` tidak pernah di-assign di `GenerateSignalMSNRPrimary()`.** Kedua jalur SMC
   (`GenerateSignal`, blok BUY dan SELL) menulis `sig.riskPct = effRisk`, tetapi jalur MSNR tidak.
   `ResizeLotForMarketFill()` men-size ulang fill **market** dari `sig.riskPct`; struct lokal MQL5
   tidak di-zero-init, jadi lot dihitung dari nilai tak terdefinisi lalu di-clamp ke
   `SYMBOL_VOLUME_MAX` (200). Akibat: 125–131 entri @200.00 lot di Y2007–Y2008 (≈ −$45.260).
   **Aturan:** setiap jalur yang membuat `SSignal` untuk eksekusi **market** WAJIB menulis
   `sig.riskPct`; `ResizeLotForMarketFill()` bergantung padanya.
2. **`ExecuteBuy()`/`ExecuteSell()` tidak pernah memanggil `CanAddAggregateRisk()`.** Guard agregat
   hanya ada di jalur manual dan jalur limit. Sekarang keduanya memanggil guard yang sama
   (`REJECT_AGGREGATE_RISK` + log `RISK_GUARD`).
3. **Tidak ada plafon lot absolut.** Input baru `InpMaxLot` (0 = nonaktif) ditegakkan di
   `NormalizeLotToBrokerLimits()` **sebelum** clamp broker, dan clamp broker-max kini dihitung
   sebagai `LOT_MAX_CLAMP` (dulu senyap), dengan `LOT_POLICY_CAP` untuk pemotongan oleh `InpMaxLot`.
   Keduanya muncul di `[YANSTD FINAL]` dan `[YANSTD SIZING]`.

Verifikasi terarah M1 Y2008: Net −$32.029,91 → **+$171,26**; max lot 200.00 → **4,93**;
125 entri@200 → **0**; DD 106,86% → **16,18%** (dengan `InpMaxLot=OFF`, membuktikan perbaikan
root-cause `sig.riskPct` yang bekerja, bukan sekadar plafon).

## 61. v4.51.0 — V15 Champion Locked, Gen-16 Hypo Test (2026-09-18)

**Gen-16 validation: Hypo 1 (M1 scalp) = FAILED, Hypo 2 (HTF) = SKIP:**

1. **Hypo 1 (M1 scan sensitivity) = FAILED.** ScanBars 300→50 menurunkan profit 37% (+$6.021→+$3.790), trade count turun (1,245→968). Zona M5 lebih sensitif di MSNR scan — false signal naik. **Scan 300 tetap optimal.**

2. **Hypo 2 (HTF trigger) = SKIPED.** `ENUM_SETUP_MODE` hanya punya 3 nilai (HYBRID/MSNR/SMC). Butuh enum baru `SETUP_M1_TRIGGERED` — terlalu invasif untuk refinement cycle. Disimpan untuk riset terpisah.

3. **V15 SL2.0 + 24h = champion definitif.** Chain lengkap:
   - V6 SL1.50: +$5,247 → V9 SL2.0: +$5,771 → V15 24H: **+$6,021** (+$774 dari baseline V6)
   - Trade count: 1,616 → 1,222 → **1,245** (quality over quantity)
   - DD tetap <11%, PF naik 1.25 → 1.30

**Champion final frozen:** `YANSTD_XAUUSD_M2_G16_V15_CHAMPION.set` (SL2.0 + 24h + BlockOverlap ON)

## 62. v4.52.0 — Gen-17 BlockOverlap OFF Champion (2026-09-18)

**Gen-17 hasil: BlockOverlap OFF = champion baru:**

1. **BlockOverlap OFF = winner.** V15 (overlap ON) → V17 (overlap OFF):
   - V15 ON: +$6,021, PF 1.30, DD 10.42%, 1,245 trades (exp +4.84)
   - V17 OFF: **+$7,090, PF 1.31, DD 10.29%, 1,384 trades (exp +5.12)**
   - Δ = +$1,069 profit, trades naik 139 — BlockOverlap filter terlalu ketat untuk 24h session. London/NY overlap block mengurangi entry valid.

2. **SL 2.50 = tidak unggul.** Trade turun 20% (1,032), profit turun → +$5,838. SL 2.0 optimal.

3. **Grade gate S = tidak berpengaruh.** Hasil identitcal V15.

**Full chain:** V6(+$5.247) → V9(+$5.771) → V15(+$6.021) → **V17(+$7.090)**

**Champion frozen:** `YANSTD_XAUUSD_M2_G18_V15_NOCHAMP.set` (SL2.0 + 24h + BlockOverlap=0)

## 63. G27B — champion berjalan (2026-09-22)

V17 dilampaui. Angka di bawah window 2020.01.01–2026.08.31, bukan live.

| | G27B | G27A | G28 TP1 0.6 MaxPos 5 |
|---|---|---|---|
| Net | **+$9,196** | +$8,660 | +$5,327 |
| PF | **1.34** | 1.32 | 1.26 |
| Trade | 1,309 | 1,404 | 1,686 |
| Sharpe | 3.49 | 3.42 | 3.13 |
| DD | 11.81% | 11.53% | 11.99% |

Kunci G27B: `InpTP1RR=1.5`, `InpMaxActivePositions=3`, varian `FVG_50,FIB_790`, `InpRequireM3Sweep=1`, `InpUseLayer2M15Gate=1`.

Preset live: `Backtests\YANSTD-LIVE-SELECTION-MODULE\Candidates_Gen27\G27B_Live_Demo\G27B_TP1_1.5_MAXPOS3_LIVE.set` (`InpShowDashboard=1`).

Turunkan TP1 atau naikkan MaxPos sudah diuji di G28: trade naik, PF jatuh ke 1.26. Bukan champion.

## 60. v4.50.0 — 24h Session V15 Champion (2026-09-18)

**Hypo 3 (time filter relaxation) terbukti.** Membuka seluruh sesi Asia:

1. **Asian session (00-07 UTC) kini terbuka.** Setting lama `InpStartHourUTC=7` — Asian early excluded. V15 ubah ke `0` + `InpEndHourUTC=23`. Friday cutoff `15→23`.

2. **Trade count naik:** V9 (1,222) → V15 (1,245) — +18 trade/7yr. Profit naik +$250 (PF 1.29 → 1.30, DD 10.85% → 10.42%).

3. **DD tetap <20% target.** Time filter relaxation tidak menambah risk secara signifikan — BlockOverlap + InpMaxAggregateRiskPct tetap menahan eksposisi.

**Input yang dipaksa:** `InpStartHourUTC=0`, `InpEndHourUTC=23`, `InpFridayCutoffHour=23`, `InpBlockSundayOpen=false`.

## 59. v4.49.0 — SL ATR 2.00 Champion Refinement (2026-09-18) — SL ATR 2.00 Champion Refinement + Schema Validator (REFINE Gen-13/14)

Hasil akhir refinement rantai V6 SL1.50 → V9 SL2.0 (kontinu 2020.01.01–2026.08.31):

1. **SL ATR 2.00 = champion baru.** V9 (SLATRMult=2.00) +V5.771 (PF 1.29, exp +4.72, DD 10.85%, 1.222 trades) mengalahkan V6 (SLATRMult=1.50) +V5.247. Trade count turun 24% tetapi profit naik +$524 — SL yang lebih longgar mengurangi whipsaw di 2022/2024 vol-spike.

2. **InpMinTradeGrade tidak berpengaruh pada P&L.** Semua level grade (S+/S/A+/A/B+/B/C+/C/D) hasilnya identitcal pada Gen-13. Input tetap tersedia untuk instrumentation tetapi tidak dipakai sebagai hard gate.

3. **FVG_50-only / FVG_50-S+ = jebol** — FIB_790 vital (Gen-12 attribution: +$1.588). Jangan drop FIB variants.

4. **NY session never blocked.** BlockOverlap hanya blokir London+NY *overlap*; NY tetap aktif (−overlap zone only). NY +$3.965 tetap dominan kontributor di V6 attribution.

5. **Schema validator dinamis** (`Run-YANSTDBacktestJob.ps1`): jumlah `input` declaration dihitung langsung dari `YANSTD.mq5`, bukan hardcode angka. Memperbaiki Gen-10/13 recursion schema-mismatch yang disebabkan oleh penambahan input baru (`InpBlockOverlapSession`, `InpMinTradeGrade`).

**Champion frozen:** `Candidates_Gen15/YANSTD_XAUUSD_M2_G15_V9_CHAMPION.set` — SLATRMult=2.00, InpBlockOverlapSession=1, InpEntryVariants=ALL.

## 58. v4.48.2 — Filter Sesi Overlap + Variant Whitelist Jalur MSNR_PRIMARY (2026-09-18)

Dua perubahan perilaku dari atribusi Gen-9CONT (window kontinu 2020.01.01–2026.08.31):

1. **`InpBlockOverlapSession` (default `false`).** Atribusi per-sesi M2: Overlap LDN+NY
   −$609,25 vs Asia +$255,16 / London +$1.078,80 / NY +$190,94 — Overlap adalah drag tunggal
   terbesar. Saat `true`, `TimeFilterAllowsEntry()` menolak entry ketika
   `g_session.GetCurrentSession() == SESSION_OVERLAP` (13–17 UTC summer / 14–18 winter).
   Gate ini berada di helper tunggal, jadi berlaku untuk **semua** jalur yang lewat
   `TimeFilterAllowsEntry()` (market, limit, dan MSNR_PRIMARY) — bukan tambalan per-jalur.

2. **Variant whitelist kini ditegakkan di jalur MSNR_PRIMARY.** `PlaceMSNRPrimaryLimit()`
   tidak pernah memanggil `g_entryVariants.IsAllowed()` — dua jalur lain
   (`ManageAutoLimitOrders` untuk FALLBACK/DIRECT) sudah memanggilnya sejak lama. Akibatnya
   preset `InpEntryVariants=FIB_618` tetap bisa tereksekusi sebagai OB_45 di Mode 1. Guard
   `if(!g_entryVariants.IsAllowed(sig.entryType)) return;` ditambahkan di awal fungsi.
   **Aturan:** setiap jalur yang mengeksekusi sinyal WAJIB melewati `g_entryVariants.IsAllowed()`
   terhadap `sig.entryType` sebelum mengirim order.

Verifikasi: compile 0 error / 0 warning; atribusi Gen-9CONT di `Attribution_9CONT/` sebagai basis.
