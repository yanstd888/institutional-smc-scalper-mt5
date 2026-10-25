//+------------------------------------------------------------------+
//|                                                    Defines.mqh   |
//|                    YANSTD EA — Common Structures & Enumerations  |
//|                                    v4.47.14 |  2026-09-13        |
//+------------------------------------------------------------------+
#ifndef YANSTD_DEFINES_MQH
#define YANSTD_DEFINES_MQH

//--- EA Identity
// Runtime/dashboard source of truth. Tools/Sync-Version.ps1 keeps the literal
// #property fields required by MQL5 synchronized before compilation.
#define YANSTD_NAME      "YANSTD"
#define YANSTD_VERSION   "4.52.0"
#define YANSTD_PREFIX    "YANSTD_"
#define YANSTD_HARD_MIN_LOT 0.01
#define YANSTD_EMERGENCY_STRUCTURAL_RR 4.0

//--- Absolute lot policy ceiling (set from InpMaxLot in OnInit; 0 = disabled).
// Applied BEFORE the broker's SYMBOL_VOLUME_MAX so an over-sized risk request is
// capped by operator policy rather than silently absorbed by the broker limit.
double g_maxLotCap          = 0.0;
long   g_lotPolicyCapCount  = 0;   // times InpMaxLot reduced a requested volume
long   g_lotMaxClampCount   = 0;   // times SYMBOL_VOLUME_MAX reduced a volume

double EffectiveBrokerMinLot(const string symbol)
  {
   string sym = (symbol == NULL || symbol == "") ? Symbol() : symbol;
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(minL <= 0.0)
      minL = YANSTD_HARD_MIN_LOT;
   if(minL < YANSTD_HARD_MIN_LOT)
      minL = YANSTD_HARD_MIN_LOT;
   return minL;
  }

double EffectiveBrokerLotStep(const string symbol)
  {
   string sym = (symbol == NULL || symbol == "") ? Symbol() : symbol;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = YANSTD_HARD_MIN_LOT;
   return step;
  }

// Clamp a positive calculated volume to broker min, max, and step.
// Zero/negative stays zero so a structurally invalid setup is not opened.
// Name covers both bounds — the historical alias EnforceBrokerMinLot remains.
double NormalizeLotToBrokerLimits(double lot, const string symbol)
  {
   if(lot <= 0.0)
      return lot;
   string sym = (symbol == NULL || symbol == "") ? Symbol() : symbol;
   double minL = EffectiveBrokerMinLot(sym);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = EffectiveBrokerLotStep(sym);
   if(lot < minL)
      lot = minL;
   if(step > 0.0)
     {
      lot = MathRound((lot + 1e-12) / step) * step;
      if(lot < minL)
         lot = MathCeil(minL / step - 1e-12) * step;
      if(lot < minL)
         lot = minL;
     }
   // Policy ceiling (InpMaxLot) — applied BEFORE the broker max so an oversized
   // request is capped by the operator's limit AND counted, instead of being
   // silently absorbed by SYMBOL_VOLUME_MAX below (the Gen-7 hard defect).
   if(g_maxLotCap > 0.0 && g_maxLotCap >= minL && lot > g_maxLotCap)
     {
      lot = g_maxLotCap;
      if(step > 0.0)
         lot = MathFloor((lot + 1e-12) / step) * step;
      if(lot < minL)
         lot = minL;
      g_lotPolicyCapCount++;
     }
   // Broker ceiling — previously silent; now counted so a max-clamp can never
   // hide behind a `LOT_CLAMP / LOT_FALLBACK : 0 / 0` report again.
   if(maxL > 0.0 && lot > maxL)
     {
      lot = maxL;
      g_lotMaxClampCount++;
     }
   return NormalizeDouble(lot, 8);
  }

double EnforceBrokerMinLot(double lot, const string symbol)
  {
   return NormalizeLotToBrokerLimits(lot, symbol);
  }

//--- Array Limits
#define MAX_ZONES        300
#define MSNR_MAX_ZONES   200   // CMSNREngine zone + Layer-2 cache capacity
#define MAX_FVGS         300
#define MAX_NEWS         30
#define MAX_POSITIONS    10
#define ENTRY_VARIANT_COUNT 6          // OB15 + OB45 + FVG50 + 3 Fib entry IDs
#define MATRIX_MAX_CANDIDATE_COUNT 6

bool g_pushAlertsEnabled = false;
void ConfigurePushAlerts(const bool enabled) { g_pushAlertsEnabled = enabled; }
#define YANSTD_ALERT_TABLE_MAX 64
void SendCriticalAlert(const string key, const string message, const int cooldownSeconds = 300)
  {
   if(!g_pushAlertsEnabled || MQLInfoInteger(MQL_TESTER)) return;
   static string keys[];
   static datetime sentAt[];
   int slot = -1;
   for(int i = 0; i < ArraySize(keys); i++)
      if(keys[i] == key) { slot = i; break; }
   if(slot < 0)
     {
      // AUDIT FIX M-2: cap the throttle table; evict the oldest-fired slot
      // instead of growing linearly with unique per-ticket keys.
      if(ArraySize(keys) >= YANSTD_ALERT_TABLE_MAX)
        {
         int oldest = 0;
         for(int i = 1; i < ArraySize(sentAt); i++)
            if(sentAt[i] < sentAt[oldest]) oldest = i;
         slot = oldest;
        }
      else
        {
         slot = ArraySize(keys);
         if(ArrayResize(keys, slot + 1, 8) != slot + 1 ||
            ArrayResize(sentAt, slot + 1, 8) != slot + 1) return;
        }
      keys[slot] = key;
      sentAt[slot] = 0;
     }
   datetime now = TimeCurrent();
   if(sentAt[slot] > 0 && now - sentAt[slot] < cooldownSeconds) return;
   sentAt[slot] = now;
   string payload = StringFormat("YANSTD %I64d %s: %s",
                                 AccountInfoInteger(ACCOUNT_LOGIN), Symbol(), message);
   if(StringLen(payload) > 255) payload = StringSubstr(payload, 0, 255);
   ResetLastError();
   if(!SendNotification(payload))
      Print("[YANSTD ALERT] Push notification failed | key=", key,
            " error=", GetLastError(), " message=", message);
  }

double GetPipFactor(string symbol = NULL)
  {
   static string s_sym[];
   static double s_factor[];

   string sym = (symbol == NULL || symbol == "") ? Symbol() : symbol;

   int n = ArraySize(s_sym);
   for(int i = 0; i < n; i++)
      if(s_sym[i] == sym)
         return s_factor[i];

   double factor = 1.0;
   double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0)
     {
      // Symbol data not ready yet: return the neutral factor WITHOUT caching it,
      // so a later call can still resolve the real value once the symbol is
      // fully selected in Market Watch.
      return 1.0;
     }

   string upper = sym;
   StringToUpper(upper);
   if(StringFind(upper, "XAU") >= 0 || StringFind(upper, "GOLD") >= 0)
      factor = 0.1 / point;
   else
     {
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      factor = (digits == 3 || digits == 5) ? 10.0 : 1.0;
     }

   if(ArrayResize(s_sym, n + 1) == n + 1 && ArrayResize(s_factor, n + 1) == n + 1)
     {
      s_sym[n]    = sym;
      s_factor[n] = factor;
     }
   return factor;
  }

// rates[] must be AS_SERIES (index 1 = newest closed bar). Walk from the
// oldest loaded bar toward index 1 so consecutive closes are evaluated in
// chronological order. A wick through the edge does not invalidate a zone.
bool ZoneInvalidatedByClosedBars(const MqlRates &rates[], const int copied,
                                 const datetime formationTime, const bool demand,
                                 const double zoneBottom, const double zoneTop,
                                 const int requiredCloses, const double bufferPrice)
  {
   if(copied <= requiredCloses || requiredCloses < 1 || zoneTop <= zoneBottom)
      return false;
   int consecutive = 0;
   for(int i = copied - 1; i >= 1; i--)
     {
      if(rates[i].time <= formationTime) continue;
      bool beyond = demand ? (rates[i].close < zoneBottom - bufferPrice)
                           : (rates[i].close > zoneTop + bufferPrice);
      consecutive = beyond ? consecutive + 1 : 0;
      if(consecutive >= requiredCloses) return true;
     }
   return false;
  }

// Depth of FVG consumption on closed bars after the gap candle (shift of C3).
// 0.0 = untouched, 0.50 = CE, 1.0 = full fill. Bull fill is measured from the
// top of the gap downward; bear fill from the bottom upward.
double FVGFillRatio(const bool isBull, const double fvgTop, const double fvgBottom,
                    const MqlRates &rates[], const int copied, const int startShift)
  {
   if(copied < 2 || startShift < 1 || fvgTop <= fvgBottom)
      return 0.0;
   const double width = fvgTop - fvgBottom;
   double extreme = isBull ? fvgTop : fvgBottom;
   const int last = MathMin(startShift, copied - 1);
   for(int k = last; k >= 1; k--)
     {
      if(isBull)
        {
         if(rates[k].low < extreme) extreme = rates[k].low;
         if(extreme <= fvgBottom) return 1.0;
        }
      else
        {
         if(rates[k].high > extreme) extreme = rates[k].high;
         if(extreme >= fvgTop) return 1.0;
        }
     }
   if(isBull)
      return MathMax(0.0, MathMin(1.0, (fvgTop - extreme) / width));
   return MathMax(0.0, MathMin(1.0, (extreme - fvgBottom) / width));
  }

void WarnATRFallback(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const string why)
  {
   if(symbol == "" || symbol == "__RELEASE__") return;
   static string   s_key = "";
   static datetime s_bar = 0;
   datetime bar = iTime(symbol, tf, 0);
   string key = symbol + "|" + IntegerToString((int)tf) + "|" + IntegerToString(period);
   if(key == s_key && bar == s_bar) return;
   s_key = key;
   s_bar = bar;
   Print("⚠️ [YANSTD] ATR fallback active: ", symbol, " ", EnumToString(tf),
         " period=", IntegerToString(period), " — ", why,
         ". Dynamic FVG/MSNR/QML widths use pip fallback until ATR is ready.");
  }

// AUDIT FIX H-1: distinguish CopyBuffer/handle failure from a real 0.0 reading.
double ReadIndicatorValueSafe(int handle, int buffer, int shift, bool &ok)
  {
   ok = false;
   if(handle == INVALID_HANDLE) return 0.0;
   double values[1];
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1) return 0.0;
   ok = true;
   return values[0];
  }

void WarnIndicatorReadFailed(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const string why)
  {
   if(symbol == "" || symbol == "__RELEASE__") return;
   static string   s_key = "";
   static datetime s_bar = 0;
   datetime bar = iTime(symbol, tf, 0);
   string key = symbol + "|" + IntegerToString((int)tf) + "|" + IntegerToString(period) + "|" + why;
   if(key == s_key && bar == s_bar) return;
   s_key = key;
   s_bar = bar;
   Print("⚠️ [YANSTD] Indicator read failed: ", symbol, " ", EnumToString(tf),
         " period=", IntegerToString(period), " — ", why);
  }

