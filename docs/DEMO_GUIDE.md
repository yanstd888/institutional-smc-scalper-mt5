# Uji Demo L5 vs G27B (berdampingan, satu akun demo)

## Preset (di LAYLA\Presets)
| Preset | Isi | Magic |
|---|---|---|
| `DEMO_G27B.set` | salinan byte champion live preset (expiry 30) | 494004 |
| `DEMO_L5.set` | L5 (expiry 60), satu-satunya beda: magic | 494005 |

## Binary EA untuk demo
**Champion root sudah diperbaiki GUI-nya** (2026-09-23, izin user): tombol RST title bar + bug tile
PROFIT raksasa + subtitle mode dinamis. EX5 aktif: 631.530 byte, SHA-256 `0e11641049c0...`
(sama di root, LAYLA, dan stage `YANSTD_AUDIT`). Perbedaan dari binary lama HANYA `StatsDashboard.mqh`
(display) — logika trade identik, semua file lain byte-identik.
Binary lama di-backup: `YANSTD.ex5.champion-backup` 631.362 byte `9176fa8f592b...` (root & LAYLA).
Preset champion tidak tersentuh: `85ff14c257f2...`.
Setelah menyalin EX5 baru, refresh Navigator MT5 (klik kanan -> Refresh) lalu pasang ulang EA di kedua chart.

## Cara pasang
1. Akun demo yang sama, dua chart **XAUUSD.FXSPREAD M3**.
2. Chart 1: pasang EA, load `DEMO_G27B.set`. Chart 2: pasang EA, load `DEMO_L5.set`.
3. Algo Trading ON keduanya. Jangan ubah input apa pun dari preset.

## Aturan evaluasi (tetap sekarang, jangan digeser saat berjalan)
- Nilai setelah KEDUANYA >= 100 trade (kira-kira 2-3 bulan).
- L5 lulus jika: PF demo L5 tidak lebih rendah > 0,10 dari G27B, dan net/trade sepadan.
- L5 kalah jelas -> L5 dibuang, G27B tetap champion.
- L5 setara/menang -> L5 layak dicatat sebagai preset live baru (keputusan user).

## Ekspektasi
Angka demo pasti sedikit lebih jelek dari backtest (slippage, spread nyata).
Yang dinilai selisih ANTAR preset, bukan angka absolut.
