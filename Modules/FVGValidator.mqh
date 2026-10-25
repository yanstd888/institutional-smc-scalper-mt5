//+------------------------------------------------------------------+
//|                                               FVGValidator.mqh   |
//|         YANSTD EA — FVG becomes an ENTRY POI only if it passes   |
//|                                    v4.39  |  2026-09-09          |
//+------------------------------------------------------------------+
#ifndef YANSTD_FVG_VALIDATOR_MQH
#define YANSTD_FVG_VALIDATOR_MQH
#include "Defines.mqh"

// Runtime knobs pushed from OnInit (modules cannot read EA `input`).
struct SFVGValidatorCfg
  {
   string            symbol;
   int               atrPeriod;
   double            minATRMult;
   double            impulseBodyRatio;
   int               maxBarAge;
   bool              requireStructure;
   int               wingLTF;   // native TF + H1 fractal wing (default 3)
   int               wingHTF;   // H4 fractal wing (default 2)
  };

SFVGValidatorCfg g_fvgVal;

struct SFVGStructureCache
  {
   string            symbol;
   ENUM_TIMEFRAMES   tf;
   datetime          formationTime;
   double            bottom;
   double            top;
   bool              qualified;
  };

SFVGStructureCache g_fvgStructureCache[];
int g_fvgStructureCacheNext = 0;
#define FVG_STRUCTURE_CACHE_SIZE 512

struct SFVGLevelCache
  {
   string            symbol;
   ENUM_TIMEFRAMES   tf;
   datetime          anchorTime;
   int               lookback;
   int               wing;
   int               count;
   double            levels[128];
  };
SFVGLevelCache g_fvgLevelCache[];
int g_fvgLevelCacheNext = 0;
#define FVG_LEVEL_CACHE_SIZE 32

void SetFVGValidatorParams(string symbol, double minATRMult, int maxBarAge,
                           double impulseBodyRatio, bool requireStructure, int atrPeriod,
                           int wingLTF = 3, int wingHTF = 2)
  {
   g_fvgVal.symbol            = (symbol == NULL || symbol == "") ? Symbol() : symbol;
   g_fvgVal.atrPeriod         = (atrPeriod > 0) ? atrPeriod : 14;
   g_fvgVal.minATRMult        = (minATRMult > 0.0) ? minATRMult : 0.30;
   g_fvgVal.impulseBodyRatio  = MathMax(0.50, MathMin(0.95, impulseBodyRatio));
   g_fvgVal.maxBarAge         = (maxBarAge <= 0) ? 36 : maxBarAge; // AUDIT FIX: 0 defaults to 36 instead of clamping to 1 bar
   g_fvgVal.requireStructure  = requireStructure;
   g_fvgVal.wingLTF           = MathMax(2, wingLTF);
   g_fvgVal.wingHTF           = MathMax(2, wingHTF);
   ArrayResize(g_fvgStructureCache, 0);
   g_fvgStructureCacheNext = 0;
   ArrayResize(g_fvgLevelCache, 0);
   g_fvgLevelCacheNext = 0;
  }

bool FVGRangeOverlapsLevel(const double fvgBottom, const double fvgTop, const double levelPrice)
  {
   if(fvgTop <= fvgBottom || levelPrice <= 0.0) return false;
   return (fvgBottom <= levelPrice && fvgTop >= levelPrice);
  }

bool FVGRangeOverlapsZone(const double fvgBottom, const double fvgTop,
                          const double zoneBottom, const double zoneTop)
  {
   if(fvgTop <= fvgBottom || zoneTop <= zoneBottom) return false;
   return (fvgBottom <= zoneTop && fvgTop >= zoneBottom);
  }

double FVGPsychologicalStep(const string symbol)
  {
   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0) return 5.0;
   if(StringFind(symbol, "XAG") >= 0 || StringFind(symbol, "SILVER") >= 0) return 0.50;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits <= 3) return 0.50;          // JPY pairs: 50-pip figures
   return 0.0050;                        // 5-digit FX: 50-pip figures
  }

void FVGAppendLevel(double &levels[], int &n, const double price)
  {
   if(price <= 0.0 || n >= ArraySize(levels)) return;
   for(int i = 0; i < n; i++)
      if(MathAbs(levels[i] - price) <= 0.0) return;
   levels[n++] = price;
  }