double GetCachedATR(const string symbol, const ENUM_TIMEFRAMES tf, const int period = 14)
  {
   static string   s_sym[];
   static int      s_tf[];
   static int      s_period[];
   static int      s_handle[];
   static datetime s_bar[];
   static double   s_val[];

   if(symbol == "__RELEASE__")
     {
      int m = ArraySize(s_handle);
      for(int i = 0; i < m; i++)
        {
         if(s_handle[i] != INVALID_HANDLE)
           {
            IndicatorRelease(s_handle[i]);
            s_handle[i] = INVALID_HANDLE;
           }
        }
      ArrayFree(s_sym);    ArrayFree(s_tf);
      ArrayFree(s_period);  ArrayFree(s_handle);
      ArrayFree(s_bar);     ArrayFree(s_val);
      return 0.0;
     }

   int n = ArraySize(s_handle);
   int slot = -1;
   for(int i = 0; i < n; i++)
      if(s_handle[i] != INVALID_HANDLE && s_sym[i] == symbol &&
         s_tf[i] == (int)tf && s_period[i] == period) { slot = i; break; }

   if(slot < 0)
     {
      int h = iATR(symbol, tf, period);
      if(h == INVALID_HANDLE)
        {
         WarnATRFallback(symbol, tf, period, "iATR handle invalid");
         return 0.0;
        }
      slot = n;
      ArrayResize(s_sym,    n + 1); ArrayResize(s_tf,     n + 1);
      ArrayResize(s_period, n + 1); ArrayResize(s_handle, n + 1);
      ArrayResize(s_bar,    n + 1); ArrayResize(s_val,    n + 1);
      s_sym[slot] = symbol; s_tf[slot] = (int)tf; s_period[slot] = period;
      s_handle[slot] = h;   s_bar[slot] = 0;      s_val[slot] = 0.0;
     }

   datetime curBar = iTime(symbol, tf, 0);
   if(curBar != s_bar[slot] || s_val[slot] <= 0.0)
     {
      double buf[1];
      if(CopyBuffer(s_handle[slot], 0, 1, 1, buf) == 1 && buf[0] > 0.0)
        {
         s_val[slot] = buf[0];
         s_bar[slot] = curBar;
        }
     }
   if(s_val[slot] <= 0.0)
      WarnATRFallback(symbol, tf, period, "ATR unavailable — callers use pip fallback");
   return s_val[slot];
  }

// AUDIT FIX H1 (causal history bug): GetCachedATR() above always answers with
// the ATR of the most recently CLOSED candle (shift=1). That is correct for
// live execution filters (trailing, spread, current proximity) but wrong for
// classifying a historical FVG/OB/SNR candidate that formed at some older
// shift — using "now's" ATR to accept/reject a zone that formed weeks ago
// makes backtests non-causal and lets a rescan change old zone content.
//
// ReadATRAtShift() answers "what was ATR at this specific closed shift" and
// caches a whole contiguous buffer per (symbol,tf,period) so a scan that
// touches many candidates issues one CopyBuffer call for the run, not one
// per candidate. The buffer only grows (never truncated) within a bar and is
// refreshed once when a new bar opens, so repeated scans of the same closed
// history return identical values every time.
struct SATRShiftCache
  {
   string            symbol;
   int               tf;
   int               period;
   int               handle;
   datetime          bar0;
   double            buf[];
  };

SATRShiftCache g_atrShiftCache[];

double ReadATRAtShift(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift)
  {
   if(symbol == "__RELEASE__")
     {
      int rn = ArraySize(g_atrShiftCache);
      for(int i = 0; i < rn; i++)
         if(g_atrShiftCache[i].handle != INVALID_HANDLE)
           {
            IndicatorRelease(g_atrShiftCache[i].handle);
            g_atrShiftCache[i].handle = INVALID_HANDLE;
            ArrayFree(g_atrShiftCache[i].buf);
           }
      ArrayFree(g_atrShiftCache);
      return 0.0;
     }
   if(shift < 0 || symbol == "") return 0.0;

   int n = ArraySize(g_atrShiftCache);
   int slot = -1;
   for(int i = 0; i < n; i++)
      if(g_atrShiftCache[i].handle != INVALID_HANDLE && g_atrShiftCache[i].symbol == symbol &&
         g_atrShiftCache[i].tf == (int)tf && g_atrShiftCache[i].period == period) { slot = i; break; }

   if(slot < 0)
     {
      int h = iATR(symbol, tf, period);
      if(h == INVALID_HANDLE)
        {
         WarnATRFallback(symbol, tf, period, "iATR handle invalid (shift-read)");
         return 0.0;
        }
      slot = n;
      ArrayResize(g_atrShiftCache, n + 1);
      g_atrShiftCache[slot].symbol = symbol;
      g_atrShiftCache[slot].tf     = (int)tf;
      g_atrShiftCache[slot].period = period;
      g_atrShiftCache[slot].handle = h;
      g_atrShiftCache[slot].bar0   = 0;
      ArrayFree(g_atrShiftCache[slot].buf);
     }

   datetime curBar0 = iTime(symbol, tf, 0);
   int have = ArraySize(g_atrShiftCache[slot].buf);
   if(curBar0 != g_atrShiftCache[slot].bar0 || shift >= have)
     {
      // New bar -> old cached shifts are still valid (closed candles never
      // change), but the array is indexed relative to shift 0, so a bar
      // rollover shifts every existing index by one. Simplest correct fix is
      // a full re-copy sized to what's actually needed; CopyBuffer on a
      // history buffer is cheap relative to per-candidate calls it replaces.
      int want = MathMax(shift + 1, have);
      double tmp[];
      ArraySetAsSeries(tmp, true);
      if(CopyBuffer(g_atrShiftCache[slot].handle, 0, 0, want, tmp) == want)
        {
         ArrayResize(g_atrShiftCache[slot].buf, want);
         for(int i = 0; i < want; i++)
            g_atrShiftCache[slot].buf[i] = tmp[i];
         g_atrShiftCache[slot].bar0 = curBar0;
        }
      else
        {
         WarnIndicatorReadFailed(symbol, tf, period, "ATR shift-buffer CopyBuffer failed");
         return 0.0;
        }
     }

   if(shift >= ArraySize(g_atrShiftCache[slot].buf)) return 0.0;
   double v = g_atrShiftCache[slot].buf[shift];
   if(v <= 0.0)
      WarnATRFallback(symbol, tf, period, "ATR shift value unavailable");
   return v;
  }

void ReleaseCachedATRHandles()
  {
   GetCachedATR("__RELEASE__", PERIOD_CURRENT, 0);
   ReadATRAtShift("__RELEASE__", PERIOD_CURRENT, 0, 0);
  }

int LastSundayOfMonth(const int year, const int month)
  {
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year;
   dt.mon  = month + 1;
   dt.day  = 1;
   if(dt.mon > 12) { dt.mon = 1; dt.year++; }
   datetime firstNextMonth = StructToTime(dt);
   datetime lastDayTime = firstNextMonth - 86400;
   TimeToStruct(lastDayTime, dt);
   return dt.day - dt.day_of_week;
  }

bool IsUSDST(const datetime utc)
  {
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   if(dt.mon < 3 || dt.mon > 11) return false;
   if(dt.mon > 3 && dt.mon < 11) return true;
   MqlDateTime first;
   ZeroMemory(first);
   first.year = dt.year; first.mon = dt.mon; first.day = 1;
   TimeToStruct(StructToTime(first), first);
   int firstSunday = 1 + (7 - first.day_of_week) % 7;
   if(dt.mon == 3)
     {
      int secondSunday = firstSunday + 7;
      return (dt.day > secondSunday || (dt.day == secondSunday && dt.hour >= 7));
     }
   return (dt.day < firstSunday || (dt.day == firstSunday && dt.hour < 6));
  }

void ComputeStopBoundPips(const string symbol, const ENUM_TIMEFRAMES tf, const int atrPeriod,
                          const double pip,
                          const double pipMin, const double pipMax,
                          const bool useATR, const double atrMinMult, const double atrMaxMult,
                          double &outMinPips, double &outMaxPips)
  {
   outMinPips = pipMin;
   outMaxPips = pipMax;
   if(!useATR || pip <= 0.0) return;
   double atr = GetCachedATR(symbol, tf, (atrPeriod > 0 ? atrPeriod : 14));
   if(atr <= 0.0) return;
   double atrPips = atr / pip;
   if(atrMinMult > 0.0)
      outMinPips = MathMax(outMinPips, atrPips * atrMinMult);
   if(atrMaxMult > 0.0)
     {
      double atrMax = atrPips * atrMaxMult;
      outMaxPips = (outMaxPips > 0.0) ? MathMax(outMaxPips, atrMax) : atrMax;
     }
  }

bool StopWithinBounds(const double slP, const double minPips, const double maxPips)
  {
   return (slP > 0.0 && (minPips <= 0.0 || slP >= minPips) &&
                        (maxPips <= 0.0 || slP <= maxPips));
  }

bool ClampStopToBounds(const bool isBuy, const double entryPrice, const double pip,
                       const int digits, const double minPips, const double maxPips,
                       double &sl, double &slP)
  {
   if(pip <= 0.0 || entryPrice <= 0.0) return false;
   bool clamped = false;
   if(minPips > 0.0 && slP < minPips)
     {
      slP = minPips;
      sl  = NormalizeDouble(isBuy ? (entryPrice - slP * pip)
                                  : (entryPrice + slP * pip), digits);
      clamped = true;
     }
   if(maxPips > 0.0 && slP > maxPips)
     {
      slP = maxPips;
      sl  = NormalizeDouble(isBuy ? (entryPrice - slP * pip)
                                  : (entryPrice + slP * pip), digits);
      clamped = true;
     }
   return clamped;
  }

bool IsFractalPivot(const MqlRates &rates[], const int copied, const int i,
                    const int leftBars, const int rightBars, const bool wantHigh)
  {
   if(leftBars < 1 || rightBars < 1) return false;
   // AUDIT H3: bar 0 is the forming candle. Do not let the left wing rest on it.
   if(i - leftBars < 1) return false;
   if(i < leftBars || i + rightBars >= copied) return false;
   if(wantHigh)
     {
      const double centre = rates[i].high;
      for(int j = 1; j <= leftBars; j++)
         if(centre < rates[i - j].high) return false;
      for(int j = 1; j <= rightBars; j++)
         if(centre < rates[i + j].high) return false;
      return true;
     }
   const double centre = rates[i].low;
   if(centre <= 0.0) return false;
   for(int j = 1; j <= leftBars; j++)
      if(centre > rates[i - j].low) return false;
   for(int j = 1; j <= rightBars; j++)
      if(centre > rates[i + j].low) return false;
   return true;
  }

