#ifndef YANSTD_MSNR_ENGINE_MQH
#define YANSTD_MSNR_ENGINE_MQH
#define QML_SHOULDER_CLEARANCE_ATR_MULT 0.067
#define MSNR_MAX_KEY_LEVEL_AGE 200
#include "Defines.mqh"
#include "SMCLayerM15.mqh"

class CMSNREngine
{
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;        // Always PERIOD_M15
   SMSNR_Zone       m_zones[];   // Dynamic array, max MSNR_MAX_ZONES
   int              m_count;
   datetime         m_lastScanBar; // skip a second full rebuild on the same M15 bar
   long             m_objSeq;    // Monotonic id for unique chart-object names
   int              m_atrPeriod;        // ATR Engine: period for dynamic proximity
   double           m_proximityATRMult; // ATR Engine: zone touch/mitigation tol = ATR * this
   double           m_fibMin;    // OTE Fibo Min (default 0.618)
   double           m_fibMax;    // OTE Fibo Max (default 0.786)
   int              m_invalidationCloses;
   double           m_invalidationBufferPips;

   ENUM_TIMEFRAMES  m_kingPrimaryTF;    // King SNR primary/priority TF (default H4)
   ENUM_TIMEFRAMES  m_kingSecondaryTF;  // King SNR secondary/fallback TF (default H1)
   int              m_kingLookback;   // HTF candles scanned for King SNR pairs
   bool             m_requireOTE;     // true = OTE band is a hard AND gate
                                       // at zone formation; false=OR mode (optional boost only)
   bool             m_requireM5Contained; // v4.34: true = M5 ⊆ M15; false = overlap + ATR tol
   int              m_structureSwingWing; // AUDIT H2: QML + King SNR fractal wing (default 2)

   // --- Layer 2 (SMC) composition: OB M15 & FVG M15, independently coded ---
   CSMCLayerM15     m_smcM15;
   bool             m_useLayer2Gate;  // Require Layer1 x Layer2 OTE Overlap ("Overlap Logic")

   long             m_diagNoOverlapCount;   // FindOverlap() found nothing
   long             m_diagOverlapFailOTE;   // overlap found, but not in OTE
   long             m_diagOverlapPass;      // overlap found AND in OTE
   bool             m_layer2Qualified[MSNR_MAX_ZONES]; // cached once per M15 scan
   int              m_layer2Index[MSNR_MAX_ZONES];

   // Scan() only AddZone()s live zones; isMitigated is always false in-buffer.
   int FindWorstZoneIndex()
   {
      int worstIdx = -1;
      double worstScore = DBL_MAX;
      datetime worstTime = D'3000.01.01';
      for(int i = 0; i < m_count; i++) {
         if(m_zones[i].msnrScore < worstScore ||
            (m_zones[i].msnrScore == worstScore && m_zones[i].createTime < worstTime)) {
            worstScore = m_zones[i].msnrScore;
            worstTime  = m_zones[i].createTime;
            worstIdx   = i;
         }
      }
      if(worstIdx >= 0) return worstIdx;
      return (m_count > 0) ? 0 : -1;
   }

   bool FormationRangeFromLoaded(const MqlRates &rates[], int copied, int formationIndex,
                                 int pivotDepth, int lookbackBars,
                                 double &swingHigh, double &swingLow)
   {
      swingHigh = 0.0; swingLow = 0.0;
      int halfDepth = MathMax(2, pivotDepth / 2);
      int start = formationIndex + 1;
      int available = copied - start;
      int requested = MathMin(MathMax(30, lookbackBars), available);
      if(start < 0 || requested < halfDepth * 2 + 5) return false;
      return PairFormationSwingLeg(rates, copied, start, requested, halfDepth, swingHigh, swingLow);
   }