void FVGCollectFractalSwings(const string symbol, ENUM_TIMEFRAMES tf, int youngerThanShift,
                             double &levels[], int &n, const int lookback = 80, const int wing = 3)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 0, MathMax(lookback + wing + 2, youngerThanShift + lookback), rates);
   if(copied < wing * 2 + 3) return;
   // The complete right wing must already exist at formation time. Starting
   // only two bars older leaked one future bar when wing=3.
   int start = MathMax(youngerThanShift + wing, wing);
   int stop  = MathMin(copied - wing, start + lookback);
   for(int i = start; i < stop; i++)
     {
      bool peak = IsFractalPivot(rates, copied, i, wing, wing, true);
      bool trough = IsFractalPivot(rates, copied, i, wing, wing, false);
      if(peak)   FVGAppendLevel(levels, n, rates[i].high);
      if(trough) FVGAppendLevel(levels, n, rates[i].low);

      // SBR / RBS: a swing that later candles closed through becomes a flipped key level.
      if(peak)
        {
         for(int k = i - 1; k >= youngerThanShift && k >= 1; k--)
           {
            if(rates[k].close > rates[i].high)
              { FVGAppendLevel(levels, n, rates[i].high); break; }
           }
        }
      if(trough)
        {
         for(int k = i - 1; k >= youngerThanShift && k >= 1; k--)
           {
            if(rates[k].close < rates[i].low)
              { FVGAppendLevel(levels, n, rates[i].low); break; }
           }
        }
     }
  }

// Cache key is (symbol, tf, that TF's bar containing formationTime, lookback, wing).
// Many FVG candidates on the same M5/H1/H4 bar reuse one CopyRates scan.
void FVGCollectCachedFractalSwings(const string symbol, ENUM_TIMEFRAMES tf,
                                   datetime formationTime, double &levels[], int &n,
                                   const int lookback, const int wing)
  {
   int anchorShift = iBarShift(symbol, tf, formationTime, false);
   if(anchorShift < 1) return;
   datetime anchorTime = iTime(symbol, tf, anchorShift);
   int cacheCount = ArraySize(g_fvgLevelCache);
   int slot = -1;
   for(int i = 0; i < cacheCount; i++)
      if(g_fvgLevelCache[i].symbol == symbol && g_fvgLevelCache[i].tf == tf &&
         g_fvgLevelCache[i].anchorTime == anchorTime &&
         g_fvgLevelCache[i].lookback == lookback && g_fvgLevelCache[i].wing == wing)
        { slot = i; break; }

   if(slot < 0)
     {
      double found[];
      ArrayResize(found, 128);
      int foundCount = 0;
      FVGCollectFractalSwings(symbol, tf, anchorShift, found, foundCount, lookback, wing);
      if(cacheCount < FVG_LEVEL_CACHE_SIZE)
        {
         slot = cacheCount;
         ArrayResize(g_fvgLevelCache, cacheCount + 1, 8);
        }
      else
        {
         slot = g_fvgLevelCacheNext;
         g_fvgLevelCacheNext = (g_fvgLevelCacheNext + 1) % FVG_LEVEL_CACHE_SIZE;
        }
      g_fvgLevelCache[slot].symbol = symbol;
      g_fvgLevelCache[slot].tf = tf;
      g_fvgLevelCache[slot].anchorTime = anchorTime;
      g_fvgLevelCache[slot].lookback = lookback;
      g_fvgLevelCache[slot].wing = wing;
      g_fvgLevelCache[slot].count = MathMin(foundCount, 128);
      for(int j = 0; j < g_fvgLevelCache[slot].count; j++)
         g_fvgLevelCache[slot].levels[j] = found[j];
     }

   for(int j = 0; j < g_fvgLevelCache[slot].count; j++)
      FVGAppendLevel(levels, n, g_fvgLevelCache[slot].levels[j]);
  }

void FVGCollectPsychological(const string symbol, const double mid, double &levels[], int &n)
  {
   double step = FVGPsychologicalStep(symbol);
   if(step <= 0.0 || mid <= 0.0) return;
   double base = MathFloor(mid / step) * step;
   for(int k = -3; k <= 3; k++)
      FVGAppendLevel(levels, n, base + k * step);
  }