bool PairFormationSwingLeg(const MqlRates &rates[], const int copied,
                           const int startIndex, const int span,
                           const int halfDepth, double &swingHigh, double &swingLow)
  {
   swingHigh = 0.0;
   swingLow  = 0.0;
   if(halfDepth < 2 || span <= halfDepth * 2) return false;
   int first = -1;
   bool firstIsHigh = false;
   double firstPrice = 0.0;
   const int last = MathMin(copied - halfDepth - 1, startIndex + span - 1);
   for(int b = startIndex + halfDepth; b <= last; b++)
     {
      const bool isHigh = IsFractalPivot(rates, copied, b, halfDepth, halfDepth, true);
      const bool isLow  = IsFractalPivot(rates, copied, b, halfDepth, halfDepth, false);
      if(!isHigh && !isLow) continue;
      if(isHigh && isLow) continue;
      if(first < 0)
        {
         first = b;
         firstIsHigh = isHigh;
         firstPrice = isHigh ? rates[b].high : rates[b].low;
         continue;
        }
      if(firstIsHigh)
        {
         if(isHigh) return false;
         swingHigh = firstPrice;
         swingLow  = rates[b].low;
         return (swingHigh > swingLow && swingLow > 0.0);
        }
      if(isLow) return false;
      swingLow  = firstPrice;
      swingHigh = rates[b].high;
      return (swingHigh > swingLow && swingLow > 0.0);
     }
   return false;
  }

// Build a dealing range using information that was already confirmed when a
// zone formed. No bar newer than formationTime may participate, preventing a
// historical POI from being reclassified with future/current swings.
bool GetFormationDealingRange(string symbol, ENUM_TIMEFRAMES tf, datetime formationTime,
                              int pivotDepth, int lookbackBars,
                              double &swingHigh, double &swingLow)
  {
   swingHigh = 0.0;
   swingLow  = 0.0;
   if(formationTime <= 0) return false;

   int formationShift = iBarShift(symbol, tf, formationTime, false);
   int totalBars = Bars(symbol, tf);
   if(formationShift < 0 || totalBars <= formationShift + 5) return false;

   int halfDepth = MathMax(2, pivotDepth / 2);
   int requested = MathMin(MathMax(30, lookbackBars), totalBars - formationShift - 1);
   MqlRates history[];
   ArraySetAsSeries(history, true);
   int copied = CopyRates(symbol, tf, formationShift + 1, requested, history);
   if(copied < halfDepth * 2 + 5) return false;
   return PairFormationSwingLeg(history, copied, 0, copied, halfDepth, swingHigh, swingLow);
  }
//==========================================================================
//  ENUMERATIONS
//==========================================================================

enum ENUM_ZONE_TYPE
  {
   ZONE_DEMAND = 0,
   ZONE_SUPPLY = 1
  };

enum ENUM_ZONE_STATUS
  {
   ZONE_FRESH     = 0,
   ZONE_PARTIAL   = 1,
   ZONE_MITIGATED = 2
  };

// Legacy aliases used by some modules
#define STATUS_FRESH      ZONE_FRESH
#define STATUS_PARTIAL    ZONE_PARTIAL
#define STATUS_MITIGATED  ZONE_MITIGATED

enum ENUM_FVG_TYPE
  {
   FVG_BULLISH = 0,
   FVG_BEARISH = 1
  };

enum ENUM_SIGNAL_TYPE
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

enum ENUM_SESSION_TYPE
  {
   SESSION_NONE    = 0,
   SESSION_ASIA    = 1,
   SESSION_LONDON  = 2,
   SESSION_NEWYORK = 3,
   SESSION_OVERLAP = 4,
   SESSION_UNKNOWN = 5,
   SESSION_LONDON_KZ = 6,
   SESSION_NY_KZ = 7
  };

enum ENUM_TREND_BIAS
  {
   BIAS_STRONG_BEAR = 0,
   BIAS_BEAR        = 1,
   BIAS_NEUTRAL     = 2,
   BIAS_BULL        = 3,
   BIAS_STRONG_BULL = 4
  };

enum ENUM_NEWS_STATUS
  {
   NEWS_CLEAR   = 0,
   NEWS_WARNING = 1,
   NEWS_LIVE    = 2,
   NEWS_COOLING = 3,
   NEWS_ERROR   = 4
  };

enum ENUM_NEWS_POSITION_ACTION
  {
   NEWS_POSITION_HOLD          = 0,
   NEWS_POSITION_PARTIAL_CLOSE = 1,
   NEWS_POSITION_CLOSE_ALL     = 2
  };

// Diagnostic rejection funnel.  Counters represent unique candidate/bar
// rejections rather than raw ticks, so tester percentages remain meaningful.
enum ENUM_SIGNAL_REJECT_REASON
  {
   REJECT_NO_ACTIVE_POI = 0,
   REJECT_SPREAD,
   REJECT_SPREAD_ATR,
   REJECT_ADX_GUARD,
   REJECT_MIN_RRR,
   REJECT_SL_OUT_OF_RANGE,
   REJECT_DATA_UNAVAILABLE,
   REJECT_DIRECTION_BIAS,
   REJECT_MSNR_ZONE,
   REJECT_MSNR_FVG,
   REJECT_SOFT_SCORE,
   REJECT_POI_INVALIDATED,
   REJECT_INDUCEMENT_PENALTY,
   REJECT_NOT_IN_POI,
   REJECT_CHOCH_NOT_CONFIRMED,
   REJECT_CHOCH_TIMEOUT,
   REJECT_SWEEP_NOT_CONFIRMED, // v4.34: joint M3 sweep+CHoCH gate (InpRequireM3Sweep)
   REJECT_OB_NO_FVG,          // v4.35: M3 base is not a real OB (no displacement FVG + sweep candle)
   REJECT_M3_OUTSIDE_PARENT_ZONE, // v4.35: refined M3 OB/FVG not contained in parent M5 POI
   REJECT_LAYER_DUPLICATE,
   REJECT_POSITION_LIMIT,
   REJECT_DISTANCE,
   REJECT_TIME_FILTER,
   REJECT_DAILY_LOSS,
   REJECT_NEWS,
   REJECT_AGGREGATE_RISK,
   REJECT_PENDING_LIMIT,
   REJECT_ORDER_SEND,
   REJECT_MARGIN_LEVEL,       // Fix R1: blocked by account-wide margin-level circuit breaker
   REJECT_LOT_TOO_SMALL,      // LOW: risk-based lot below broker minimum (was logged as aggregate-risk 100%)
   REJECT_SL_BELOW_MIN,       // H1: structural stop tighter than InpMinSLPips and policy=SKIP
   REJECT_SL_ABOVE_MAX,       // structural stop wider than maximum when a rejecting policy is selected
   REJECT_VARIANT_NOT_ALLOWED,// H2: mitigation variant not in the operator whitelist
   REJECT_CLUSTER_TOO_CLOSE,  // H2/H8: sibling order inside the minimum correlation distance
   REJECT_ENTRY_TOO_FAR,      // M5: limit further than InpMaxEntryDistanceATR x ATR
   REJECT_POI_STALE,          // M6: POI older than the configured age limit
   REJECT_SUNDAY_OPEN,        // M2: blocked inside the Sunday re-open gap window
   REJECT_EQUITY_DD,          // L2: equity drawdown circuit breaker tripped
   REJECT_SETUP_GRADE,        // v4.41: D+/D setup grade is not tradeable
   REJECT_GAP_PAUSE,          // v4.46: unexpected data-gap cool-down
   REJECT_ADX_SOFT_PENALTY,   // v4.47.4: ADX < MinADX applied as score penalty only
   REJECT_NOT_IN_KILLZONE,       // Killzone gate: entry outside London/NY killzone
   REJECT_NOT_FRESH,             // MSNR fresh status gate: zone not virgin/single-touch
   REJECT_ENTRY_STOPS_DISTANCE,  // v4.47.16: SL/TP closer than stops/freeze+spread (pre-send guard)
   REJECT_REENTRY_COOLDOWN,      // Gen-6C M1: same-direction re-entry inside the cooldown window
   SIGNAL_REJECT_REASON_COUNT
  };

enum ENUM_AUTO_MODE
  {
   AUTO_OFF = 0,
   AUTO_ON  = 1
  };

// Policy for a natural structural stop wider than InpMaxSLPips. The active
// user policy is HARD_CAP: keep the entry and execute at the configured ceiling.
enum ENUM_WIDE_SL_POLICY
  {
   WIDE_SL_REQUIRE_REFINEMENT = 0, // reject if no <= max-SL sub-node exists
   WIDE_SL_HARD_CAP           = 1, // active: cap SL at InpMaxSLPips and keep entry
   WIDE_SL_SKIP               = 2  // optional: reject the setup
  };

enum ENUM_NARROW_SL_POLICY
  {
   NARROW_SL_SKIP  = 0, // H1 default: reject the setup, never widen the stop
   NARROW_SL_WIDEN = 1  // legacy: widen to InpMinSLPips (fabricates R)
  };

enum ENUM_BRAIN_TEST_SOURCE
  {
   BRAIN_TEST_REALTICK = 0,
   BRAIN_TEST_OHLC     = 1
  };

enum ENUM_TESTER_EXECUTION_MODE
  {
   TESTER_MATRIX_COLLECTION = 0, // fan out up to 6 active candidates; exploration stats only
   TESTER_LIVE_STRICT       = 1, // single best entry; brain read-only by default
   TESTER_MATRIX_OFF        = 2  // H8 default: single best entry, brain learns normally
  };

// Exit contract selected before entry. FIXED_RR uses one broker-side TP and
// does not require a volume split; STAGED retains TP1/TP2/runner management.
enum ENUM_EXIT_MODE
  {
   EXIT_STAGED          = 0,
   EXIT_FIXED_RR        = 1,
   EXIT_STRUCTURAL_POI  = 2  // broker TP = M15 opposing MSNR; optional 50% at +80 pips
  };

enum ENUM_LOG_LEVEL
  {
   LOG_LEVEL_ERROR = 0,
   LOG_LEVEL_WARN  = 1,
   LOG_LEVEL_INFO  = 2,
   LOG_LEVEL_DEBUG = 3
  };

enum ENUM_TARGET_SOURCE
  {
   TARGET_NONE              = 0,
   TARGET_PERSISTED         = 1,
   TARGET_RECALCULATED_MSNR = 2,
   TARGET_M15_SWING         = 3,
   TARGET_EMERGENCY_RR      = 4
  };

enum ENUM_LOT_SIZE_STATUS
  {
   LOT_STATUS_OK       = 0,
   LOT_STATUS_CLAMP    = 1,
   LOT_STATUS_FALLBACK = 2,
   LOT_STATUS_INVALID  = 3
  };

enum ENUM_DATA_GAP_KIND
  {
   DATA_GAP_NONE                 = 0,
   DATA_GAP_UNEXPECTED           = 1,
   DATA_GAP_NORMAL_SESSION_BREAK = 2,
   DATA_GAP_WEEKEND_OR_HOLIDAY   = 3
  };

enum ENUM_TIME_FILTER_MODE
  {
   TIME_FILTER_WINDOW        = 0, // [startHour, endHour) UTC
   TIME_FILTER_ROLLOVER_HOLE = 1  // all hours except [holeStart, holeEnd) UTC
  };

