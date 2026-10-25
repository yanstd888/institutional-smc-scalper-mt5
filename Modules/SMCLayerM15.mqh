//+------------------------------------------------------------------+
//|                                                SMCLayerM15.mqh   |
//|         YANSTD EA — Layer 2 (SMC): Order Block & FVG on M15      |
//|                                    v1.0  |  2026-08-31           |
//+------------------------------------------------------------------+
#ifndef YANSTD_SMC_LAYER_M15_MQH
#define YANSTD_SMC_LAYER_M15_MQH
#include "Defines.mqh"
#include "FVGValidator.mqh"

class CSMCLayerM15
{
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;                     // Always PERIOD_M15
   SSMCM15_Zone     m_zones[];
   int              m_count;
   long             m_objSeq;   // Per-scan monotonic id for unique object names
   int              m_invalidationCloses;
   double           m_invalidationBufferPips;
   double           m_minDispBodyRatio;       // Min body/range ratio to qualify as "impulsive"
   int              m_maxOBBarAge;            // 0 = unlimited (classic OB); >0 = drop OB whose base bar is older
   double           m_minGapPips;             // Min FVG gap size in pips (legacy fallback when ATR unavailable)
   double           m_minZoneWidthPips;       // Min OB zone width in pips
   int              m_atrPeriod;              // ATR Engine: period for dynamic FVG width
   double           m_fvgATRMult;             // ATR Engine: FVG min width = ATR * this
   bool             m_obRequireOppositeColor;

   // C3: Liquidity sweep check — price must sweep below/above a recent swing before displacement
   bool HasSweepBeforeDisplacement(const MqlRates &rates[], int copied, int dispBar,
                                    bool isBullish, double atr)
     {
      if(dispBar + 7 >= copied) return false;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double sweepDepth = (atr > 0.0) ? (0.05 * atr) : (2.0 * pip);
      if(isBullish)
        {
         double recentLow = DBL_MAX;
         for(int k = dispBar + 3; k < MathMin(dispBar + 15, copied); k++)
            recentLow = MathMin(recentLow, rates[k].low);
         if(recentLow < DBL_MAX && rates[dispBar].low < recentLow + sweepDepth)
            return true;
        }
      else
        {
         double recentHigh = -DBL_MAX;
         for(int k = dispBar + 3; k < MathMin(dispBar + 15, copied); k++)
            recentHigh = MathMax(recentHigh, rates[k].high);
         if(recentHigh > -DBL_MAX && rates[dispBar].high > recentHigh - sweepDepth)
            return true;
        }
      return false; // ponytail: simplified lookback, extend to fractal swings for Gen5
     }

   // Scan() rebuilds the buffer from unmitigated zones only, so isMitigated
   // is always false here. Evict by touch count, then fill depth, then oldest.
   int FindWorstZoneIndex()
   {
      int worstIdx = -1;
      int worstTouch = -1;
      double worstFill = -1.0;
      datetime worstTime = D'3000.01.01';
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].touchCount > worstTouch ||
            (m_zones[i].touchCount == worstTouch && m_zones[i].fillRatio > worstFill) ||
            (m_zones[i].touchCount == worstTouch && m_zones[i].fillRatio == worstFill &&
             m_zones[i].createTime < worstTime))
         {
            worstTouch = m_zones[i].touchCount;
            worstFill  = m_zones[i].fillRatio;
            worstTime  = m_zones[i].createTime;
            worstIdx   = i;
         }
      }
      if(worstIdx >= 0) return worstIdx;
      return (m_count > 0) ? 0 : -1;
   }

   void AddZone(ENUM_SMCM15_TYPE type, double top, double bottom, datetime t, int bar, int touches,
                const double fillRatio = 0.0, const ENUM_ZONE_STATUS status = ZONE_FRESH)
   {
      if(top <= bottom) return;
      if((type == SMCM15_OB_DEMAND || type == SMCM15_OB_SUPPLY) &&
         m_maxOBBarAge > 0 && bar > m_maxOBBarAge)
         return;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);

      // Dedup: same type, overlapping within 3 pips on both edges
      for(int i = 0; i < m_count; i++)
      {
         if(m_zones[i].type == type &&
            MathAbs(m_zones[i].top - top) / pip < 3.0 &&
            MathAbs(m_zones[i].bottom - bottom) / pip < 3.0)
            return;
      }
      if(m_count >= MAX_ZONES)
      {
         int evictIdx = FindWorstZoneIndex();
         if(evictIdx >= 0)
         {
            if(evictIdx != m_count - 1)
               m_zones[evictIdx] = m_zones[m_count - 1];
            m_count--;
         }
      }
      m_zones[m_count].type        = type;
      m_zones[m_count].top         = top;
      m_zones[m_count].bottom      = bottom;
      m_zones[m_count].createTime  = t;
      m_zones[m_count].createBar   = bar;
      m_zones[m_count].barAge      = 0;
      m_zones[m_count].isMitigated = false;
      m_zones[m_count].isActive    = true;
      m_zones[m_count].touchCount  = touches;
      m_zones[m_count].fillRatio   = MathMax(0.0, MathMin(1.0, fillRatio));
      m_zones[m_count].status      = status;
      m_zones[m_count].objName     = "SMCM15_" + IntegerToString(m_objSeq) + "_" + IntegerToString((int)type);
      m_objSeq++;
      m_count++;
   }