bool FVGTouchesAnyLevel(const double fvgBottom, const double fvgTop, const double &levels[], const int n)
  {
   for(int i = 0; i < n; i++)
      if(FVGRangeOverlapsLevel(fvgBottom, fvgTop, levels[i]))
         return true;
   return false;
  }

// Mechanical 3-candle FVG at `shift` (newest candle of the trio = rates[shift]).
// Candle mapping ICT: C1=oldest rates[shift+2], C2=displacement rates[shift+1], C3=newest rates[shift].
bool IsFVGValidFromRates(const MqlRates &rates[], const int copied, int shift,
                         ENUM_TIMEFRAMES tf, double &fvgTop,
                         double &fvgBottom, bool &isBull)
  {
   fvgTop = fvgBottom = 0.0;
   isBull = false;
   string symbol = (g_fvgVal.symbol == "") ? "" : g_fvgVal.symbol;
   if(g_fvgVal.maxBarAge <= 0)
     {
      static datetime s_lastWarn = 0;
      datetime now = TimeCurrent();
      if(now - s_lastWarn >= 60)
        {
         Print("⚠️ [YANSTD FVGValidator] Uninitialized config; fallback applied. symbol=",
               (symbol == "" ? "UNSPECIFIED" : symbol));
         s_lastWarn = now;
        }
      if(symbol == "")
         return false;
      SetFVGValidatorParams(symbol, 0.30, 36, 0.70, true, 14);
     }
   if(symbol == "")
      return false;
   if(shift < 1) return false;
   if(shift > MathMax(1, g_fvgVal.maxBarAge)) return false;

   if(copied < shift + 3) return false;

   const double c2Range = rates[shift+1].high - rates[shift+1].low;
   if(c2Range <= 0.0) return false;
   const double c2Body  = MathAbs(rates[shift+1].close - rates[shift+1].open);
   if(c2Body / c2Range < g_fvgVal.impulseBodyRatio) return false;

   // AUDIT FIX H1: use the ATR at the displacement candle's own shift
   // (shift+1 = C2), not "now's" ATR. Otherwise an old FVG's pass/fail can
   // flip purely because volatility changed after it formed.
   const double atr = ReadATRAtShift(symbol, tf, g_fvgVal.atrPeriod, shift + 1);
   const double minGap = (atr > 0.0)
                         ? (g_fvgVal.minATRMult * atr)
                         : (SymbolInfoDouble(symbol, SYMBOL_POINT) * GetPipFactor(symbol));

   const bool c2Bull = (rates[shift+1].close > rates[shift+1].open);
   const bool c2Bear = (rates[shift+1].close < rates[shift+1].open);
   const double bullGap = rates[shift].low - rates[shift+2].high;
   const double bearGap = rates[shift+2].low - rates[shift].high;

   if(c2Bull && bullGap >= minGap)
     {
      isBull = true;
      fvgTop = rates[shift].low;
      fvgBottom = rates[shift+2].high;
     }
   else if(c2Bear && bearGap >= minGap)
     {
      isBull = false;
      fvgTop = rates[shift+2].low;
      fvgBottom = rates[shift].high;
     }
   else
      return false;

   if(fvgTop <= fvgBottom) return false;

   // M1 (2026-09-13, §49): CE 50% is the entry point AND the eligibility
   // cutoff. The instant price first reaches/crosses the 50% consequent
   // encroachment, the FVG is complete/mitigated and can no longer
   // originate a new FVG entry -- there is no 80% grace window anymore.
   // Full fill (>= 1.0) is still reachable and still worth knowing about
   // as an information/full-invalidation marker for callers that track
   // it, but it is redundant for *this* gate since eligibility already
   // closed at CE.
   const double fillRatio = FVGFillRatio(isBull, fvgTop, fvgBottom, rates, copied, shift - 1);
   if(fillRatio >= 0.50) return false;
   return true;
  }