string TargetSourceLabel(const ENUM_TARGET_SOURCE src)
  {
   switch(src)
     {
      case TARGET_PERSISTED:         return "PERSISTED";
      case TARGET_RECALCULATED_MSNR: return "RECALCULATED_MSNR";
      case TARGET_M15_SWING:         return "M15_SWING";
      case TARGET_EMERGENCY_RR:      return "EMERGENCY_RR";
      default:                       return "NONE";
     }
  }

string DataGapKindLabel(const ENUM_DATA_GAP_KIND kind)
  {
   switch(kind)
     {
      case DATA_GAP_UNEXPECTED:           return "UNEXPECTED_DATA_GAP";
      case DATA_GAP_NORMAL_SESSION_BREAK: return "NORMAL_SESSION_BREAK";
      case DATA_GAP_WEEKEND_OR_HOLIDAY:   return "WEEKEND_OR_HOLIDAY";
      default:                            return "NONE";
     }
  }

bool TargetPriceValid(const double entryPrice, const bool isBuy, const double target)
  {
   if(target <= 0.0 || entryPrice <= 0.0) return false;
   return isBuy ? (target > entryPrice) : (target < entryPrice);
  }

double EmergencyStructuralTarget(const double entryPrice, const bool isBuy,
                                 const double slDistance)
  {
   if(entryPrice <= 0.0 || slDistance <= 0.0) return 0.0;
   return isBuy ? (entryPrice + slDistance * YANSTD_EMERGENCY_STRUCTURAL_RR)
                : (entryPrice - slDistance * YANSTD_EMERGENCY_STRUCTURAL_RR);
  }

// Pure helpers used by unit tests to lock BUY/SELL geometric symmetry.
double MirrorDemandToSupplyPrice(const double high, const double low, const double demandPrice)
  {
   return high + low - demandPrice;
  }

double StructuralSLPrice(const double entryPrice, const bool isBuy,
                         const double structureExtreme, const double bufferPrice)
  {
   if(isBuy)
      return structureExtreme - bufferPrice;
   return structureExtreme + bufferPrice;
  }

double StructuralTPPrice(const double entryPrice, const bool isBuy, const double opposingExtreme)
  {
   if(isBuy)
      return (opposingExtreme > entryPrice) ? opposingExtreme : 0.0;
   return (opposingExtreme > 0.0 && opposingExtreme < entryPrice) ? opposingExtreme : 0.0;
  }

bool SymbolSessionOpenAt(const string symbol, const datetime t)
  {
   if(t <= 0) return false;
   MqlDateTime dt;
   TimeToStruct(t, dt);
   ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   const int secondsInDay = dt.hour * 3600 + dt.min * 60 + dt.sec;
   datetime from = 0, to = 0;
   for(int session = 0; session < 8; session++)
     {
      if(!SymbolInfoSessionTrade(symbol, dow, session, from, to))
         break;
      int fromSec = (int)from;
      int toSec   = (int)to;
      if(toSec > fromSec && secondsInDay >= fromSec && secondsInDay < toSec)
         return true;
      // For an overnight session, the part before midnight belongs to this
      // weekday; the part after midnight is checked against the prior day.
      if(toSec <= fromSec && secondsInDay >= fromSec)
         return true;
     }
   ENUM_DAY_OF_WEEK prevDow = (ENUM_DAY_OF_WEEK)((dt.day_of_week + 6) % 7);
   for(int session = 0; session < 8; session++)
     {
      if(!SymbolInfoSessionTrade(symbol, prevDow, session, from, to))
         break;
      int fromSec = (int)from;
      int toSec   = (int)to;
      if(toSec <= fromSec && secondsInDay < toSec)
         return true;
     }
   return false;
  }

ENUM_DATA_GAP_KIND ClassifyBarGap(const string symbol, const datetime prevBar,
                                  const datetime nextBar)
  {
   if(prevBar <= 0 || nextBar <= prevBar)
      return DATA_GAP_NONE;

   MqlDateTime a, b;
   TimeToStruct(prevBar, a);
   TimeToStruct(nextBar, b);
   const int spanDays = (int)((nextBar - prevBar) / 86400);
   if(spanDays >= 2)
      return DATA_GAP_WEEKEND_OR_HOLIDAY;

   bool anySessionSample = false;
   bool anyClosedSample  = false;
   const int step = 300;
   for(datetime cursor = prevBar + step; cursor < nextBar; cursor += step)
     {
      if(SymbolSessionOpenAt(symbol, cursor))
         anySessionSample = true;
      else
         anyClosedSample = true;
     }
   if(!anySessionSample)
      return anyClosedSample ? DATA_GAP_NORMAL_SESSION_BREAK : DATA_GAP_WEEKEND_OR_HOLIDAY;
   if(anyClosedSample && !SymbolSessionOpenAt(symbol, prevBar + 60) &&
      !SymbolSessionOpenAt(symbol, nextBar - 60))
      return DATA_GAP_NORMAL_SESSION_BREAK;
   return DATA_GAP_UNEXPECTED;
  }

// Modules cannot read the EA's input variables, so the log level is pushed
// into this global from OnInit(). Declared here (single translation unit) so
// every module can consult it without wiring an extra setter through each one.
int g_logLevel = LOG_LEVEL_INFO;

// When true, an entry whose volume is too small to honour the staged
// TP1/TP2/runner split is still allowed as a SINGLE-exit trade instead of
// being rejected outright. Without this, every 0.01-lot position (small
// accounts, collection/matrix research mode) was refused at the entry gate.
bool g_allowSingleExitBelowRunnerMin = true;

bool LogEnabled(int level)
  {
   return (level <= g_logLevel);
  }

void LogMsg(int level, string tag, string message)
  {
   if(!LogEnabled(level)) return;
   switch(level)
     {
      case LOG_LEVEL_ERROR: Print("🚨 [YANSTD ERROR] [", tag, "] ", message); break;
      case LOG_LEVEL_WARN:  Print("⚠️ [YANSTD WARN]  [", tag, "] ", message); break;
      case LOG_LEVEL_DEBUG: Print("🔍 [YANSTD DEBUG] [", tag, "] ", message); break;
      default:              Print("[YANSTD] [", tag, "] ", message);          break;
     }
  }

// Generic per-tag journal throttle. Matrix / collection / tester runs can
// evaluate the same reject path hundreds of times without a new direction,
// and a raw Print/LogMsg there floods the journal and slows the tester.
// Timestamps are kept in a small static table keyed by tag (not by message),
// so two different RISK_GUARD texts still share one interval.
#define LOG_THROTTLE_SLOTS 24
void LogThrottled(string tag, int minIntervalSec, string message, int level = LOG_LEVEL_WARN)
  {
   if(!LogEnabled(level)) return;
   if(minIntervalSec < 0) minIntervalSec = 0;

   static string   s_tag[LOG_THROTTLE_SLOTS];
   static datetime s_last[LOG_THROTTLE_SLOTS];
   static int      s_used = 0;

   datetime now = TimeCurrent();
   int slot = -1;
   for(int i = 0; i < s_used; i++)
      if(s_tag[i] == tag) { slot = i; break; }

   if(slot < 0)
     {
      if(s_used < LOG_THROTTLE_SLOTS)
        {
         slot = s_used;
         s_tag[slot] = tag;
         s_last[slot] = 0;
         s_used++;
        }
      else
        {
         slot = 0;
         datetime oldest = s_last[0];
         for(int i = 1; i < LOG_THROTTLE_SLOTS; i++)
            if(s_last[i] < oldest) { oldest = s_last[i]; slot = i; }
         s_tag[slot] = tag;
         s_last[slot] = 0;
        }
     }

   if(s_last[slot] != 0 && (now - s_last[slot]) < minIntervalSec)
      return;
   s_last[slot] = now;
   LogMsg(level, tag, message);
  }

enum ENUM_STRUCTURE_EVENT
  {
   STRUCTURE_EVENT_NONE       = 0,
   STRUCTURE_BOS_BULLISH      = 1,
   STRUCTURE_BOS_BEARISH      = 2,
   STRUCTURE_CHOCH_BULLISH    = 3,
   STRUCTURE_CHOCH_BEARISH    = 4
  };

#define YANSTD_STRUCT_EVENT_MAX 8
#define YANSTD_STRUCT_EVENT_TTL_BARS 20
struct SStructureEvent
  {
   ENUM_STRUCTURE_EVENT evt;
   datetime             barTime;
   double               level;
  };

void StructureEventsPush(SStructureEvent &buf[], int &count, const SStructureEvent &event)
  {
   for(int i=0; i<count; i++)
      if(buf[i].evt==event.evt && buf[i].barTime==event.barTime) return;
   if(ArraySize(buf)<YANSTD_STRUCT_EVENT_MAX) ArrayResize(buf,YANSTD_STRUCT_EVENT_MAX);
   if(count<YANSTD_STRUCT_EVENT_MAX) buf[count++]=event;
   else
     {
      for(int i=1;i<YANSTD_STRUCT_EVENT_MAX;i++) buf[i-1]=buf[i];
      buf[YANSTD_STRUCT_EVENT_MAX-1]=event;
     }
  }

int StructureEventsActive(const SStructureEvent &buf[], const int count, SStructureEvent &out[],
                          const datetime now, const int tfSeconds)
  {
   ArrayResize(out,YANSTD_STRUCT_EVENT_MAX);
   int n=0;
   datetime ttl=(datetime)(MathMax(1,tfSeconds)*YANSTD_STRUCT_EVENT_TTL_BARS);
   for(int i=MathMin(count,YANSTD_STRUCT_EVENT_MAX)-1;i>=0;i--)
      if(buf[i].evt!=STRUCTURE_EVENT_NONE && buf[i].barTime>0 && now-buf[i].barTime<=ttl) out[n++]=buf[i];
   ArrayResize(out,n);
   return n;
  }

string StructureEventLabel(const ENUM_STRUCTURE_EVENT evt)
  {
   switch(evt)
     {
      case STRUCTURE_BOS_BULLISH: return "BOS BULLISH";
      case STRUCTURE_BOS_BEARISH: return "BOS BEARISH";
      case STRUCTURE_CHOCH_BULLISH: return "CHoCH BULLISH";
      case STRUCTURE_CHOCH_BEARISH: return "CHoCH BEARISH";
      default: return "STRUCTURE NONE";
     }
  }

enum ENUM_OB_COLOR
  {
   OB_COLOR_UNKNOWN=0,
   OB_COLOR_OPPOSITE=1,
   OB_COLOR_SAME=2,
   OB_COLOR_DOJI=3
  };

string OBColorLabel(const ENUM_OB_COLOR value)
  {
   switch(value) { case OB_COLOR_OPPOSITE:return "OPPOSITE"; case OB_COLOR_SAME:return "SAME"; case OB_COLOR_DOJI:return "DOJI"; default:return "UNKNOWN"; }
  };

ENUM_OB_COLOR ClassifyOBColor(const bool demand,const double open,const double close)
  {
   if(close==open) return OB_COLOR_DOJI;
   return ((demand && close<open)||(!demand && close>open)) ? OB_COLOR_OPPOSITE : OB_COLOR_SAME;
  };