   bool AddZone(ENUM_MSNR_ZONE_TYPE type, double top, double bottom, datetime t, int bar,
                 ENUM_MSNR_FRESH_STATUS freshStatus,
                 bool hasFVG, double fvgTop, double fvgBot,
                 int touchCount, datetime fibAnchorTime = 0,
                 ENUM_TIMEFRAMES fibAnchorTF = PERIOD_CURRENT,
                 double formationHighHint = 0.0, double formationLowHint = 0.0)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      // Dedup: check overlap within 5 pips
      for(int i = 0; i < m_count; i++) {
         if(m_zones[i].msnrType == type &&
            MathAbs(m_zones[i].top - top) / pip < 5.0 &&
            MathAbs(m_zones[i].bottom - bottom) / pip < 5.0)
             return false; // Duplicate
      }
      datetime anchorTime = (fibAnchorTime > 0) ? fibAnchorTime : t;
      ENUM_TIMEFRAMES anchorTF = (fibAnchorTF == PERIOD_CURRENT) ? m_tf : fibAnchorTF;
      double formationHigh = formationHighHint, formationLow = formationLowHint;
      if(!(formationHigh > formationLow && formationLow > 0.0) &&
         !GetFormationDealingRange(m_symbol, anchorTF, anchorTime, 12, 180,
                                   formationHigh, formationLow)) return false;
      double formationRange = formationHigh - formationLow;
      bool demandType = MsnrIsDemand(type);
      double fibMinVal = demandType ? formationHigh - m_fibMin * formationRange
                                    : formationLow + m_fibMin * formationRange;
      double fibMaxVal = demandType ? formationHigh - m_fibMax * formationRange
                                    : formationLow + m_fibMax * formationRange;
      // A zone qualifies by its midpoint, not by a one-tick edge overlap with
      // the OTE band.  This is the documented rule and prevents very wide zones
      // from passing merely because one boundary touches 0.618 or 0.786.
      double zoneMid = (top + bottom) * 0.5;
      bool formationOTE = demandType ? (zoneMid >= fibMaxVal && zoneMid <= fibMinVal)
                                     : (zoneMid >= fibMinVal && zoneMid <= fibMaxVal);
      if(m_requireOTE && !formationOTE) return false;
      if(m_count >= MSNR_MAX_ZONES) {
         int evictIdx = FindWorstZoneIndex();
         if(evictIdx >= 0) {
            // O(1) eviction: overwrite the victim with the last live slot.
            // Scan() rebuilds the array from scratch each HTF bar, so index
            // stability across scans is not required here.
            if(evictIdx != m_count - 1)
               m_zones[evictIdx] = m_zones[m_count - 1];
            m_count--;
         }
      }
      m_zones[m_count].msnrType          = type;
      m_zones[m_count].freshStatus        = freshStatus;
      m_zones[m_count].top               = top;
      m_zones[m_count].bottom            = bottom;
      m_zones[m_count].leftShoulderPrice  = 0.0;
      m_zones[m_count].qmlHeadPrice       = 0.0;
      m_zones[m_count].keyLevelPrice      = 0.0;
      m_zones[m_count].isKeyLevel         = MsnrIsKeyLevel(type);
      m_zones[m_count].createTime        = t;
      m_zones[m_count].createBar         = bar;
      m_zones[m_count].barAge            = 0;
      m_zones[m_count].isActive          = true;
      m_zones[m_count].isMitigated       = false;
      m_zones[m_count].isInOTE           = formationOTE; // Preserve actual formation overlap in optional-OTE mode
      m_zones[m_count].fiboSwingHigh     = formationHigh;
      m_zones[m_count].fiboSwingLow      = formationLow;
      m_zones[m_count].hasFVG            = hasFVG;
      m_zones[m_count].fvgTop            = fvgTop;
      m_zones[m_count].fvgBottom         = fvgBot;
      m_zones[m_count].touchCount        = touchCount;
      m_zones[m_count].isKingSNR         = (type == MSNR_KING_SUPPORT || type == MSNR_KING_RESISTANCE);
      m_zones[m_count].kingSourceTF      = m_zones[m_count].isKingSNR ? anchorTF : PERIOD_CURRENT;
      // Score calculation
      double score = 50.0;
      if(freshStatus == MSNR_VIRGIN) score += 20.0;
      else if(freshStatus == MSNR_SINGLE_TOUCH) score += 10.0;
      // Liquidity is evaluated on M3. M15 FVG is validated by the gate.
      if(MsnrIsQml(type)) score += 15.0;
      if(MsnrIsKeyLevel(type)) score += 15.0;
      if(type == MSNR_RBS || type == MSNR_SBR) score += 5.0;
      // King SNR is an HTF liquidity-sweep structure -> highest structural quality
      if(type == MSNR_KING_SUPPORT || type == MSNR_KING_RESISTANCE) score += 25.0;
      double oteSweetSpot = demandType ? (formationHigh - 0.705 * formationRange)
                                       : (formationLow  + 0.705 * formationRange);
      double fibBandWidth = MathAbs(fibMinVal - fibMaxVal);
      double oteQualityScore = (formationOTE && fibBandWidth > 0.0)
                               ? MathMax(0.0, 1.0 - MathAbs(zoneMid - oteSweetSpot) / (0.5 * fibBandWidth))
                               : 0.0;
      score *= (1.0 + 0.15 * oteQualityScore);
      m_zones[m_count].msnrScore = MathMin(score, 100.0);
      m_zones[m_count].objName = "MSNR_" + IntegerToString(m_objSeq) + "_" + IntegerToString((int)type);
      m_zones[m_count].lblName = m_zones[m_count].objName + "_LBL";
      m_objSeq++;
      m_count++;
      return true;
   }

   // M3: Time invalidation — skip key levels older than 200 bars (XAUUSD ~50 hours on M15)
   void CommitKeyLevel(ENUM_MSNR_ZONE_TYPE type, double zTop, double zBot, double levelPrice,
                       datetime t, int bar, const MqlRates &rates[], int copied,
                       double invBuf)
   {
      if(m_count >= MSNR_MAX_ZONES) return;
      if(zTop <= zBot) return;
      if(bar > MSNR_MAX_KEY_LEVEL_AGE) return; // M3: skip ancient key levels (freshness decay)
      bool demand = MsnrIsDemand(type);
      int touches = 0;
      int invalidCloses = 0;
      bool mitigated = false;
      bool flipped = false;
      ENUM_MSNR_ZONE_TYPE flipType = MSNR_ZONE_NONE;
      int flipTouches = 0;
      int flipInvalid = 0;
      bool flipDead = false;
      bool wasInside = false;
      bool flipInside = false;
      for(int k = bar - 1; k >= 1; k--)
        {
         if(!flipped)
           {
            bool beyond = demand ? (rates[k].close < zBot - invBuf)
                                 : (rates[k].close > zTop + invBuf);
            invalidCloses = beyond ? invalidCloses + 1 : 0;
            if(invalidCloses >= m_invalidationCloses)
              {
               if(type == MSNR_V_SUPPORT || type == MSNR_OCL_DEMAND)
                 { flipped = true; flipType = MSNR_SBR; mitigated = true; }
               else if(type == MSNR_A_RESISTANCE || type == MSNR_OCL_SUPPLY)
                 { flipped = true; flipType = MSNR_RBS; mitigated = true; }
               else
                 { mitigated = true; break; }
               continue;
              }
            bool inside = (rates[k].low <= zTop && rates[k].high >= zBot);
            if(inside && !wasInside && IsZoneHeldTouch(demand, rates[k], zTop, zBot)) touches++;
            wasInside = inside;
           }
         else
           {
            bool flipDemand = MsnrIsDemand(flipType);
            bool beyond = flipDemand ? (rates[k].close < zBot - invBuf)
                                     : (rates[k].close > zTop + invBuf);
            flipInvalid = beyond ? flipInvalid + 1 : 0;
            if(flipInvalid >= m_invalidationCloses) { flipDead = true; break; }
            bool inside = (rates[k].low <= zTop && rates[k].high >= zBot);
            if(inside && !flipInside && IsZoneHeldTouch(flipDemand, rates[k], zTop, zBot)) flipTouches++;
            flipInside = inside;
           }
        }
      double fh = 0.0, fl = 0.0;
      FormationRangeFromLoaded(rates, copied, bar, 12, 180, fh, fl);
      if(!mitigated)
        {
         ENUM_MSNR_FRESH_STATUS status = (touches == 0) ? MSNR_VIRGIN :
                                         ((touches == 1) ? MSNR_SINGLE_TOUCH : MSNR_PARTIAL);
         if(AddZone(type, zTop, zBot, t, bar, status, false, 0.0, 0.0, touches, t, m_tf, fh, fl))
            m_zones[m_count - 1].keyLevelPrice = levelPrice;
        }
      else if(flipped && !flipDead && flipType != MSNR_ZONE_NONE)
        {
         ENUM_MSNR_FRESH_STATUS status = (flipTouches == 0) ? MSNR_VIRGIN :
                                         ((flipTouches == 1) ? MSNR_SINGLE_TOUCH : MSNR_PARTIAL);
         if(AddZone(flipType, zTop, zBot, t, bar, status, false, 0.0, 0.0, flipTouches, t, m_tf, fh, fl))
            m_zones[m_count - 1].keyLevelPrice = levelPrice;
        }
   }

   void ScanKeyLevels(const MqlRates &rates[], int copied)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      // AUDIT M5: MathMax(5, copied-2) was a no-op inside MathMin(copied-2, ...).
      int limit = copied - 2;
      if(limit < 5) return;
      for(int i = 1; i < limit; i++)
        {
         if(m_count >= MSNR_MAX_ZONES) break; // AUDIT FIX: early exit when zone capacity full
         const MqlRates c2 = rates[i];
         const MqlRates c1 = rates[i + 1];
         if(c1.close <= 0.0 || c2.close <= 0.0 || c1.high <= c1.low || c2.high <= c2.low)
            continue;
         // AUDIT FIX H1: this candidate's own formation-shift ATR (at c2 = i),
         // not the scan-wide "now" ATR that used to sit above this loop --
         // that let a rescan flip old key-level candidates on volatility change.
         double atr = ReadATRAtShift(m_symbol, m_tf, (m_atrPeriod > 0 ? m_atrPeriod : 14), i);
         double band = (atr > 0.0) ? (0.10 * atr) : pip;
         double invBuf = (atr > 0.0) ? (0.10 * atr) : (m_invalidationBufferPips * pip);
         double c1Top = MathMax(c1.open, c1.close);
         double c1Bot = MathMin(c1.open, c1.close);
         double c2Top = MathMax(c2.open, c2.close);
         double c2Bot = MathMin(c2.open, c2.close);
         bool c1Bull = (c1.close > c1.open);
         bool c2Bull = (c2.close > c2.open);
         double minBody = (atr > 0.0) ? (0.25 * atr) : pip;
         double minGap  = (atr > 0.0) ? (0.05 * atr) : pip;
         if(MathMax(MathAbs(c1.close - c1.open), MathAbs(c2.close - c2.open)) < minBody)
            continue;

         if(c2Bot > c1Top && (c2Bot - c1Top) >= minGap)
           {
            CommitKeyLevel(MSNR_OCL_DEMAND, c2Bot, c1Top, (c1Top + c2Bot) * 0.5,
                           c2.time, i, rates, copied, invBuf);
           }
         else if(c2Top < c1Bot && (c1Bot - c2Top) >= minGap)
           {
            CommitKeyLevel(MSNR_OCL_SUPPLY, c1Bot, c2Top, (c2Top + c1Bot) * 0.5,
                           c2.time, i, rates, copied, invBuf);
           }
         else if(c1Bull && !c2Bull)
           {
            double lvl = (c1Top + c2Top) * 0.5;
            CommitKeyLevel(MSNR_A_RESISTANCE, lvl + band, lvl - band, lvl,
                           c2.time, i, rates, copied, invBuf);
           }
         else if(!c1Bull && c2Bull)
           {
            double lvl = (c1Bot + c2Bot) * 0.5;
            CommitKeyLevel(MSNR_V_SUPPORT, lvl + band, lvl - band, lvl,
                           c2.time, i, rates, copied, invBuf);
           }
        }
   }

   void ScanQML(const MqlRates &rates[], int copied)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      // QML geometry per Rumus-Teknis-MSNR-SMC-ATR.md Tahap 1C:
      // Toleransi = 0.10 * ATR(M15, 14), Entry Zone = [Shoulder - Toleransi, Shoulder + Toleransi]
      // AUDIT FIX H1: atrQ/sigDist/qmlTol used to be one scan-wide value from
      // GetCachedATR() ("now"), applied to every swing combination regardless
      // of how old the left-shoulder pivot was. They are now recomputed per
      // candidate inside the loop below from the shoulder pivot's own shift
      // (swingBars[j]), so an old QML's validity stays fixed to the
      // volatility that existed when its shoulder formed.

      // Collect confirmed pivots in chronological order. rates[] is a series
      // array, therefore walking from the largest index down is essential.
      double swingPrices[]; datetime swingTimes[]; int swingBars[]; bool isHigh[];
      int swingCount = 0;
      ArrayResize(swingPrices, 0); ArrayResize(swingTimes, 0);
      ArrayResize(swingBars, 0); ArrayResize(isHigh, 0);

      const int qmlWing = MathMax(2, m_structureSwingWing);
      for(int i = copied - qmlWing - 2; i >= qmlWing + 1; i--)
      {
         if(IsFractalPivot(rates, copied, i, qmlWing, qmlWing, true))
         {
            int n = ArraySize(swingPrices);
            ArrayResize(swingPrices, n+1, 64); ArrayResize(swingTimes, n+1, 64);
            ArrayResize(swingBars, n+1, 64); ArrayResize(isHigh, n+1, 64);
            swingPrices[n] = rates[i].high; swingTimes[n] = rates[i].time; swingBars[n] = i; isHigh[n] = true;
            swingCount++;
         }
         if(IsFractalPivot(rates, copied, i, qmlWing, qmlWing, false))
         {
            int n = ArraySize(swingPrices);
            ArrayResize(swingPrices, n+1, 64); ArrayResize(swingTimes, n+1, 64);
            ArrayResize(swingBars, n+1, 64); ArrayResize(isHigh, n+1, 64);
            swingPrices[n] = rates[i].low; swingTimes[n] = rates[i].time; swingBars[n] = i; isHigh[n] = false;
            swingCount++;
         }
      }

      // Bullish QM: LL(left shoulder) -> H -> lower LL -> break above H.
      // Bearish QM: HH(left shoulder) -> L -> higher HH -> break below L.
      for(int j = 0; j + 3 < swingCount; j++)
      {
         if(m_count >= MSNR_MAX_ZONES) break; // AUDIT FIX: early exit when zone capacity full
         double atrQ    = ReadATRAtShift(m_symbol, m_tf, (m_atrPeriod > 0 ? m_atrPeriod : 14), swingBars[j]);
         double sigDist = (atrQ > 0.0) ? (QML_SHOULDER_CLEARANCE_ATR_MULT * atrQ) : (2.0 * pip);
         double qmlTol  = (atrQ > 0.0) ? (0.10 * atrQ)  : (1.0 * pip);
         if(!isHigh[j] && isHigh[j+1] && !isHigh[j+2] && isHigh[j+3])
         {
            double leftSL     = swingPrices[j];
            double firstHigh  = swingPrices[j+1];
            double lowerLow   = swingPrices[j+2];
            if(lowerLow >= leftSL - sigDist) continue;
            // AUDIT M2: breakout of first high must be a CLOSE, not the 4th swing wick.
            bool closeConfirmedBreak = false;
            for(int cb = swingBars[j+2] - 1; cb >= swingBars[j+3]; cb--)
              {
               if(cb < 1 || cb >= copied) continue;
               if(rates[cb].close > firstHigh + sigDist) { closeConfirmedBreak = true; break; }
              }
            if(!closeConfirmedBreak) continue;

            double zTop = leftSL + qmlTol;
            double zBot = leftSL - qmlTol;

            int confirmBar = MathMax(1, swingBars[j+3] - 2);
            datetime confirmTime = rates[confirmBar].time + PeriodSeconds(m_tf);
            double invBufPrice = m_invalidationBufferPips * pip;
            bool mitigated = ZoneInvalidatedByClosedBars(rates, copied, confirmTime, true,
                                                         zBot, zTop, m_invalidationCloses, invBufPrice);
            if(mitigated) continue;
            int touches = CountHeldTouchesAfter(rates, copied, confirmTime, true, zTop, zBot);
            ENUM_MSNR_FRESH_STATUS status = (touches == 0) ? MSNR_VIRGIN :
                                                   ((touches == 1) ? MSNR_SINGLE_TOUCH : MSNR_PARTIAL);
            // AUDIT FIX (#5): this used to search m_zones for
            // MSNR_FRESH_DEMAND/MSNR_PARTIAL_DEMAND — zone types that are
            // legacy aliases never actually assigned by AddZone(), so hasFVG
            // was always false (dead code). FVGs are tracked by m_smcM15
            // (the Layer-2 M15 SMC layer), so look there instead, and reuse
            // FVGRangeOverlapsZone() (FVGValidator.mqh) for the geometric
            // test rather than re-deriving it.
            bool hasFVG = false;
            double fvgTop = 0.0, fvgBot = 0.0;
            int fvgIdx = -1;
            double qmlRefPrice = (zTop + zBot) / 2.0;
            if(m_smcM15.FindOverlap(zBot, zTop, ZONE_DEMAND, DynamicProximityPips(), qmlRefPrice, fvgIdx))
              {
               SSMCM15_Zone smcZone;
               if(m_smcM15.GetZone(fvgIdx, smcZone) && smcZone.type == SMCM15_FVG_BULL &&
                  FVGRangeOverlapsZone(smcZone.bottom, smcZone.top, zBot, zTop))
                 {
                  hasFVG = true;
                  fvgTop = smcZone.top;
                  fvgBot = smcZone.bottom;
                 }
              }
            double fh = 0.0, fl = 0.0;
            FormationRangeFromLoaded(rates, copied, swingBars[j+3], 12, 180, fh, fl);
            if(AddZone(MSNR_QML_BUY, zTop, zBot, confirmTime, 0, status,
                       hasFVG, fvgTop, fvgBot, touches, confirmTime, m_tf, fh, fl))
              {
               m_zones[m_count-1].leftShoulderPrice = leftSL;
               m_zones[m_count-1].qmlHeadPrice = lowerLow;
              }
         }

         if(isHigh[j] && !isHigh[j+1] && isHigh[j+2] && !isHigh[j+3])
         {
            double leftSH     = swingPrices[j];
            double firstLow   = swingPrices[j+1];
            double higherHigh = swingPrices[j+2];
            if(higherHigh <= leftSH + sigDist) continue;
            // AUDIT M2: breakout of first low must be a CLOSE, not the 4th swing wick.
            bool closeConfirmedBreak = false;
            for(int cb = swingBars[j+2] - 1; cb >= swingBars[j+3]; cb--)
              {
               if(cb < 1 || cb >= copied) continue;
               if(rates[cb].close < firstLow - sigDist) { closeConfirmedBreak = true; break; }
              }
            if(!closeConfirmedBreak) continue;

            double zTop = leftSH + qmlTol;
            double zBot = leftSH - qmlTol;

            int confirmBar = MathMax(1, swingBars[j+3] - 2);
            datetime confirmTime = rates[confirmBar].time + PeriodSeconds(m_tf);
            double invBufPrice = m_invalidationBufferPips * pip;
            bool mitigated = ZoneInvalidatedByClosedBars(rates, copied, confirmTime, false,
                                                         zBot, zTop, m_invalidationCloses, invBufPrice);
            if(mitigated) continue;
            int touches = CountHeldTouchesAfter(rates, copied, confirmTime, false, zTop, zBot);
            ENUM_MSNR_FRESH_STATUS status = (touches == 0) ? MSNR_VIRGIN :
                                                   ((touches == 1) ? MSNR_SINGLE_TOUCH : MSNR_PARTIAL);
            // AUDIT FIX (#5): see the matching BUY-branch comment above —
            // MSNR_FRESH_SUPPLY/MSNR_PARTIAL_SUPPLY are never assigned to any
            // zone, so this was dead code. Look up the Layer-2 M15 SMC layer
            // instead, reusing FVGRangeOverlapsZone() for the overlap test.
            bool hasFVG = false;
            double fvgTop = 0.0, fvgBot = 0.0;
            int fvgIdx = -1;
            double qmlRefPrice = (zTop + zBot) / 2.0;
            if(m_smcM15.FindOverlap(zBot, zTop, ZONE_SUPPLY, DynamicProximityPips(), qmlRefPrice, fvgIdx))
              {
               SSMCM15_Zone smcZone;
               if(m_smcM15.GetZone(fvgIdx, smcZone) && smcZone.type == SMCM15_FVG_BEAR &&
                  FVGRangeOverlapsZone(smcZone.bottom, smcZone.top, zBot, zTop))
                 {
                  hasFVG = true;
                  fvgTop = smcZone.top;
                  fvgBot = smcZone.bottom;
                 }
              }
            double fh = 0.0, fl = 0.0;
            FormationRangeFromLoaded(rates, copied, swingBars[j+3], 12, 180, fh, fl);
            if(AddZone(MSNR_QML_SELL, zTop, zBot, confirmTime, 0, status,
                       hasFVG, fvgTop, fvgBot, touches, confirmTime, m_tf, fh, fl))
              {
               m_zones[m_count-1].leftShoulderPrice = leftSH;
               m_zones[m_count-1].qmlHeadPrice = higherHigh;
              }
         }
      }
   }

   //+---------------------------------------------------------------+
   //| King SNR — computed on HTF (H1/H4), mapped down to M15.       |
   //|                                                               |
   //| King Support (Bullish): candle1 Bearish -> candle2 Bullish,   |
   //|   AND candle2's lower wick sweeps below candle1's lower wick  |
   //|   (liquidity grab), Close[2] > Low[1]                         |
   //|   Zone = [candle2.Low ... candle2.Open].                      |
   //|                                                               |
   //| King Resistance (Bearish): candle1 Bullish -> candle2 Bearish,|
   //|   AND candle2's upper wick sweeps above candle1's upper wick, |
   //|   Close[2] < High[1]                                          |
   //|   Zone = [candle2.Open ... candle2.High].                     |
   //|                                                               |
   //| Invalidation Buffer = 0.10 * ATR(HTF, 14)                     |
   //+---------------------------------------------------------------+

   bool IsSwingLowValidated(const MqlRates &rates[], const int copied, const int i, const int swingWindow)
   {
      return IsFractalPivot(rates, copied, i, swingWindow, swingWindow, false);
   }
   bool IsSwingHighValidated(const MqlRates &rates[], const int copied, const int i, const int swingWindow)
   {
      return IsFractalPivot(rates, copied, i, swingWindow, swingWindow, true);
   }
   bool HasEqualLowsNearby(const MqlRates &rates[], const int copied, const int i, const double tolerance)
   {
      if(tolerance <= 0.0) return false;
      for(int k = i + 2; k < copied && k <= i + 8; k++)
         if(MathAbs(rates[k].low - rates[i].low) <= tolerance) return true;
      return false;
   }
   bool HasEqualHighsNearby(const MqlRates &rates[], const int copied, const int i, const double tolerance)
   {
      if(tolerance <= 0.0) return false;
      for(int k = i + 2; k < copied && k <= i + 8; k++)
         if(MathAbs(rates[k].high - rates[i].high) <= tolerance) return true;
      return false;
   }

   void ScanKingSNRTF(ENUM_TIMEFRAMES tf, int lookback)
   {
      if(lookback <= 0) return;
      MqlRates htf[];
      ArraySetAsSeries(htf, true);
      int copied = CopyRates(m_symbol, tf, 0, lookback + 3, htf);
      if(copied < 5) return;

      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      // ATR Engine: Buffer = 0.10 * ATR(tf, 14) following Rumus-Teknis-MSNR-SMC-ATR.md
      // AUDIT FIX H1: kingBuffer/minZoneWidth used to come from one scan-wide
      // GetCachedATR() call ("now"), applied to every historical King SNR
      // candidate. Recomputed per candidate below via ReadATRAtShift() at c2's
      // own shift (i), so old King SNR zones keep the validity they had when
      // c2 formed, independent of current volatility.
      for(int i = 1; i < lookback && i < copied - 2; i++)
      {
         if(m_count >= MSNR_MAX_ZONES) break; // AUDIT FIX: early exit when zone capacity full
         double atrKing = ReadATRAtShift(m_symbol, tf, (m_atrPeriod > 0 ? m_atrPeriod : 14), i);
         double kingBuffer = (atrKing > 0.0) ? (0.10 * atrKing) : (m_invalidationBufferPips * pip);
         double minZoneWidth = (atrKing > 0.0) ? (0.05 * atrKing) : 1.0 * pip;
         MqlRates c1 = htf[i+1]; // first candle  (older, chronologically earlier)
         MqlRates c2 = htf[i];   // second candle (newer, forms the King SNR)
         bool matchedThisPair = false;

         //--- KING SUPPORT (Bullish King SNR): Sweep low[1] and close above low[1]
         bool c1Bear = (c1.close < c1.open);
         bool c2Bull = (c2.close > c2.open);
         bool genuineLow = IsSwingLowValidated(htf, copied, i + 1, MathMax(2, m_structureSwingWing)) ||
                           HasEqualLowsNearby(htf, copied, i + 1, kingBuffer);
         if(c1Bear && c2Bull && c2.low < c1.low && c2.close > c1.low && genuineLow)
         {
            // C6: require impulsive body ratio >= 0.55 for King SNR quality
            double _krB = c2.high - c2.low;
            if(_krB <= 0.0 || MathAbs(c2.close - c2.open) / _krB < 0.55) {} else
              {
            double zTop = c2.open;
            double zBot = c2.low;
            if(zTop > zBot && (zTop - zBot) >= minZoneWidth)
            {
               int touches = 0; bool mitigated = false, wasInside = false;
               // H1: wick vs body touch — body close inside zone demotes faster
               for(int k = i - 1; k >= 1; k--)
               {
                  if(htf[k].close < zBot - kingBuffer) { mitigated = true; break; }
                  bool inside = (htf[k].low <= zTop && htf[k].high >= zBot);
                  // H1: body close inside zone counts as 2 touches (heavier), wick-only as 1
                  if(inside && !wasInside)
                    {
                     bool bodyInside = (htf[k].close >= zBot && htf[k].close <= zTop);
                     if(IsZoneHeldTouch(true, htf[k], zTop, zBot))
                        touches += bodyInside ? 2 : 1; // ponytail: body=2, wick=1
                    }
                  wasInside = inside;
               }
               if(!mitigated)
               {
                  ENUM_MSNR_FRESH_STATUS status = (touches == 0) ? MSNR_VIRGIN :
                                                   ((touches == 1) ? MSNR_SINGLE_TOUCH : MSNR_PARTIAL);
                  double fh = 0.0, fl = 0.0;
                  FormationRangeFromLoaded(htf, copied, i, 12, 180, fh, fl);
                  if(AddZone(MSNR_KING_SUPPORT, zTop, zBot, c2.time, i, status,
                             false, 0.0, 0.0, touches, c2.time, tf, fh, fl))
                  {
                     matchedThisPair = true;
                  }
               }
              } // C6 else close
            }
         }

         //--- KING RESISTANCE (Bearish King SNR): Sweep high[1] and close below high[1]
         bool c1Bull = (c1.close > c1.open);
         bool c2Bear = (c2.close < c2.open);
         bool genuineHigh = IsSwingHighValidated(htf, copied, i + 1, MathMax(2, m_structureSwingWing)) ||
                            HasEqualHighsNearby(htf, copied, i + 1, kingBuffer);
         if(c1Bull && c2Bear && c2.high > c1.high && c2.close < c1.high && genuineHigh)
         {
            // C6: require impulsive body ratio >= 0.55 for King SNR quality
            double _krR = c2.high - c2.low;
            if(_krR <= 0.0 || MathAbs(c2.close - c2.open) / _krR < 0.55) {} else
              {
            double zTop = c2.high;
            double zBot = c2.open;
            if(zTop > zBot && (zTop - zBot) >= minZoneWidth)
            {
               int touches = 0; bool mitigated = false, wasInside = false;
               for(int k = i - 1; k >= 1; k--)
               {
                  if(htf[k].close > zTop + kingBuffer) { mitigated = true; break; }
                  bool inside = (htf[k].high >= zBot && htf[k].low <= zTop);
                  if(inside && !wasInside)
                    {
                     bool bodyInside = (htf[k].close >= zBot && htf[k].close <= zTop);
                     if(IsZoneHeldTouch(false, htf[k], zTop, zBot))
                        touches += bodyInside ? 2 : 1;
                    }
                  wasInside = inside;
               }
               if(!mitigated)
               {
                  ENUM_MSNR_FRESH_STATUS status = (touches == 0) ? MSNR_VIRGIN :
                                                   ((touches == 1) ? MSNR_SINGLE_TOUCH : MSNR_PARTIAL);
                  double fh = 0.0, fl = 0.0;
                  FormationRangeFromLoaded(htf, copied, i, 12, 180, fh, fl);
                  if(AddZone(MSNR_KING_RESISTANCE, zTop, zBot, c2.time, i, status,
                             false, 0.0, 0.0, touches, c2.time, tf, fh, fl))
                  {
                     matchedThisPair = true;
                  }
               }
              } // C6 else close
            }
         }

         if(matchedThisPair) i++;
      }
   }

   void ScanKingSNR()
   {
      ScanKingSNRTF(m_kingPrimaryTF, m_kingLookback);
      ScanKingSNRTF(m_kingSecondaryTF, m_kingLookback);
   }

   // Overlap Logic (King SNR / MSNR+SMC method):
   // A QML Layer-1 zone is valid only if it has a real geometric
   // intersection with a matching-side Layer-2 M15 OB/FVG. The intersection
   // being inside the OTE Fibo window is optional by default and becomes a
   // hard condition only when m_requireOTE=true. Returns the Layer-2 index.
   bool EvaluateLayer2Confluence(const SMSNR_Zone &zone, ENUM_ZONE_TYPE type,
                                 double tolerancePips, int &smcIdx)
   {
      smcIdx = -1;
      int idx = -1;
      double refPrice = (zone.top + zone.bottom) / 2.0;
      if(!m_smcM15.FindOverlap(zone.bottom, zone.top, type, tolerancePips, refPrice, idx))
      {
         m_diagNoOverlapCount++;
         return false;
      }

      SSMCM15_Zone smc;
      if(!m_smcM15.GetZone(idx, smc)) return false;

      // Numeric intersection window between the two layers (tolerance-only
      // touches with no real overlap don't count as a valid confluence).
      double interTop = MathMin(zone.top, smc.top);
      double interBot = MathMax(zone.bottom, smc.bottom);
      if(interTop < interBot) { m_diagNoOverlapCount++; return false; }

      // OTE is optional by default. The geometric Layer-1/Layer-2 overlap
      // above remains hard; only the intersection's location inside the OTE
      // band is conditional on the strict compatibility switch.
      double swingRange = zone.fiboSwingHigh - zone.fiboSwingLow;
      bool inOTE = false;
      if(swingRange > 0.0)
      {
         double interMid = (interTop + interBot) * 0.5;
         if(type == ZONE_DEMAND)
         {
            double fibMinVal = zone.fiboSwingHigh - m_fibMin * swingRange;
            double fibMaxVal = zone.fiboSwingHigh - m_fibMax * swingRange;
            inOTE = (interMid >= fibMaxVal && interMid <= fibMinVal);
         }
         else
         {
            double fibMinVal = zone.fiboSwingLow + m_fibMin * swingRange;
            double fibMaxVal = zone.fiboSwingLow + m_fibMax * swingRange;
            inOTE = (interMid >= fibMinVal && interMid <= fibMaxVal);
         }
      }
      if(!inOTE)
      {
         m_diagOverlapFailOTE++; // informational in optional mode
         if(m_requireOTE) return false;
      }
      else
         m_diagOverlapPass++;

      smcIdx = idx;
      return true;
   }

   // Layer 1 (MSNR map: key level / QML) must overlap Layer 2 (SMC OB/FVG M15).
   // King SNR is a direction filter only — never an entry zone.
   void RebuildLayer2Qualification()
   {
      for(int i = 0; i < MSNR_MAX_ZONES; i++)
        {
         m_layer2Qualified[i] = false;
         m_layer2Index[i] = -1;
        }
      for(int i = 0; i < m_count; i++)
        {
         if(m_zones[i].isKingSNR)
           {
            m_layer2Qualified[i] = false;
            continue;
           }
         ENUM_ZONE_TYPE side = MsnrIsDemand(m_zones[i].msnrType) ? ZONE_DEMAND : ZONE_SUPPLY;
         if(m_useLayer2Gate)
           {
            int smcIdx = -1;
            m_layer2Qualified[i] = EvaluateLayer2Confluence(m_zones[i], side, DynamicProximityPips(), smcIdx);
            m_layer2Index[i] = smcIdx;
           }
         else
            m_layer2Qualified[i] = true;
        }
   }