bool IsFVGValid(int shift, ENUM_TIMEFRAMES tf, double &fvgTop, double &fvgBottom, bool &isBull)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates((g_fvgVal.symbol == "") ? Symbol() : g_fvgVal.symbol,
                          tf, 0, shift + 4, rates);
   return IsFVGValidFromRates(rates, copied, shift, tf, fvgTop, fvgBottom, isBull);
  }

bool IsFVGStructureQualified(ENUM_TIMEFRAMES tf, datetime formationTime,
                             double fvgBottom, double fvgTop)
  {
   if(!g_fvgVal.requireStructure) return true;
   string symbol = (g_fvgVal.symbol == "") ? Symbol() : g_fvgVal.symbol;

   int cacheCount = ArraySize(g_fvgStructureCache);
   for(int i = 0; i < cacheCount; i++)
      if(g_fvgStructureCache[i].symbol == symbol && g_fvgStructureCache[i].tf == tf &&
         g_fvgStructureCache[i].formationTime == formationTime &&
         g_fvgStructureCache[i].bottom == fvgBottom && g_fvgStructureCache[i].top == fvgTop)
         return g_fvgStructureCache[i].qualified;

   double levels[];
   ArrayResize(levels, 128);
   int n = 0;
   const int wingLTF = (g_fvgVal.wingLTF >= 2) ? g_fvgVal.wingLTF : 3;
   const int wingHTF = (g_fvgVal.wingHTF >= 2) ? g_fvgVal.wingHTF : 2;
   FVGCollectCachedFractalSwings(symbol, tf, formationTime, levels, n, 80, wingLTF);
   if(tf != PERIOD_H1)
      FVGCollectCachedFractalSwings(symbol, PERIOD_H1, formationTime, levels, n, 40, wingLTF);
   if(tf != PERIOD_H4)
      FVGCollectCachedFractalSwings(symbol, PERIOD_H4, formationTime, levels, n, 30, wingHTF);
   FVGCollectPsychological(symbol, (fvgTop + fvgBottom) * 0.5, levels, n);
   bool qualified = FVGTouchesAnyLevel(fvgBottom, fvgTop, levels, n);

   int slot = 0;
   if(cacheCount < FVG_STRUCTURE_CACHE_SIZE)
     {
      slot = cacheCount;
      ArrayResize(g_fvgStructureCache, cacheCount + 1, 64);
     }
   else
     {
      slot = g_fvgStructureCacheNext;
      g_fvgStructureCacheNext = (g_fvgStructureCacheNext + 1) % FVG_STRUCTURE_CACHE_SIZE;
     }
   g_fvgStructureCache[slot].symbol = symbol;
   g_fvgStructureCache[slot].tf = tf;
   g_fvgStructureCache[slot].formationTime = formationTime;
   g_fvgStructureCache[slot].bottom = fvgBottom;
   g_fvgStructureCache[slot].top = fvgTop;
   g_fvgStructureCache[slot].qualified = qualified;
   return qualified;
  }

bool IsFVGValidWithStructureFromRates(const MqlRates &rates[], const int copied,
                                      int shift, ENUM_TIMEFRAMES tf)
  {
   double fvgTop = 0.0, fvgBottom = 0.0;
   bool isBull = false;
   if(!IsFVGValidFromRates(rates, copied, shift, tf, fvgTop, fvgBottom, isBull))
      return false;
   return IsFVGStructureQualified(tf, rates[shift].time, fvgBottom, fvgTop);
  }

// Gate POI-entry: true = FVG ini boleh dipakai sebagai zona/varian entry
// (FVG_50 / hasFVG pada POI). false = FVG tidak diangkat jadi POI entry;
// OB di timeframe yang sama tetap boleh hidup tanpa FVG.
bool IsFVGValidWithStructure(int shift, ENUM_TIMEFRAMES tf)
  {
   double fvgTop = 0.0, fvgBottom = 0.0;
   bool isBull = false;
   if(!IsFVGValid(shift, tf, fvgTop, fvgBottom, isBull))
      return false;
   string symbol = (g_fvgVal.symbol == "") ? Symbol() : g_fvgVal.symbol;
   datetime formationTime = iTime(symbol, tf, shift);
   return formationTime > 0 && IsFVGStructureQualified(tf, formationTime, fvgBottom, fvgTop);
  }

#endif // YANSTD_FVG_VALIDATOR_MQH