//--- MSNR Zone Types
enum ENUM_MSNR_ZONE_TYPE
  {
   MSNR_ZONE_NONE         = 0,
   // [DEPRECATED — never assigned by AddZone(); kept so MsnrIsDemand/MsnrIsSupply
   // stay binary-stable. See MSNREngine.mqh ScanQML AUDIT FIX #5]
   MSNR_FRESH_DEMAND      = 1,
   MSNR_FRESH_SUPPLY      = 2,
   MSNR_PARTIAL_DEMAND    = 3,
   MSNR_PARTIAL_SUPPLY    = 4,
   MSNR_QML_BUY          = 5,  // Quasimodo Left Shoulder BUY zone
   MSNR_QML_SELL         = 6,  // Quasimodo Left Shoulder SELL zone
   MSNR_KING_SUPPORT     = 7,  // King SNR direction filter only
   MSNR_KING_RESISTANCE  = 8,
   MSNR_A_RESISTANCE     = 9,  // A-level: bullish then bearish body handover
   MSNR_V_SUPPORT        = 10, // V-level: bearish then bullish body handover
   MSNR_OCL_DEMAND       = 11, // Bullish gap / open-close level
   MSNR_OCL_SUPPLY       = 12, // Bearish gap / open-close level
   MSNR_RBS              = 13, // Resistance became support (close through A/OCL supply)
   MSNR_SBR              = 14  // Support became resistance (close through V/OCL demand)
  };

bool MsnrIsDemand(const ENUM_MSNR_ZONE_TYPE t)
  {
   return (t == MSNR_FRESH_DEMAND || t == MSNR_PARTIAL_DEMAND ||
           t == MSNR_QML_BUY || t == MSNR_KING_SUPPORT ||
           t == MSNR_V_SUPPORT || t == MSNR_OCL_DEMAND || t == MSNR_RBS);
  }

bool MsnrIsSupply(const ENUM_MSNR_ZONE_TYPE t)
  {
   return (t == MSNR_FRESH_SUPPLY || t == MSNR_PARTIAL_SUPPLY ||
           t == MSNR_QML_SELL || t == MSNR_KING_RESISTANCE ||
           t == MSNR_A_RESISTANCE || t == MSNR_OCL_SUPPLY || t == MSNR_SBR);
  }

bool MsnrIsKeyLevel(const ENUM_MSNR_ZONE_TYPE t)
  {
   return (t == MSNR_A_RESISTANCE || t == MSNR_V_SUPPORT ||
           t == MSNR_OCL_DEMAND || t == MSNR_OCL_SUPPLY ||
           t == MSNR_RBS || t == MSNR_SBR);
  }

bool MsnrIsQml(const ENUM_MSNR_ZONE_TYPE t)
  {
   return (t == MSNR_QML_BUY || t == MSNR_QML_SELL);
  }

// Manual SMC/MSNR traders don't count "freshness"/touch from every wick that
// clips a zone (support/resistance level, Order Block, or FVG) — a candle
// that pokes into the zone and CLOSES back on the respecting side is a
// clean, valid test. A candle that closes through to the far side is a break
// attempt, not a normal test (it is already tracked separately by each
// scanner's own consecutive-close invalidation/mitigation counter). Only a
// held-close touch should count toward touch-count/Freshness; a rejected or
// failed wick should not silently make a zone look "used up" the same way a
// real retest does. Shared by MSNREngine.mqh (SNR/QML/King levels) and
// SMCLayerM15.mqh (OB/FVG) so both layers judge "touched" the same way.
bool IsZoneHeldTouch(const bool isDemand, const MqlRates &c, const double zTop, const double zBot)
  {
   return isDemand ? (c.close >= zBot) : (c.close <= zTop);
  }

// Held retests after formationTime, oldest -> newest. Same window as
// ZoneInvalidatedByClosedBars so ScanQML does not walk the series backwards.
int CountHeldTouchesAfter(const MqlRates &rates[], const int copied,
                          const datetime formationTime, const bool demand,
                          const double zoneTop, const double zoneBottom)
  {
   if(copied < 2 || zoneTop <= zoneBottom)
      return 0;
   int touches = 0;
   bool wasInside = false;
   for(int i = copied - 1; i >= 1; i--)
     {
      if(rates[i].time <= formationTime) continue;
      bool inside = (rates[i].low <= zoneTop && rates[i].high >= zoneBottom);
      if(inside && !wasInside && IsZoneHeldTouch(demand, rates[i], zoneTop, zoneBottom))
         touches++;
      wasInside = inside;
     }
   return touches;
  }

string MsnrTypeName(const ENUM_MSNR_ZONE_TYPE t)
  {
   switch(t)
     {
      case MSNR_FRESH_DEMAND:     return "FRESH DEMAND";
      case MSNR_FRESH_SUPPLY:     return "FRESH SUPPLY";
      case MSNR_PARTIAL_DEMAND:   return "PARTIAL DEMAND";
      case MSNR_PARTIAL_SUPPLY:   return "PARTIAL SUPPLY";
      case MSNR_QML_BUY:          return "QML BUY";
      case MSNR_QML_SELL:         return "QML SELL";
      case MSNR_KING_SUPPORT:     return "KING SUPPORT";
      case MSNR_KING_RESISTANCE:  return "KING RESIST";
      case MSNR_A_RESISTANCE:     return "A-LEVEL";
      case MSNR_V_SUPPORT:        return "V-LEVEL";
      case MSNR_OCL_DEMAND:       return "OCL DEMAND";
      case MSNR_OCL_SUPPLY:       return "OCL SUPPLY";
      case MSNR_RBS:              return "RBS";
      case MSNR_SBR:              return "SBR";
      default:                    return "MSNR";
     }
  }

enum ENUM_SETUP_MODE
  {
   SETUP_SMC_PRIMARY  = 2,   // SMC execution + MSNR map as soft overlay
   SETUP_PURE_SMC     = 3    // SMC execution only; MSNR is never scanned
  };

string SetupModeName(const ENUM_SETUP_MODE m)
  {
   return (m == SETUP_PURE_SMC) ? "PURE_SMC" : "SMC_PRIMARY";
  }

// Sizing contract (recalibrated v4.48.0 from Gen-6C..6H measured expectancy —
// see YANSTD_EA_SYSTEM_GUIDE.md §56): the rung must match realised edge, not
// just classifier intent. Gen-6 core (2020–2026.08) per-position expectancy:
//   Mode 1 MSNR : S +1.36 (n=16773) | A -0.69 (n=25183) | B -1.41 (n=16262)
//   Mode 2 SMC  : S+ +2.38 | B +0.43 | A +3.10 (n=743) | A+ +0.07 | S +0.08
// Only S/S+ carried a positive edge across modes, so S is the sole 2.00x rung;
// A (expectancy ~flat to negative) drops to 1.50x and never sizes at max risk.
// S+/S = 2.00x, A+/A = 1.50x, B+/B = 1.00x, C+/C = 0.50x, D+/D = reject.
// The '+' suffix records quality/stats only — it never creates a new lot rung.
// Mode 0 emits '+' from healthyR/usableR. Mode 2 from VIRGIN vs SINGLE_TOUCH.
// Mode 1 still emits S/A/B/D only.
enum ENUM_SETUP_GRADE
  {
   GRADE_S_PLUS = 0,
   GRADE_S      = 1,
   GRADE_A_PLUS = 2,
   GRADE_A      = 3,
   GRADE_B_PLUS = 4,
   GRADE_B      = 5,
   GRADE_C_PLUS = 6,
   GRADE_C      = 7,
   GRADE_D_PLUS = 8,
   GRADE_D      = 9
  };

string SetupGradeName(const ENUM_SETUP_GRADE g)
  {
   switch(g)
     {
      case GRADE_S_PLUS: return "S+";
      case GRADE_S:      return "S";
      case GRADE_A_PLUS: return "A+";
      case GRADE_A:      return "A";
      case GRADE_B_PLUS: return "B+";
      case GRADE_B:      return "B";
      case GRADE_C_PLUS: return "C+";
      case GRADE_C:      return "C";
      case GRADE_D_PLUS: return "D+";
      default:           return "D";
     }
  }

// Single source of truth for grade → lot sizing. Max contract = 2.00x for the
// S rung only (recalibrated v4.48.0, §56). Do not hardcode this table anywhere
// else — read it via this function or MaxSetupGradeLotMultiplier() below.
double SetupGradeLotMultiplier(const ENUM_SETUP_GRADE g)
  {
   switch(g)
     {
      case GRADE_S_PLUS: return 2.00;
      case GRADE_S:      return 2.00;
      case GRADE_A_PLUS: return 1.50;
      case GRADE_A:      return 1.50;
      case GRADE_B_PLUS: return 1.00;
      case GRADE_B:      return 1.00;
      case GRADE_C_PLUS: return 0.50;
      case GRADE_C:      return 0.50;
      default:           return 0.00;
     }
  }

bool SetupGradeRejects(const ENUM_SETUP_GRADE g)
  {
   return (g == GRADE_D_PLUS || g == GRADE_D);
  }

// Derives the maximum lot multiplier by scanning all 10 ENUM_SETUP_GRADE
// values against SetupGradeLotMultiplier() — never a second hardcoded
// number. Used by the OnInit() startup log so the printed "max effective
// risk" always tracks the same table the entry pipeline actually uses.
double MaxSetupGradeLotMultiplier()
  {
   double maxMult = 0.00;
   for(int i = 0; i < 10; i++)
     {
      double mult = SetupGradeLotMultiplier((ENUM_SETUP_GRADE)i);
      if(mult > maxMult)
         maxMult = mult;
     }
   return maxMult;
  }

//--- MSNR Fresh Status (for Brain Engine scoring differentiation)
enum ENUM_MSNR_FRESH_STATUS
  {
   MSNR_VIRGIN       = 0,   // Never touched — highest quality
   MSNR_SINGLE_TOUCH = 1,   // Touched once but not closed through
   MSNR_PARTIAL      = 2    // Multiple touches, partially consumed
  };

// Mode 2 M2-β: M3 already hard. No map + not inOTE = D. No map + inOTE = C.
// Freshness matches Mode 0/1: PARTIAL confluence cannot receive S/A.
// PURE SMC: no MSNR map exists by construction, so the rungs come from the SMC
// path itself -- M15 dealing-range OTE location and M3 confirmation.
// ponytail: no FVG/freshness rung yet; add one only if this mode proves it trades.
ENUM_SETUP_GRADE ClassifySetupGradePureSMC(const bool inOTE,
                                           const bool m3Confirmed,
                                           const bool counterTrend,
                                           const int ladder)
  {
   // PURE_SMC ladder switch (runtime-selected, see SetPureLadder). Measured cohorts
   // of the 6.7y run: counterTrend C=PF 1.20 (profitable), same-dir B=PF 0.69
   // (losing), !inOTE=D rejected. Fixed-lot mode ignores grade multipliers, so
   // only the D (reject) line matters -- every rung therefore just routes to
   // tradeable vs GRADE_D.
   // ponytail: InpMinTradeGrade is a dead string input repurposed as the switch;
   // give mode 3 a dedicated enum input at the next preset-schema change.
   switch(ladder)
     {
      case 1: return counterTrend ? (m3Confirmed ? GRADE_A : GRADE_B) : GRADE_D;   // counter-only
      case 2: return counterTrend ? GRADE_C : GRADE_B;                             // no OTE veto
      case 3: return counterTrend ? (m3Confirmed ? GRADE_A : GRADE_B) : GRADE_D;   // both
      default:
        if(!inOTE)       return GRADE_D;
        if(counterTrend) return GRADE_C;
        return m3Confirmed ? GRADE_A : GRADE_B;
     }
  }