public:
   CSMCLayerM15() : m_symbol(""), m_tf(PERIOD_M15), m_count(0), m_objSeq(0),
                    m_invalidationCloses(2), m_invalidationBufferPips(2.0),
                    m_minDispBodyRatio(0.0), m_maxOBBarAge(0), m_minGapPips(1.0), m_minZoneWidthPips(1.0),
                    m_atrPeriod(14), m_fvgATRMult(0.30), m_obRequireOppositeColor(true)
   {}

   // ATR Engine wiring (called from OnInit via CMSNREngine::SetATRParams).
   void SetATRParams(int atrPeriod, double fvgATRMult)
   {
      m_atrPeriod  = (atrPeriod  > 0)   ? atrPeriod  : 14;
      m_fvgATRMult = (fvgATRMult > 0.0) ? fvgATRMult : 0.30;
   }

   void Init(string symbol, int invalidationCloses, double invalidationBufferPips,
             double minDispBodyRatio, int maxOBBarAge = 0,
             double minGapPips = 1.0, double minZoneWidthPips = 1.0)
   {
      m_symbol = symbol;
      m_tf = PERIOD_M15;
      m_invalidationCloses     = MathMax(1, invalidationCloses);
      m_invalidationBufferPips = MathMax(0.0, invalidationBufferPips);
      // Same clamp as FVGValidator / InpFVGImpulseBodyRatio (0.50–0.95).
      m_minDispBodyRatio       = Clamp(minDispBodyRatio, 0.50, 0.95);
      m_maxOBBarAge            = MathMax(0, maxOBBarAge);
      m_minGapPips             = MathMax(0.1, minGapPips);
      m_minZoneWidthPips       = MathMax(0.1, minZoneWidthPips);
      m_count = 0;
      m_objSeq = 0;
      ArrayResize(m_zones, MAX_ZONES);
   }

   double GetMinDispBodyRatio() const { return m_minDispBodyRatio; }
   void SetOBRequireOppositeColor(const bool requireOpposite) { m_obRequireOppositeColor = requireOpposite; }

   // Rebuilds Layer-2 zones from closed M15 history:
   //  - OB M15  : the last opposite-colour candle immediately before an
   //              impulsive (body/range >= m_minDispBodyRatio) displacement.
   //  - FVG M15 : 3-candle imbalance; gap between candle-1 (oldest) and
   //              candle-3 (newest) wicks, candle-2 is the impulsive move.
   //
   // H3-FVG (audit 2026-09-12): on M15 (and every TF >= M5) an impulsive FVG is
   // mandatory for OB validity -- see YANSTD_EA_SYSTEM_GUIDE.md §48. Both
   // AddZone(SMCM15_OB_DEMAND, ...) and AddZone(SMCM15_OB_SUPPLY, ...) below
   // are intentionally nested inside `if(hasBullFVG)` / `if(hasBearFVG)`;
   // do not hoist the OB block out of that scope or lift it into its own
   // sibling `if`, or M15 OBs would stop requiring a paired FVG. This rule
   // does not apply to the M3 refinement in SignalEngine.mqh, where FVG
   // stays an optional confluence, not a requirement.
   void Scan(int lookbackBars = 300)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_tf, 0, lookbackBars + 5, rates);
      if(copied < 10) return;

      m_count = 0;
      m_objSeq = 0; // Restart per scan while keeping names unique within that scan
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      // One configurable FVG-width rule is shared by M15 and M5.  Previously
      // M15 hardcoded 0.10*ATR while the same input controlled only M5, so the
      // property label and actual Layer-2 behaviour disagreed.
      //
      // AUDIT FIX H1: minFVGWidth used to be derived from GetCachedATR() once,
      // outside the candidate loop below -- i.e. every historical candidate in
      // this scan was judged against TODAY's ATR instead of the ATR at its own
      // formation shift. That made old zones' validity drift with current
      // volatility and rescans non-causal. minFVGWidth is now recomputed per
      // candidate inside the loop from ReadATRAtShift() at the displacement
      // candle's shift (i+1); the pip-fallback path is unchanged.

      // Historical rebuilds must use the same lifecycle rule as live POIs:
      // consecutive closed M3 candles beyond the far edge plus buffer. Loading
      // M3 once avoids a CopyRates call for every candidate zone.
      MqlRates ltfRates[];
      ArraySetAsSeries(ltfRates, true);
      int ltfNeed = lookbackBars * MathMax(1, PeriodSeconds(m_tf) / PeriodSeconds(PERIOD_M3)) + 10;
      int ltfCopied = CopyRates(m_symbol, PERIOD_M3, 0, ltfNeed, ltfRates);
      double invalidationBuffer = m_invalidationBufferPips * pip;

      for(int i = 2; i < lookbackBars && i < copied - 2; i++)
      {
         // AUDIT FIX H1: formation-era ATR for THIS candidate, read at its own
         // displacement shift (i+1), not "now's" ATR (see note above Scan()).
         double atrFormation = ReadATRAtShift(m_symbol, m_tf, m_atrPeriod, i + 1);
         double minFVGWidth  = (atrFormation > 0.0) ? (m_fvgATRMult * atrFormation) : (m_minGapPips * pip);

         // Candle-2 (rates[i+1]) is the displacement candle in the three-candle
         // FVG sequence.  Enforce the configured body/range ratio on that exact
         // candle; the previous implementation stored this input but never used it.
         double dispRange = rates[i+1].high - rates[i+1].low;
         double dispBody  = MathAbs(rates[i+1].close - rates[i+1].open);
         if(dispRange <= 0) continue;
         bool bullDisplacement = (rates[i+1].close > rates[i+1].open &&
                                  dispBody / dispRange >= m_minDispBodyRatio);
         bool bearDisplacement = (rates[i+1].close < rates[i+1].open &&
                                  dispBody / dispRange >= m_minDispBodyRatio);

         // H5: displacement velocity — wick-to-body ratio must be low for impulse quality
         if(bullDisplacement || bearDisplacement)
           {
            double upperWick = rates[i+1].high - MathMax(rates[i+1].open, rates[i+1].close);
            double lowerWick = MathMin(rates[i+1].open, rates[i+1].close) - rates[i+1].low;
            double wickBodyRatio = (dispBody > 0.0) ? MathMax(upperWick, lowerWick) / dispBody : 9.0;
            if(wickBodyRatio > 0.50)
              {
               bullDisplacement = false;
               bearDisplacement = false; // ponytail: max wick/body=0.50, raise to 0.70 if too restrictive
              }
           }

         // An opposite candle plus a large body is not sufficient to call an
         // order block. The displacement close must also break pre-base
         // structure; otherwise ordinary alternating candles become false OBs.
         double priorHigh = -DBL_MAX, priorLow = DBL_MAX;
         for(int s = i + 3; s < i + 15 && s < copied; s++)
           {
            priorHigh = MathMax(priorHigh, rates[s].high);
            priorLow  = MathMin(priorLow,  rates[s].low);
           }
         bool breaksBullStructure = (priorHigh > -DBL_MAX && (rates[i].close > priorHigh || rates[i+1].close > priorHigh));
         bool breaksBearStructure = (priorLow < DBL_MAX && (rates[i].close < priorLow || rates[i+1].close < priorLow));

         //--- FVG BULLISH & BULLISH ORDER BLOCK (Displacement Order Flow)
         // Candle 1 = rates[i+2] (base candle), Candle 2 = rates[i+1] (displacement), Candle 3 = rates[i]
         bool hasBullFVG = (bullDisplacement && rates[i].low - rates[i+2].high >= minFVGWidth);
         // C3: liquidity sweep gate — bull FVG requires a sweep before displacement
         if(hasBullFVG && !HasSweepBeforeDisplacement(rates, copied, i+1, true, atrFormation))
            hasBullFVG = false; // ponytail: sweep required, relax to soft score if too many rejects
         if(hasBullFVG)
         {
            double fTop = rates[i].low;
            double fBot = rates[i+2].high;
            int touches = 0; bool wasInsideFVG = false;
            double fillRatio = FVGFillRatio(true, fTop, fBot, rates, copied, i - 1);
            bool fvgMitigated = (fillRatio >= 1.0);
            for(int k = i - 1; k >= 1; k--)
            {
               bool inside = (rates[k].low <= fTop && rates[k].high >= fBot);
               if(inside && !wasInsideFVG && IsZoneHeldTouch(true, rates[k], fTop, fBot)) touches++;
               wasInsideFVG = inside;
            }
            // Entry FVG must also overlap structure / SBR-RBS / HTF or psych level.
            // Mechanical gap above is still enough to justify the paired OB.
            // M1 (2026-09-13, §49): CE 50% is the eligibility cutoff, not 80%.
            // Once price has reached/crossed the midpoint the FVG is
            // complete/mitigated and must not be offered as a new entry.
            if(!fvgMitigated && fillRatio < 0.50 && IsFVGValidWithStructureFromRates(rates, copied, i, m_tf))
               AddZone(SMCM15_FVG_BULL, fTop, fBot, rates[i].time, i, touches,
                       fillRatio, (fillRatio > 0.0) ? ZONE_PARTIAL : ZONE_FRESH);

            // Bullish OB: base candle is rates[i+2] before displacement candle rates[i+1]
            // Base candle color is free unless InpOBRequireOppositeColor is on.
            bool baseColorOKBull = !m_obRequireOppositeColor || (rates[i+2].close < rates[i+2].open);
            if(breaksBullStructure && baseColorOKBull)
            {
               double zTop = rates[i+2].high;
               double zBot = rates[i+2].low;
               if(zTop < zBot) { double tmp = zTop; zTop = zBot; zBot = tmp; }
               if((zTop - zBot) >= (atrFormation > 0.0 ? 0.05 * atrFormation : pip))
               {
                  bool obMitigated = ZoneInvalidatedByClosedBars(ltfRates, ltfCopied,
                                      rates[i+2].time, true, zBot, zTop,
                                      m_invalidationCloses, invalidationBuffer);
                  int obTouches = 0; bool wasInsideOB = false;
                  for(int k = i - 1; k >= 1; k--)
                  {
                     bool inside = (rates[k].low <= zTop && rates[k].high >= zBot);
                     if(inside && !wasInsideOB && IsZoneHeldTouch(true, rates[k], zTop, zBot)) obTouches++;
                     wasInsideOB = inside;
                  }
                  if(!obMitigated) AddZone(SMCM15_OB_DEMAND, zTop, zBot, rates[i+2].time, i+2, obTouches);
               }
            }
         }

         //--- FVG BEARISH & BEARISH ORDER BLOCK (Displacement Order Flow)
         bool hasBearFVG = (bearDisplacement && rates[i+2].low - rates[i].high >= minFVGWidth);
         // C3: liquidity sweep gate — bear FVG requires a sweep before displacement
         if(hasBearFVG && !HasSweepBeforeDisplacement(rates, copied, i+1, false, atrFormation))
            hasBearFVG = false;
         if(hasBearFVG)
         {
            double fTop = rates[i+2].low;
            double fBot = rates[i].high;
            int touches = 0; bool wasInsideFVG = false;
            double fillRatio = FVGFillRatio(false, fTop, fBot, rates, copied, i - 1);
            bool fvgMitigated = (fillRatio >= 1.0);
            for(int k = i - 1; k >= 1; k--)
            {
               bool inside = (rates[k].high >= fBot && rates[k].low <= fTop);
               if(inside && !wasInsideFVG && IsZoneHeldTouch(false, rates[k], fTop, fBot)) touches++;
               wasInsideFVG = inside;
            }
            // M1 (2026-09-13, §49): CE 50% is the eligibility cutoff, not 80%.
            if(!fvgMitigated && fillRatio < 0.50 && IsFVGValidWithStructureFromRates(rates, copied, i, m_tf))
               AddZone(SMCM15_FVG_BEAR, fTop, fBot, rates[i].time, i, touches,
                       fillRatio, (fillRatio > 0.0) ? ZONE_PARTIAL : ZONE_FRESH);

            // Bearish OB: base candle is rates[i+2] before displacement candle rates[i+1]
            // Base candle color is free. Mandatory FVG formed by displacement candle.
            bool baseColorOKBear = !m_obRequireOppositeColor || (rates[i+2].close > rates[i+2].open);
            if(breaksBearStructure && baseColorOKBear)
            {
               double zTop = rates[i+2].high;
               double zBot = rates[i+2].low;
               if(zTop < zBot) { double tmp = zTop; zTop = zBot; zBot = tmp; }
               if((zTop - zBot) >= (atrFormation > 0.0 ? 0.05 * atrFormation : pip))
               {
                  bool obMitigated = ZoneInvalidatedByClosedBars(ltfRates, ltfCopied,
                                      rates[i+2].time, false, zBot, zTop,
                                      m_invalidationCloses, invalidationBuffer);
                  int obTouches = 0; bool wasInsideOB = false;
                  for(int k = i - 1; k >= 1; k--)
                  {
                     bool inside = (rates[k].high >= zBot && rates[k].low <= zTop);
                     if(inside && !wasInsideOB && IsZoneHeldTouch(false, rates[k], zTop, zBot)) obTouches++;
                     wasInsideOB = inside;
                  }
                  if(!obMitigated) AddZone(SMCM15_OB_SUPPLY, zTop, zBot, rates[i+2].time, i+2, obTouches);
               }
            }
         }
      }
   }

   int GetCount() const { return m_count; }

   bool GetZone(int idx, SSMCM15_Zone &out) const
   {
      if(idx < 0 || idx >= m_count) return false;
      out = m_zones[idx];
      return true;
   }

   bool FindOverlap(double areaBottom, double areaTop, ENUM_ZONE_TYPE side,
                    double tolerancePips, double refPrice, int &outIdx) const
   {
      outIdx = -1;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double tol = MathMax(0.0, tolerancePips) * pip;
      int best = -1;
      double bestScore = DBL_MAX;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_zones[i].isActive || m_zones[i].isMitigated) continue;
         bool isDemandSide = (m_zones[i].type == SMCM15_OB_DEMAND || m_zones[i].type == SMCM15_FVG_BULL);
         bool isSupplySide = (m_zones[i].type == SMCM15_OB_SUPPLY || m_zones[i].type == SMCM15_FVG_BEAR);
         if((side == ZONE_DEMAND && !isDemandSide) || (side == ZONE_SUPPLY && !isSupplySide)) continue;
         bool overlaps = (areaTop >= m_zones[i].bottom - tol && areaBottom <= m_zones[i].top + tol);
         if(!overlaps) continue;

         double zoneMid = (m_zones[i].top + m_zones[i].bottom) / 2.0;
         double distPips = (pip > 0.0) ? MathAbs(zoneMid - refPrice) / pip : 0.0;
         // touchCount dominates, then fill depth (CE/partial FVG loses to virgin),
         // then distance breaks remaining ties.
         double score = (double)m_zones[i].touchCount * 1000.0
                      + m_zones[i].fillRatio * 200.0
                      + distPips;
         if(score < bestScore) { bestScore = score; best = i; }
      }
      outIdx = best;
      return (best >= 0);
   }
};

#endif // YANSTD_SMC_LAYER_M15_MQH
//+------------------------------------------------------------------+