public:
   // ATR Engine wiring (called from OnInit). Forwards FVG multiplier to the
   // embedded Layer-2 M15 engine so both layers share one ATR configuration.
   void SetATRParams(int atrPeriod, double proximityATRMult, double fvgATRMult)
   {
      m_atrPeriod        = (atrPeriod > 0)          ? atrPeriod        : 14;
      m_proximityATRMult = (proximityATRMult > 0.0) ? proximityATRMult : 0.25;
      m_smcM15.SetATRParams(m_atrPeriod, fvgATRMult);
   }

   void SetRequireM5Contained(bool requireContained) { m_requireM5Contained = requireContained; }
   void SetStructureSwingWing(int wing) { m_structureSwingWing = MathMax(2, wing); }

   // Dynamic zone touch/mitigation tolerance in PIPS = ATR(period) * mult / pip.
   // Falls back to the legacy 3-pip confluence tolerance when ATR is unavailable.
   double DynamicProximityPips()
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double atr = GetCachedATR(m_symbol, m_tf, m_atrPeriod);
      if(atr <= 0.0 || pip <= 0.0) return 3.0;
      return (atr * m_proximityATRMult) / pip;
   }

   void Init(string symbol, ENUM_TIMEFRAMES tf, double fibMin = 0.618, double fibMax = 0.786,
             int invalidationCloses = 2, double invalidationBufferPips = 2.0,
             ENUM_TIMEFRAMES kingPrimaryTF = PERIOD_H4, ENUM_TIMEFRAMES kingSecondaryTF = PERIOD_H1,
             int kingLookback = 150,
             bool useLayer2Gate = true, bool requireOTE = false,
             double fvgImpulseBodyRatio = 0.70, int maxOBBarAge = 0)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_fibMin = (fibMin > 0.0) ? fibMin : 0.618;
      m_fibMax = (fibMax > 0.0) ? fibMax : 0.786;
      m_invalidationCloses = MathMax(1, invalidationCloses);
      m_invalidationBufferPips = MathMax(0.0, invalidationBufferPips);
      // Fall back to the spec pair if caller passes two identical TFs (would
      // make the primary/secondary priority logic in GetKingSNRBias() meaningless).
      m_kingPrimaryTF   = kingPrimaryTF;
      m_kingSecondaryTF = (kingSecondaryTF != kingPrimaryTF)
                          ? kingSecondaryTF
                          : (kingPrimaryTF == PERIOD_H4 ? PERIOD_H1 : PERIOD_H4);
      m_kingLookback = MathMax(0, kingLookback);
      m_useLayer2Gate = useLayer2Gate;
      m_requireOTE = requireOTE;
      m_requireM5Contained = true;
      m_structureSwingWing = 2;
      m_count = 0;
      m_lastScanBar = 0;
      m_objSeq = 0;
      if(m_atrPeriod <= 0)        m_atrPeriod = 14;          // ATR Engine defaults (overridden by SetATRParams)
      if(m_proximityATRMult <= 0.0) m_proximityATRMult = 0.25;
      m_diagNoOverlapCount = 0;
      m_diagOverlapFailOTE = 0;
      m_diagOverlapPass    = 0;
      for(int i = 0; i < MSNR_MAX_ZONES; i++)
        {
         m_layer2Qualified[i] = false;
         m_layer2Index[i] = -1;
        }
      ArrayResize(m_zones, MSNR_MAX_ZONES);
      m_smcM15.Init(symbol, invalidationCloses, invalidationBufferPips,
                   fvgImpulseBodyRatio, maxOBBarAge);
   }

   double GetLayer2MinDispBodyRatio() const { return m_smcM15.GetMinDispBodyRatio(); }
   void SetOBRequireOppositeColor(const bool requireOpposite) { m_smcM15.SetOBRequireOppositeColor(requireOpposite); }

   int GetZoneCount() const { return m_count; }

   bool GetZone(int index, SMSNR_Zone &zone) const
   {
      if(index < 0 || index >= m_count) return false;
      zone = m_zones[index];
      return true;
   }

   int GetLayer2Count() const { return m_smcM15.GetCount(); }

   bool GetLayer2Zone(int index, SSMCM15_Zone &zone) const
   {
      return m_smcM15.GetZone(index, zone);
   }

   string GetDiagOverlapSummary() const
   {
      long total = m_diagNoOverlapCount + m_diagOverlapFailOTE + m_diagOverlapPass;
      if(total <= 0) return "OverlapLogic diag: no candidates evaluated yet";
      return StringFormat("OverlapLogic diag: %I64d checked | no-overlap=%I64d (%.1f%%) | overlap-but-not-OTE=%I64d (%.1f%%) | pass=%I64d (%.1f%%)",
                           total,
                           m_diagNoOverlapCount, 100.0 * (double)m_diagNoOverlapCount / (double)total,
                           m_diagOverlapFailOTE, 100.0 * (double)m_diagOverlapFailOTE / (double)total,
                           m_diagOverlapPass,    100.0 * (double)m_diagOverlapPass    / (double)total);
   }

   void Scan(int lookbackBars = 300)
   {
      datetime barTime = iTime(m_symbol, m_tf, 0);
      if(barTime > 0 && barTime == m_lastScanBar)
         return;
      m_lastScanBar = barTime;

      m_diagNoOverlapCount = 0;
      m_diagOverlapFailOTE = 0;
      m_diagOverlapPass    = 0;
      // Layer 2 (SMC) is rebuilt independently of Layer 1 (MSNR) — kept as
      // a separate scan/array per the coding-layer separation rule.
      m_smcM15.Scan(lookbackBars);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_tf, 0, lookbackBars + 5, rates);
      if(copied < 20) return;

      // Rebuild from closed history on each HTF bar.  This prevents tick-count
      // dependent freshness state and guarantees identical OHLC/real-tick
      // zone classification for the same completed candles.
      m_count = 0;

      // Layer 1 map = MSNR key levels + QML. Layer 2 SMC OB/FVG stays in m_smcM15
      // and is applied only through the overlap gate.
      ScanKeyLevels(rates, copied);
      ScanQML(rates, copied);
      ScanKingSNR();
      RebuildLayer2Qualification();
   }



   ENUM_SIGNAL_TYPE GetKingSNRBias() const
   {
      // 1. Check primary-TF King SNR (higher priority = dominant bias)
      datetime priBuyTime = 0, priSellTime = 0;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_zones[i].isKingSNR || !m_zones[i].isActive || m_zones[i].isMitigated) continue;
         if(m_zones[i].kingSourceTF == m_kingPrimaryTF)
         {
            if(m_zones[i].msnrType == MSNR_KING_SUPPORT && m_zones[i].createTime > priBuyTime) priBuyTime = m_zones[i].createTime;
            if(m_zones[i].msnrType == MSNR_KING_RESISTANCE && m_zones[i].createTime > priSellTime) priSellTime = m_zones[i].createTime;
         }
      }
      if(priBuyTime > priSellTime) return SIGNAL_BUY;
      if(priSellTime > priBuyTime) return SIGNAL_SELL;

      // 2. Fallback to secondary-TF King SNR if primary has no active unmitigated zone
      datetime secBuyTime = 0, secSellTime = 0;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_zones[i].isKingSNR || !m_zones[i].isActive || m_zones[i].isMitigated) continue;
         if(m_zones[i].kingSourceTF == m_kingSecondaryTF)
         {
            if(m_zones[i].msnrType == MSNR_KING_SUPPORT && m_zones[i].createTime > secBuyTime) secBuyTime = m_zones[i].createTime;
            if(m_zones[i].msnrType == MSNR_KING_RESISTANCE && m_zones[i].createTime > secSellTime) secSellTime = m_zones[i].createTime;
         }
      }
      if(secBuyTime > secSellTime) return SIGNAL_BUY;
      if(secSellTime > secBuyTime) return SIGNAL_SELL;

      return SIGNAL_NONE;
   }

   ENUM_SIGNAL_TYPE GetKingBias() const { return GetKingSNRBias(); }

   // AUDIT FIX (#7): removed IsKingDirectionAllowed() — the pre-v4.40 hard
   // gate ("direction must match King SNR bias") that CHANGELOG v4.40
   // deliberately replaced with a soft counter-trend score gate. It was
   // never called from anywhere; superseded by the v4.40 soft gate.

   bool GetQmlHeadPrice(const int index, double &head, bool &demand) const
   {
      head = 0.0;
      demand = false;
      if(index < 0 || index >= m_count) return false;
      if(!MsnrIsQml(m_zones[index].msnrType) || m_zones[index].qmlHeadPrice <= 0.0)
         return false;
      head = m_zones[index].qmlHeadPrice;
      demand = (m_zones[index].msnrType == MSNR_QML_BUY);
      return true;
   }

   int FindBestZoneNearPrice(double price, ENUM_ZONE_TYPE type, double proximityPips)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      int bestIdx = -1; double bestScore = -1;
      for(int i = 0; i < m_count; i++) {
         if(!m_zones[i].isActive || m_zones[i].isMitigated || m_zones[i].isKingSNR) continue;
         bool isDemand = MsnrIsDemand(m_zones[i].msnrType);
         bool isSupply = MsnrIsSupply(m_zones[i].msnrType);
         if(type == ZONE_DEMAND && !isDemand) continue;
         if(type == ZONE_SUPPLY && !isSupply) continue;
         if(price >= m_zones[i].bottom - proximityPips * pip && price <= m_zones[i].top + proximityPips * pip) {
            if(m_zones[i].msnrScore > bestScore) {
               bestScore = m_zones[i].msnrScore;
               bestIdx = i;
            }
         }
      }
      return bestIdx;
   }

   // Mode 2 (SMC primary) soft overlay: best live MSNR map that geometrically
   // overlaps the SMC POI. Not an admission gate — no OTE / Layer-2 requirement.
   // Hybrid and MSNR-primary keep EvaluatePrimaryGate().
   int FindBestOverlappingMapZone(double areaBottom, double areaTop, ENUM_ZONE_TYPE type,
                                  double tolerancePips)
   {
      int bestIdx = -1;
      double bestScore = -1.0;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(pip <= 0.0) return -1;
      double tol = MathMax(MathMax(0.0, tolerancePips), DynamicProximityPips()) * pip;
      for(int i = 0; i < m_count; i++)
        {
         if(!m_zones[i].isActive || m_zones[i].isMitigated || m_zones[i].isKingSNR) continue;
         bool isDemand = MsnrIsDemand(m_zones[i].msnrType);
         bool isSupply = MsnrIsSupply(m_zones[i].msnrType);
         if((type == ZONE_DEMAND && !isDemand) || (type == ZONE_SUPPLY && !isSupply)) continue;
         bool aligned = false;
         if(m_requireM5Contained && !m_zones[i].isKeyLevel)
            aligned = (areaTop <= m_zones[i].top + point &&
                       areaBottom >= m_zones[i].bottom - point);
         else
            aligned = (areaTop >= m_zones[i].bottom - tol &&
                       areaBottom <= m_zones[i].top + tol);
         if(!aligned) continue;
         if(m_zones[i].msnrScore > bestScore)
           {
            bestScore = m_zones[i].msnrScore;
            bestIdx = i;
           }
        }
      return bestIdx;
   }

   bool EvaluatePrimaryGate(double areaBottom, double areaTop, ENUM_ZONE_TYPE type,
                            double tolerancePips, int &zoneIndex, int &failureCode)
   {
      zoneIndex = -1;
      failureCode = 1; // no aligned MSNR zone
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tol = MathMax(MathMax(0.0, tolerancePips), DynamicProximityPips()) * pip;
      double bestScore = -1.0;
      bool foundAlignedZone = false;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_zones[i].isActive || m_zones[i].isMitigated) continue;
         if(m_requireOTE && !m_zones[i].isInOTE) continue;
         bool isDemand = MsnrIsDemand(m_zones[i].msnrType);
         bool isSupply = MsnrIsSupply(m_zones[i].msnrType);
         if(m_zones[i].isKingSNR) continue;
         if((type == ZONE_DEMAND && !isDemand) || (type == ZONE_SUPPLY && !isSupply)) continue;
         bool aligned = false;
         // Thin A/V/OCL/SBR/RBS bands use overlap. Wide QML zones keep containment.
         if(m_requireM5Contained && !m_zones[i].isKeyLevel)
            aligned = (areaTop <= m_zones[i].top + point &&
                       areaBottom >= m_zones[i].bottom - point);
         else
            aligned = (areaTop >= m_zones[i].bottom - tol &&
                       areaBottom <= m_zones[i].top + tol);
         if(!aligned) continue;
         foundAlignedZone = true;

         // Overlap Logic: Layer-1 (MSNR/King SNR) must intersect Layer-2
         // (SMC OB/FVG M15) inside the OTE window to be considered valid.
         // Falls back to the legacy same-layer FVG flag when the Layer-2
         // gate is disabled (tuning/back-compat toggle).
         int smcIdx = m_layer2Index[i];
         bool qualifies = m_layer2Qualified[i];
         if(!qualifies) continue;
         if(m_zones[i].msnrScore > bestScore)
         {
            bestScore = m_zones[i].msnrScore;
            zoneIndex = i;
         }
      }
      if(zoneIndex >= 0)
        {
         failureCode = 0;
         return true;
        }
      failureCode = foundAlignedZone ? 2 : 1;
      return false;
   }

   double GetConfluenceBonus(double price, ENUM_ZONE_TYPE type, double proximityPips,
                             double maxBonus = 15.0)
   {
      int idx = FindBestZoneNearPrice(price, type, proximityPips);
      if(idx < 0 || maxBonus <= 0.0) return 0.0;
      return MathMin(maxBonus, MathMax(0.0, m_zones[idx].msnrScore) * maxBonus / 100.0);
   }

   double GetZoneWidthPips(int index)
   {
      if(index < 0 || index >= m_count) return 0.0;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      return (pip > 0.0) ? (m_zones[index].top - m_zones[index].bottom) / pip : 0.0;
   }

   // Nearest active opposing MSNR boundary used as a real structural target.
   // Returns zero when no target exists beyond entry in the trade direction.
   double GetNearestOpposingTarget(double entryPrice, ENUM_ZONE_TYPE entrySide)
   {
      double target = 0.0;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_zones[i].isActive || m_zones[i].isMitigated || m_zones[i].isKingSNR) continue;
         bool demand = MsnrIsDemand(m_zones[i].msnrType);
         bool supply = MsnrIsSupply(m_zones[i].msnrType);
         if(entrySide == ZONE_DEMAND && supply)
         {
            double candidate = m_zones[i].bottom;
            if(candidate > entryPrice && (target <= 0.0 || candidate < target)) target = candidate;
         }
         else if(entrySide == ZONE_SUPPLY && demand)
         {
            double candidate = m_zones[i].top;
            if(candidate < entryPrice && candidate > 0.0 && (target <= 0.0 || candidate > target)) target = candidate;
         }
      }
      return target;
   }

};

#endif