ENUM_SETUP_GRADE ClassifySetupGradeSMCPrimary(const bool hasMap,
                                              const ENUM_MSNR_ZONE_TYPE mapType,
                                              const ENUM_MSNR_FRESH_STATUS fresh,
                                              const bool inOTE,
                                              const bool kingAgainst,
                                              const bool mitigated)
  {
   if(mitigated)
      return GRADE_D;
   const bool premium = (MsnrIsQml(mapType) || mapType == MSNR_SBR || mapType == MSNR_RBS);
   const bool keyMap  = MsnrIsKeyLevel(mapType);
   const bool kingOK  = !kingAgainst;
   const bool virgin  = (fresh == MSNR_VIRGIN);
   const bool single  = (fresh == MSNR_SINGLE_TOUCH);
   if(!hasMap)
      return inOTE ? GRADE_C : GRADE_D;
   if(premium && inOTE && kingOK && virgin)
      return GRADE_S_PLUS;
   if(premium && inOTE && kingOK && single)
      return GRADE_S;
   if(keyMap && inOTE && kingOK && virgin)
      return GRADE_A_PLUS;
   if(keyMap && inOTE && kingOK && single)
      return GRADE_A;
   return GRADE_B;
  }

//==========================================================================
//  STRUCTURES
//==========================================================================

//--- SMC Swing Point structure
struct SMC_SwingPoint
  {
   double            price;
   datetime          time;
   int               bar;
   bool              isHigh;
  };

//--- SMC POI Zone structure
struct SMC_Zone
  {
   ENUM_ZONE_TYPE    type;          // ZONE_DEMAND (Bullish) or ZONE_SUPPLY (Bearish)
   double            top;           // iHigh() of M5 OB candle
   double            bottom;        // iLow() of M5 OB candle
   datetime          createTime;
   int               createBar;
   int               barAge;        // Incremented on every new M5 bar
   bool              isMitigated;   // True only after configured structural/depth invalidation
   bool              isExpired;     // True if barAge > inp_zone_max_bars
   bool              isActive;
   int               primaryMSNRZoneIdx; // cached Layer-1 match, refreshed in Phase-2
   ENUM_OB_COLOR     parentOBColor;      // provenance only; never an eligibility gate
   bool              hasFVG;
   double            fvgTop;
   double            fvgBottom;
   double            fvgMidpoint;   // Consequent Encroachment (50% FVG)
   bool              fvgMitigated;  // True if FVG has been filled/mitigated
   bool              hasPendingLimit;// True if any pending limit exists for this zone
   bool              hasPendingLayer[ENTRY_VARIANT_COUNT]; // Pending state by persisted entry-type ID
   ulong             pendingEventId[ENTRY_VARIANT_COUNT]; // Exact M3 setup identity for refined pending orders
   bool              isOTE;          // True if zone sits in configured 61.8%-86.6% OTE zone

   bool              wasTouched;     // Price has mitigated into the POI and may await LTF confirmation
   datetime          firstTouchTime; // Initial touch; CHoCH anchor if optional M3 sweep is absent
   datetime          lastTouchTime;  // Most recent POI touch used by the confirmation window
   double            touchPrice;     // Price used to classify mitigation depth at first/last touch
   bool              touchWasFVG;    // Touch originated inside the linked FVG rather than only the OB
   double            fiboSwingHigh;  // Formation-time M15 dealing-range high (never recomputed later)
   double            fiboSwingLow;   // Formation-time M15 dealing-range low (never recomputed later)
   bool              m3SweepConfirmed;// Local M3 liquidity sweep observed after zone touch
   datetime          m3SweepTime;    // Closed M3 candle that confirmed the sweep/reclaim
   double            m3SweepLevel;   // Swept local liquidity reference
   bool              hasTriggeredLayer[ENTRY_VARIANT_COUNT]; // OB/FVG/Fibonacci variant tracking by ID
   int               layerCount;     // Number of layers executed on this zone
   string            objName;
   string            fvgObjName;    // Chart object name for FVG box
   ENUM_TIMEFRAMES   tf;
   string            tfLabel;
   bool              visHasM3OB;    // Last accepted M3 OB refinement (chart only)
   bool              visHasM3FVG;
   double            visM3OBTop;
   double            visM3OBBottom;
   double            visM3FVGTop;
   double            visM3FVGBottom;
  };

//--- Fair Value Gap
struct SFVG
  {
   ENUM_FVG_TYPE     type;
   double            top;
   double            bottom;
   datetime          createTime;
   datetime          timeFormed;     // alias for compatibility
   int               createBar;
   bool              isFilled;
   ENUM_ZONE_STATUS  status;         // STATUS_FRESH / STATUS_MITIGATED
   datetime          filledTime;     // time when FVG was filled
   string            objName;
   int               linkedZoneIdx;
  };

//--- News Event
struct SNewsEvent
  {
   ulong    id;
   string   currency;
   string   name;          // short name (alias for eventName)
   string   eventName;
   datetime time;          // alias for eventTime
   datetime eventTime;
   int      importance;
   bool     isBlockingNow;
  };

enum ENUM_SMC_ENTRY_TYPE
  {
   ENTRY_TYPE_OB_15    = 0,
   ENTRY_TYPE_OB_45    = 1,
   ENTRY_TYPE_FVG_50   = 2,
   ENTRY_TYPE_FIB_618  = 3,   // minimum OTE entry
   ENTRY_TYPE_FIB_705  = 4,   // OTE sweet spot
   ENTRY_TYPE_FIB_790  = 5    // deep/extreme entry at Fib 0.786 (token kept FIB_790)
  };

//--- MSNR Zone Struct (Primary Mapping Layer)
struct SMSNR_Zone
  {
   ENUM_MSNR_ZONE_TYPE  msnrType;         // Zone type (Fresh Demand/Supply/QML)
   ENUM_MSNR_FRESH_STATUS freshStatus;    // VIRGIN / SINGLE_TOUCH / PARTIAL
   double               top;              // Zone top price
   double               bottom;          // Zone bottom price
   double               leftShoulderPrice;// QML: Left Shoulder reference price (0 if not QML)
   double               qmlHeadPrice;     // QML: pattern head (invalidation); 0 if not QML
   double               keyLevelPrice;    // A/V/OCL/SBR/RBS reference price (0 if unused)
   bool                 isKeyLevel;       // Thin MSNR body/gap/flip level (overlap gate, not containment)
   datetime             createTime;       // When zone was detected on M15
   int                  createBar;        // Bar index at detection
   int                  barAge;          // Bars since zone creation
   bool                 isActive;        // Currently tradeable
   bool                 isMitigated;     // Zone fully mitigated
   bool                 isInOTE;         // True if zone sits in configured Fibo OTE window (default 0.618-0.786)
   double               fiboSwingHigh;   // Fibo reference swing high used for OTE calc
   double               fiboSwingLow;    // Fibo reference swing low used for OTE calc
   bool                 hasFVG;          // Unmitigated FVG M15 present in/near zone
   double               fvgTop;          // Associated FVG top (0 if no FVG)
   double               fvgBottom;       // Associated FVG bottom (0 if no FVG)
   double               msnrScore;       // Quality score for Brain Engine (0-100)
   int                  touchCount;      // How many times price touched this zone
   string               objName;         // Chart object name
   string               lblName;         // Chart label object name
   bool                 isKingSNR;       // True for MSNR_KING_SUPPORT / MSNR_KING_RESISTANCE
   ENUM_TIMEFRAMES      kingSourceTF;    // HTF the King SNR pair was detected on (H4/D1); PERIOD_CURRENT otherwise
  };

double MsnrPrimaryEntryPrice(const SMSNR_Zone &z)
  {
   if(z.keyLevelPrice > 0.0)
      return z.keyLevelPrice;
   if(MsnrIsQml(z.msnrType) && z.leftShoulderPrice > 0.0)
      return z.leftShoulderPrice;
   return (z.top + z.bottom) * 0.5;
  }

//--- Layer 2 (SMC) M15 Zone Types — Order Block & Fair Value Gap only.
// Deliberately separate from SMSNR_Zone/ENUM_MSNR_ZONE_TYPE (Layer 1) so the
// MSNR + SMC method keeps its two layers coded independently.
enum ENUM_SMCM15_TYPE
  {
   SMCM15_OB_DEMAND = 0,   // Last bearish candle before an impulsive bullish M15 displacement
   SMCM15_OB_SUPPLY = 1,   // Last bullish candle before an impulsive bearish M15 displacement
   SMCM15_FVG_BULL  = 2,   // M15 imbalance: candle-1 (oldest) high < candle-3 (newest) low
   SMCM15_FVG_BEAR  = 3    // M15 imbalance: candle-1 (oldest) low > candle-3 (newest) high
  };

//--- Layer 2 (SMC) M15 Zone Struct
struct SSMCM15_Zone
  {
   ENUM_SMCM15_TYPE  type;
   double            top;
   double            bottom;
   datetime          createTime;
   int               createBar;
   int               barAge;
   bool              isMitigated;
   bool              isActive;
   int               touchCount;
   double            fillRatio;     // FVG only: 0=untouched .. 1=full fill
   ENUM_ZONE_STATUS  status;        // FRESH / PARTIAL / MITIGATED
   ENUM_OB_COLOR     obColor;       // provenance only
   string            objName;
  };



// H3-FVG (audit 2026-09-12, YANSTD_EA_SYSTEM_GUIDE.md §48 -- distinct from the
// older "AUDIT H3" pivot-wing note elsewhere in this file): FVG is mandatory
// for OB validity on M5, M15, H1, H4 and above, so a zone built on any of
// those timeframes must always classify as POI_PROFILE_OB_FVG.
// POI_PROFILE_OB_ONLY may only be reached from the M3 refinement path in
// SignalEngine.mqh (ENTRY_TYPE_OB_45 without a paired M3 FVG), where FVG
// remains optional confluence. A M5+ code path that can still produce
// POI_PROFILE_OB_ONLY has a bug, not a legitimate variant.
enum ENUM_POI_PROFILE
  {
   POI_PROFILE_OB_ONLY = 0,
   POI_PROFILE_OB_FVG  = 1
  };

enum ENUM_OB_MITIGATION
  {
   OB_MITIGATION_15 = 0,
   OB_MITIGATION_45 = 1,
   OB_MITIGATION_50 = 2
  };

enum ENUM_FVG_MITIGATION
  {
   FVG_MITIGATION_NONE = 0,
   FVG_MITIGATION_50   = 1
  };

enum ENUM_FIB_LEVEL
  {
   FIB_LEVEL_NONE = 0,
   FIB_LEVEL_618  = 1,
   FIB_LEVEL_705  = 2,
   FIB_LEVEL_790  = 3    // ratio 0.786; identifier kept for compatibility
  };

//--- Trade Signal
struct SSignal
  {
   ENUM_SIGNAL_TYPE    direction;
   int                 type;          // alias for direction (for backward compat)
   ENUM_SMC_ENTRY_TYPE entryType;     // primary discrete execution variant
   ENUM_POI_PROFILE    poiProfile;
   ENUM_OB_MITIGATION  obMitigation;
   ENUM_FVG_MITIGATION fvgMitigation;
   ENUM_FIB_LEVEL      fibLevel;
   ENUM_OB_COLOR       parentOBColor;
   ENUM_OB_COLOR       executionOBColor;
   double              entryPrice;
   double              slPrice;
   double              tp1Price;
   double              tp2Price;
   double              slPips;
   double              tp1Pips;
   double              tp2Pips;
   double              lotSize;
   double              riskPct;       // Effective Risk % used
   int                 zoneIndex;
   datetime            signalTime;
   int                 brainBucketIdx;// AI Pattern Bucket index
   double              aiConfidence;  // AI confidence score (0-100%)
   double              qualityScore;  // Combined SMC/institutional/AI soft score
   double              refinedOBTop;     // M3 OB that preceded the confirmed CHoCH
   double              refinedOBBottom;
   double              refinedFVGTop;    // M3 FVG created by the CHoCH displacement (0 if absent)
   double              refinedFVGBottom;
   double              fiboSwingHigh;    // Formation-time M15 dealing range carried into execution
   double              fiboSwingLow;
   ulong               setupEventId;     // Deterministic setup identity shared by matrix siblings
   ENUM_SETUP_GRADE    setupGrade;       // v4.41 operator grade used for lot sizing
   double              gradeLotMult;     // lot/risk multiplier from setupGrade
   bool                isValid;
   string              invalidReason;
  };

//--- Session-based Performance Stats
struct SStats
  {
   double            dailyProfit;
   double            dailyProfitPct;
   double            dailyPips;        // Multi-Currency Dashboard: pip-equivalent result, Today
   int               sessionWins;
   int               sessionLosses;
   double            sessionWinRate;   // computed: sessionWins/(sessionWins+sessionLosses)*100
   int               totalTrades;
   int               totalWins;
   double            totalWinRate;     // computed: totalWins/totalTrades*100
   double            totalProfit;
   double            totalPips;        // Multi-Currency Dashboard: pip-equivalent result, All-Time
   datetime          resetEpoch;
   ENUM_SESSION_TYPE lastSession;
  };

class CEntryVariantWhitelist
  {
private:
   bool  m_allowed[ENTRY_VARIANT_COUNT];

   int TokenToIndex(string token)
     {
      string t = token;
      StringToUpper(t);
      StringTrimLeft(t);
      StringTrimRight(t);
      if(t == "OB_15"   || t == "OB15") return (int)ENTRY_TYPE_OB_15;
      if(t == "OB_45"   || t == "OB45") return (int)ENTRY_TYPE_OB_45;
      if(t == "FVG_50"  || t == "FVG50")  return (int)ENTRY_TYPE_FVG_50;
      if(t == "FIB_618" || t == "FIB618") return (int)ENTRY_TYPE_FIB_618;
      if(t == "FIB_705" || t == "FIB705" || t == "FIB_OTE") return (int)ENTRY_TYPE_FIB_705;
      if(t == "FIB_790" || t == "FIB790" || t == "FIB_DEEP") return (int)ENTRY_TYPE_FIB_790;
      return -1;
     }

public:
                     CEntryVariantWhitelist() { AllowAll(); }

   void AllowAll()
     {
      for(int i = 0; i < ENTRY_VARIANT_COUNT; i++) m_allowed[i] = true;
     }

   void AllowNone()
     {
      for(int i = 0; i < ENTRY_VARIANT_COUNT; i++) m_allowed[i] = false;
     }

   // Returns the number of tokens successfully parsed. 0 means "nothing
   // recognised", which is treated as ALL (fail-open) so a typo cannot
   // silently disable the EA -- but it is logged as an error at init time.
   int Parse(string csvList)
     {
      AllowNone();
      string s = csvList;
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "" || s == "ALL" || s == "*")
        {
         AllowAll();
         return AllowedCount();
        }

      // Accept both comma and pipe notation. Normalise to commas first;
      // StringSplit() returning one token for a pipe-delimited list used to
      // make a valid whitelist look like one unknown token and fail open.
      StringReplace(s, "|", ",");
      string tokens[];
      int count = StringSplit(s, (ushort)',', tokens);

      int recognised = 0;
      for(int i = 0; i < count; i++)
        {
         int idx = TokenToIndex(tokens[i]);
         if(idx >= 0)
           {
            m_allowed[idx] = true;
            recognised++;
           }
        }
      if(recognised <= 0) AllowAll();
      return recognised;
     }

   bool IsAllowed(ENUM_SMC_ENTRY_TYPE variant) const
     {
      int i = (int)variant;
      return (i >= 0 && i < ENTRY_VARIANT_COUNT) ? m_allowed[i] : false;
     }

   int AllowedCount() const
     {
      int n = 0;
      for(int i = 0; i < ENTRY_VARIANT_COUNT; i++) if(m_allowed[i]) n++;
      return n;
     }

   string ToString() const
     {
      string out = "";
      string names[ENTRY_VARIANT_COUNT] = {"OB_15","OB_45","FVG_50","FIB_618","FIB_705","FIB_790"};
      for(int i = 0; i < ENTRY_VARIANT_COUNT; i++)
         if(m_allowed[i]) out += (out == "" ? "" : ",") + names[i];
      return (out == "") ? "(none)" : out;
     }
  };

//==========================================================================
//  L5 / L6 — RUN TELEMETRY ACCUMULATORS
//==========================================================================
// Every counter below exists because the audit could only infer these numbers
// by parsing a 25 MB journal after the fact. They are cheap to accumulate in
// process and turn "was this run valid?" from an afternoon of grep into one
// block of journal output at deinit.
struct STradeBucketStats
  {
   int      trades;
   int      wins;
   double   grossWin;
   double   grossLoss;
   double   netR;
   double   sumR2;      // for the standard deviation behind the confidence interval

   void     Reset() { trades = 0; wins = 0; grossWin = 0.0; grossLoss = 0.0; netR = 0.0; sumR2 = 0.0; }

   void     Add(double profit, double rMultiple)
     {
      trades++;
      netR   += rMultiple;
      sumR2  += rMultiple * rMultiple;
      if(profit > 0.0) { wins++; grossWin  += profit; }
      else             {          grossLoss -= profit; }
     }

   double   WinRate() const { return (trades > 0) ? 100.0 * (double)wins / (double)trades : 0.0; }
   double   ProfitFactor() const { return (grossLoss > 0.0) ? grossWin / grossLoss : (grossWin > 0.0 ? 999.99 : 0.0); }
   double   ExpectancyR() const { return (trades > 0) ? netR / (double)trades : 0.0; }

   // L6: standard error of the mean R, so a year with 42 trades is not read
   // with the same confidence as a year with 281.
   double   StdDevR() const
     {
      if(trades < 2) return 0.0;
      double mean = ExpectancyR();
      double variance = (sumR2 - (double)trades * mean * mean) / (double)(trades - 1);
      return (variance > 0.0) ? MathSqrt(variance) : 0.0;
     }
   double   StdErrR() const { return (trades > 0) ? StdDevR() / MathSqrt((double)trades) : 0.0; }
   // 95% CI half-width (normal approximation; n is large enough for every
   // aggregate we print, and this is a diagnostic, not a publication).
   double   CI95HalfWidth() const { return 1.96 * StdErrR(); }
  };

//--- Per-timeframe trend score
struct SMTFData
  {
   double  bullPct;
   string  label;
   color   clr;
  };

//--- Full MTF result
struct SMTFResult
  {
   SMTFData          m3;
   SMTFData          m5;
   SMTFData          m15;
   SMTFData          m30;
   SMTFData          h1;
   SMTFData          h4;
   double            confluence;   // 0-100 weighted average (primary field)
   double            bullPct;      // alias for confluence
   ENUM_TREND_BIAS   bias;
   string            biasLabel;
  };

//--- Active position tracking
struct SPositionInfo
  {
   ulong               ticket;
   string              symbol;        // symbol name
   int                 posType;       // POSITION_TYPE_BUY / POSITION_TYPE_SELL
   int                 type;          // alias for posType (backward compat)
   ENUM_SMC_ENTRY_TYPE entryType;     // primary discrete execution variant
   double              openPrice;
   double              sl;
   double              tp;
   double              lots;
   double              volume;        // alias for lots (backward compat)
   double              initialLots;   // original volume used to calculate 50/25/25 exits
   double              initialRiskPrice;// original entry-to-SL price distance
   double              initialRiskMoney;// original monetary risk for net-R calculation
   double              maxFavorableR; // maximum favorable excursion in initial-risk units
   double              maxAdverseR;   // maximum adverse excursion in initial-risk units
   double              maxSpreadPoints;// maximum observed Bid/Ask spread while position was tracked
   double              tp1CloseLots;  // volume to close at TP1
   double              tp2CloseLots;  // volume to close at TP2
   double              runnerLots;    // planned volume remaining after TP2
   bool                scaleOutEnabled;// false = close the whole position at TP1
   double              profit;
   double              tp1Level;
   double              tp2Level;
   bool                tp1Done;
   bool                tp2Done;
   datetime            tp2Time;       // confirmed time when TP2 partial close completed
   bool                bepDone;
   bool                milestoneDone; // Stage 2b: +75 pips profit lock to +45 pips
   bool                trailActive;
   int                 brainBucketIdx;// AI memory link
   datetime            openTime;
   ENUM_SETUP_GRADE    setupGrade;
  };

//==========================================================================
//  UTILITY FUNCTIONS
//==========================================================================

// Canonical market key keeps normalized XAUUSD Brain datasets portable across
// broker symbol suffixes/prefixes such as XAUUSDm, GOLD.a or mXAUUSD.
string GetCanonicalInstrumentKey(string symbol = NULL)
  {
   string sym = (symbol == NULL || symbol == "") ? Symbol() : symbol;
   string upper = sym;
   StringToUpper(upper);
   if(StringFind(upper, "XAU") >= 0 || StringFind(upper, "GOLD") >= 0)
      return "XAUUSD";

   string clean = "";
   for(int i = 0; i < StringLen(upper); i++)
     {
      ushort ch = StringGetCharacter(upper, i);
      if((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9'))
         clean += ShortToString(ch);
     }
   return (clean == "") ? "UNKNOWN" : clean;
  }

double NormalisePrice(double price, string sym = NULL)
  {
   if(sym == NULL || sym == "") sym = Symbol();
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(tick <= 0.0) return NormalizeDouble(price, digits);
   return NormalizeDouble(MathRound(price / tick) * tick, digits);
  }

double Clamp(double val, double minVal, double maxVal)
  {
   if(val < minVal) return minVal;
   if(val > maxVal) return maxVal;
   return val;
  }

//--- Compute win rate safely
double CalcWinRate(int wins, int total)
  {
   if(total <= 0) return 0.0;
   return (double)wins / (double)total * 100.0;
  }

//==========================================================================
//  MULTI-CURRENCY DASHBOARD FORMATTING (Nominal + Pips)
//==========================================================================

// Currencies that are conventionally quoted with zero decimal places
// (no fractional sub-unit in everyday use).
bool IsZeroDecimalCurrency(string currencyCode)
  {
   string c = currencyCode;
   StringToUpper(c);
   return (c == "IDR" || c == "JPY" || c == "KRW" || c == "VND" ||
           c == "HUF" || c == "CLP" || c == "COP" || c == "ISK");
  }

// Returns a prefix symbol ("$", "€", ...) for currencies that are commonly
// displayed with a leading symbol. Returns "" for everything else, in which
// case the 3-letter ISO code is appended as a suffix instead (e.g. "IDR").
// NOTE: MQL5 string literals do not support C-style "\uXXXX" escapes, so the
// non-ASCII glyphs are built at runtime via ShortToString(codepoint) instead
// of being typed directly into the source.
string GetCurrencySymbolPrefix(string currencyCode)
  {
   string c = currencyCode;
   StringToUpper(c);
   if(c == "USD") return "$";
   if(c == "EUR") return ShortToString(0x20AC); // €
   if(c == "GBP") return ShortToString(0x00A3); // £
   if(c == "JPY") return ShortToString(0x00A5); // ¥
   if(c == "AUD" || c == "CAD" || c == "NZD" || c == "SGD" || c == "HKD") return "$";
   return "";
  }

// Inserts thousands separators (",") into a formatted number string.
// MQL5's DoubleToString() never groups digits, so the dashboard needs its
// own light-weight grouping helper for readable nominal values.
string FormatThousands(double value, int decimals)
  {
   bool neg = (value < 0.0);
   value = MathAbs(value);
   string raw = DoubleToString(value, decimals);

   string intPart = raw;
   string fracPart = "";
   int dot = StringFind(raw, ".");
   if(dot >= 0)
     {
      intPart  = StringSubstr(raw, 0, dot);
      fracPart = StringSubstr(raw, dot); // keeps the leading "."
     }

   string grouped = "";
   int len = StringLen(intPart);
   for(int i = 0; i < len; i++)
     {
      grouped += StringSubstr(intPart, i, 1);
      int remain = len - i - 1;
      if(remain > 0 && remain % 3 == 0)
         grouped += ",";
     }
   return (neg ? "-" : "") + grouped + fracPart;
  }

// Formats a monetary amount using the account's live deposit currency
// (auto-detected via ACCOUNT_CURRENCY unless an override is supplied).
// Examples: FormatMoney(100.0)         -> "$100.00"      (USD account)
//           FormatMoney(1000000.0)     -> "1,000,000 IDR" (IDR account)
string FormatMoney(double amount, string currencyOverride = NULL)
  {
   string cur = (currencyOverride == NULL || currencyOverride == "")
                ? AccountInfoString(ACCOUNT_CURRENCY) : currencyOverride;
   if(cur == "") cur = "USD";

   bool neg = (amount < 0.0);
   int decimals = IsZeroDecimalCurrency(cur) ? 0 : 2;
   string prefix = GetCurrencySymbolPrefix(cur);
   string numStr = FormatThousands(MathAbs(amount), decimals);
   string sign   = neg ? "-" : "";

   if(prefix != "")
      return sign + prefix + numStr;
   return sign + numStr + " " + cur;
  }

//==========================================================================
//  SYSTEM DIAGNOSTICS & ERROR LOGGER (JOURNAL RECORDER)
//==========================================================================

string GetDeinitReasonText(int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return "EA stopped manually by ExpertRemove()";
      case REASON_REMOVE:      return "EA removed from chart";
      case REASON_RECOMPILE:   return "Program recompiled";
      case REASON_CHARTCHANGE: return "Chart symbol or timeframe changed";
      case REASON_CHARTCLOSE:  return "Chart closed";
      case REASON_PARAMETERS:  return "Input parameters changed by user";
      case REASON_ACCOUNT:     return "Trading account changed or re-connected";
      case REASON_TEMPLATE:    return "New chart template applied";
      case REASON_INITFAILED:  return "Initialization failed (OnInit returned non-zero)";
      case REASON_CLOSE:       return "Terminal closed";
     }
   return StringFormat("Reason code: %d", reason);
  }

string GetTradeRetcodeText(uint code)
  {
   switch(code)
     {
      case TRADE_RETCODE_REQUOTE:          return "Requote (10004)";
      case TRADE_RETCODE_REJECT:           return "Request rejected by broker (10006)";
      case TRADE_RETCODE_CANCEL:           return "Request cancelled by trader (10007)";
      case TRADE_RETCODE_PLACED:           return "Order placed successfully (10008)";
      case TRADE_RETCODE_DONE:             return "Request executed successfully (10009)";
      case TRADE_RETCODE_DONE_PARTIAL:     return "Request executed partially (10010)";
      case TRADE_RETCODE_ERROR:            return "Common trade error (10011)";
      case TRADE_RETCODE_TIMEOUT:          return "Request timed out (10012)";
      case TRADE_RETCODE_INVALID:          return "Invalid request parameters (10013)";
      case TRADE_RETCODE_INVALID_VOLUME:   return "Invalid volume / lot size (10014)";
      case TRADE_RETCODE_INVALID_PRICE:    return "Invalid price (10015)";
      case TRADE_RETCODE_INVALID_STOPS:    return "Invalid stops (SL/TP too close to price) (10016)";
      case TRADE_RETCODE_TRADE_DISABLED:   return "Trade disabled on account/symbol (10017)";
      case TRADE_RETCODE_MARKET_CLOSED:    return "Market is closed (10018)";
      case TRADE_RETCODE_NO_MONEY:         return "Not enough money / margin (10019)";
      case TRADE_RETCODE_PRICE_CHANGED:    return "Prices changed (10020)";
      case TRADE_RETCODE_PRICE_OFF:        return "No quotes / off quotes (10021)";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid expiration (10022)";
      case TRADE_RETCODE_ORDER_CHANGED:    return "Order state changed (10023)";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too many requests / flood (10024)";
      case TRADE_RETCODE_NO_CHANGES:       return "No changes made to order (10025)";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "Autotrading disabled by server (10026)";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "Autotrading disabled by client terminal (10027)";
      case TRADE_RETCODE_LOCKED:           return "Request locked (10028)";
      case TRADE_RETCODE_FROZEN:           return "Order or position is frozen (10029)";
      case TRADE_RETCODE_INVALID_FILL:     return "Invalid fill type (10030)";
      case TRADE_RETCODE_CONNECTION:       return "No connection with trade server (10031)";
      case TRADE_RETCODE_ONLY_REAL:        return "Operation allowed only on real accounts (10032)";
      case TRADE_RETCODE_LIMIT_ORDERS:     return "Limit on pending orders reached (10033)";
      case TRADE_RETCODE_LIMIT_VOLUME:     return "Limit on volume reached (10034)";
      case TRADE_RETCODE_POSITION_CLOSED:  return "Position already closed (10035)";
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME: return "Invalid close volume (10036)";
      case TRADE_RETCODE_CLOSE_ORDER_EXIST: return "Close order already exists (10038)";
      case TRADE_RETCODE_LIMIT_POSITIONS:  return "Max positions limit reached (10039)";
     }
   return StringFormat("Retcode: %u", code);
  }

bool IsTransientTradeRetcode(uint code)
  {
   switch(code)
     {
      case TRADE_RETCODE_REQUOTE:           // fresh price required
      case TRADE_RETCODE_PRICE_CHANGED:     // fresh price required
      case TRADE_RETCODE_PRICE_OFF:         // momentary quote gap
      case TRADE_RETCODE_TIMEOUT:           // trade server slow to answer
      case TRADE_RETCODE_CONNECTION:        // momentary disconnect ("context busy"-style)
      case TRADE_RETCODE_TOO_MANY_REQUESTS: // server-side request flood/throttle
      case TRADE_RETCODE_LOCKED:            // request locked for processing by server
         return true;
     }
   return false;
  }

void LogTradeError(string action, ulong ticket, uint retcode, string retcomment, string extra = "")
  {
   if(!LogEnabled(LOG_LEVEL_ERROR)) return;
   Print("🚨 [YANSTD TRADE ERROR] ", action,
         " | Ticket: ", ticket,
         " | Code: ", retcode, " (", GetTradeRetcodeText(retcode), ")",
         " | Broker Comment: '", retcomment, "'",
         (extra != "" ? " | Details: " + extra : ""));
  }

void LogSystemError(string moduleName, string action, int errCode, string message)
  {
   if(!LogEnabled(LOG_LEVEL_ERROR)) return;
   Print("🚨 [YANSTD SYSTEM ERROR] [", moduleName, "::", action, "] Error Code: ", errCode, " | ", message);
  }

void LogSystemWarning(string moduleName, string action, string message)
  {
   if(!LogEnabled(LOG_LEVEL_WARN)) return;
   Print("⚠️ [YANSTD WARNING] [", moduleName, "::", action, "] ", message);
  }

string EncodeBase36(ulong value)
  {
   if(value == 0) return "0";
   string digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
   string result = "";
   while(value > 0)
     {
      int rem = (int)(value % 36);
      result = StringSubstr(digits, rem, 1) + result;
      value /= 36;
     }
   return result;
  }

//--- Reads base36 digits starting at startPos until the first non-base36
//--- character (e.g. the "_" delimiter) or end of string; matches the
//--- stop-at-first-non-digit behaviour StringToInteger() used to give us
//--- for the old decimal encoding, so callers don't need to know the
//--- field's length up front.
ulong DecodeBase36(const string &text, int startPos)
  {
   ulong value = 0;
   int len = StringLen(text);
   for(int i = startPos; i < len; i++)
     {
      ushort ch = StringGetCharacter(text, i);
      int digit = -1;
      if(ch >= '0' && ch <= '9')      digit = ch - '0';
      else if(ch >= 'A' && ch <= 'Z') digit = ch - 'A' + 10;
      else if(ch >= 'a' && ch <= 'z') digit = ch - 'a' + 10; // tolerate lower-case
      else break;
      value = value * 36 + (ulong)digit;
     }
   return value;
  }

//--- Signed wrapper for fields that can legitimately be -1 (e.g. brainBucketIdx
//--- when no pattern bucket matched). '-' is not a valid base36 digit, so
//--- DecodeBase36() above naturally stops there — safe to prefix/detect.
string EncodeBase36Signed(int value)
  {
   if(value < 0) return "-" + EncodeBase36((ulong)(-value));
   return EncodeBase36((ulong)value);
  }

int DecodeBase36Signed(const string &text, int startPos)
  {
   bool neg = false;
   int pos = startPos;
   if(pos < StringLen(text) && StringGetCharacter(text, pos) == '-')
     {
      neg = true;
      pos++;
     }
   ulong mag = DecodeBase36(text, pos);
   return neg ? -(int)mag : (int)mag;
  }

#endif // YANSTD_DEFINES_MQH
//+------------------------------------------------------------------+
