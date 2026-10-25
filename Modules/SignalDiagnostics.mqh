//+------------------------------------------------------------------+
//|                                         SignalDiagnostics.mqh    |
//|             YANSTD EA — deduplicated rejection-funnel telemetry |
//|                          v2.0  |  2026-09-05                     |
//+------------------------------------------------------------------+
#ifndef YANSTD_SIGNALDIAGNOSTICS_MQH
#define YANSTD_SIGNALDIAGNOSTICS_MQH

#include "Defines.mqh"

#define YANSTD_DIAG_YEARS 24   // 2003..2026 index base
#define YANSTD_DIAG_YEAR0 2003

// H1: histogram of the NATURAL structural stop distance, sampled before any
// min/max policy is applied. 16 buckets x 5 pip = 0..80 pip, plus overflow.
#define YANSTD_NATSL_BUCKETS     17
#define YANSTD_NATSL_BUCKET_PIPS 5.0

class CSignalDiagnostics
  {
private:
   long     m_counts[SIGNAL_REJECT_REASON_COUNT];
   long     m_lastKeys[SIGNAL_REJECT_REASON_COUNT];
   long     m_evaluations;
   long     m_lastEvaluationKey;
   datetime m_lastSummaryTime;

   //---- execution-lifecycle counters ----------------------------------
   long     m_pendingPlaced;
   long     m_pendingFilled;
   long     m_pendingExpired;
   long     m_pendingCancelled;

   //---- integrity counters (all targets are ZERO) ---------------------
   long     m_clampedSL;              // H1: SL rewritten to min/max pip bound
   long     m_stagedExitFailures;     // H4: 50/25/25 split not broker-valid
   long     m_modifySL10016;          // H7: invalid-stops on SL modification
   long     m_redundantModify;        // modify skipped because SL/TP already match
   long     m_modifySL10016Recovered; // 10016 then a later attempt succeeded
   long     m_unprotectedPositions;   // H7: gave up protecting a position
   long     m_closedWithoutVariant;
   long     m_closedWithoutGrade;
   long     m_targetSourceCount[5];
   long     m_gapPauseEvents;
   long     m_timeInvalidationCloses; // H3: stagnant positions closed
   long     m_timeInvalidationRepeat; // H3: redundant close attempts for one ticket
   long     m_circuitBreakerHalts;    // L2: daily-loss / equity-DD halts
   long     m_fridayCloses;           // M2: Friday auto-close executions
   long     m_dataGapEvents;          // L4: detected missing M5 bar intervals
   long     m_dataGapMinutes;         // L4: total missing interval, bounded to one day/event
   long     m_dataGapUnexpected;
   long     m_dataGapSessionBreak;
   long     m_dataGapWeekendHoliday;
   long     m_lotClamp;
   long     m_lotFallback;
   long     m_structuralTargetOpen;
   long     m_structuralRRSamples;
   double   m_structuralRRSum;

   //---- H1: natural (pre-policy) stop distance distribution -----------
   // Record the natural stop before min/max policy. This preserves the original
   // structural distance even when execution caps a wider stop at 70 pip.
   long     m_natSLHist[YANSTD_NATSL_BUCKETS];
   long     m_natSLCount;
   double   m_natSLSum;
   double   m_natSLMin;
   double   m_natSLMax;

   double NatSLPercentile(double pct)
     {
      if(m_natSLCount <= 0) return 0.0;
      double target = (double)m_natSLCount * pct / 100.0;
      long   running = 0;
      for(int b = 0; b < YANSTD_NATSL_BUCKETS; b++)
        {
         if(m_natSLHist[b] <= 0) continue;
         if(running + m_natSLHist[b] >= target)
           {
            double lo = b * YANSTD_NATSL_BUCKET_PIPS;
            double within = (target - (double)running) / (double)m_natSLHist[b];
            return lo + within * YANSTD_NATSL_BUCKET_PIPS;
           }
         running += m_natSLHist[b];
        }
      return m_natSLMax;
     }

   //---- per-slice performance -----------------------------------------
   STradeBucketStats m_byVariant[ENTRY_VARIANT_COUNT];
   STradeBucketStats m_byGrade[11];           // 0-9 ENUM_SETUP_GRADE + 10 = unknown
   STradeBucketStats m_byDirection[2];        // 0 = BUY, 1 = SELL
   STradeBucketStats m_bySession[6];          // ENUM_SESSION_TYPE
   STradeBucketStats m_byYear[YANSTD_DIAG_YEARS];
   STradeBucketStats m_isSegment;             // L3 in-sample
   STradeBucketStats m_oosSegment;            // L3 out-of-sample

   datetime m_oosStart;                       // 0 = no split configured
   double   m_peakEquity;
   double   m_maxEquityDDPct;

   int      YearIndex(int year)
     {
      int idx = year - YANSTD_DIAG_YEAR0;
      if(idx < 0) idx = 0;
      if(idx >= YANSTD_DIAG_YEARS) idx = YANSTD_DIAG_YEARS - 1;
      return idx;
     }

   void PrintBucket(string label, const STradeBucketStats &b, bool withCI = false, bool skipEmpty = true)
     {
      if(skipEmpty && b.trades <= 0) return;
      string line = StringFormat("   %-22s n=%-6d WR=%5.1f%%  PF=%5.2f  ExpR=%+7.4f",
                                 label, b.trades, b.WinRate(), b.ProfitFactor(), b.ExpectancyR());
      if(withCI && b.trades >= 2)
         line += StringFormat("  95%%CI [%+6.3fR , %+6.3fR]",
                              b.ExpectancyR() - b.CI95HalfWidth(),
                              b.ExpectancyR() + b.CI95HalfWidth());
      Print("[YANSTD FINAL] ", line);
     }

public:
            CSignalDiagnostics() { Reset(); }

   void Reset()
     {
      for(int i = 0; i < SIGNAL_REJECT_REASON_COUNT; i++)
        {
         m_counts[i]   = 0;
         m_lastKeys[i] = -1;
        }
      m_evaluations    = 0;
      m_lastEvaluationKey = -1;
      m_lastSummaryTime = 0;

      m_pendingPlaced = m_pendingFilled = m_pendingExpired = m_pendingCancelled = 0;
      m_clampedSL = m_stagedExitFailures = m_modifySL10016 = 0;
      m_redundantModify = m_modifySL10016Recovered = 0;
      m_closedWithoutVariant = m_closedWithoutGrade = 0;
      m_gapPauseEvents = 0;
      for(int s = 0; s < 5; s++) m_targetSourceCount[s] = 0;
      m_unprotectedPositions = m_timeInvalidationCloses = m_timeInvalidationRepeat = 0;
      m_circuitBreakerHalts = m_fridayCloses = 0;
      m_dataGapEvents = m_dataGapMinutes = 0;
      m_dataGapUnexpected = m_dataGapSessionBreak = m_dataGapWeekendHoliday = 0;
      m_lotClamp = m_lotFallback = m_structuralTargetOpen = 0;
      m_structuralRRSamples = 0;
      m_structuralRRSum = 0.0;

      for(int i = 0; i < YANSTD_NATSL_BUCKETS; i++) m_natSLHist[i] = 0;
      m_natSLCount = 0;
      m_natSLSum   = 0.0;
      m_natSLMin   = 0.0;
      m_natSLMax   = 0.0;

      for(int i = 0; i < ENTRY_VARIANT_COUNT; i++) m_byVariant[i].Reset();
      for(int i = 0; i < 11; i++)                  m_byGrade[i].Reset();
      for(int i = 0; i < 2; i++)                   m_byDirection[i].Reset();
      for(int i = 0; i < 6; i++)                   m_bySession[i].Reset();
      for(int i = 0; i < YANSTD_DIAG_YEARS; i++)   m_byYear[i].Reset();
      m_isSegment.Reset();
      m_oosSegment.Reset();

      m_oosStart     = 0;
      m_peakEquity   = 0.0;
      m_maxEquityDDPct = 0.0;
     }

   // L3: trades closed at or after this timestamp are attributed to the
   // out-of-sample segment. 0 disables the split (everything is in-sample).
   void SetOOSStart(datetime oosStart) { m_oosStart = oosStart; }

   string Label(ENUM_SIGNAL_REJECT_REASON reason) const
     {
      switch(reason)
        {
         case REJECT_NO_ACTIVE_POI:       return "NO_ACTIVE_POI";
         case REJECT_SPREAD:              return "SPREAD";
         case REJECT_SPREAD_ATR:          return "SPREAD_GT_ATR_CAP";
         case REJECT_ADX_GUARD:           return "ADX_M15_HARD_GATE";
         case REJECT_ADX_SOFT_PENALTY:    return "ADX_M15_SOFT_PENALTY";
         case REJECT_NOT_IN_KILLZONE:    return "NOT_IN_KILLZONE";
         case REJECT_NOT_FRESH:          return "MSNR_NOT_FRESH";
         case REJECT_MIN_RRR:             return "STRUCTURAL_TARGET_LT_MIN_RRR";
         case REJECT_SL_OUT_OF_RANGE:     return "STRUCTURAL_SL_OUT_OF_RANGE";
         case REJECT_DATA_UNAVAILABLE:    return "DATA_UNAVAILABLE";
         case REJECT_DIRECTION_BIAS:      return "M15_DIRECTION_BIAS";
         case REJECT_MSNR_ZONE:           return "MSNR_ZONE_NOT_ALIGNED";
         case REJECT_MSNR_FVG:            return "MSNR_M15_SMC_OB_OR_FVG_OVERLAP_MISSING";
         case REJECT_SOFT_SCORE:          return "INSTITUTIONAL_SOFT_SCORE";
         case REJECT_POI_INVALIDATED:     return "POI_INVALIDATED";
         case REJECT_INDUCEMENT_PENALTY:  return "INDUCEMENT_PENALTY";
         case REJECT_NOT_IN_POI:          return "PRICE_NOT_IN_POI";
         case REJECT_CHOCH_NOT_CONFIRMED: return "CHOCH_NOT_CONFIRMED";
         case REJECT_CHOCH_TIMEOUT:       return "CHOCH_TIMEOUT";
         case REJECT_SWEEP_NOT_CONFIRMED: return "M3_SWEEP_NOT_CONFIRMED";
         case REJECT_OB_NO_FVG:           return "M3_OB_MISSING_DISPLACEMENT_FVG";
         case REJECT_M3_OUTSIDE_PARENT_ZONE: return "M3_OUTSIDE_PARENT_M5";
         case REJECT_LAYER_DUPLICATE:     return "LAYER_DUPLICATE";
         case REJECT_POSITION_LIMIT:      return "POSITION_LIMIT";
         case REJECT_DISTANCE:            return "ENTRY_DISTANCE";
         case REJECT_REENTRY_COOLDOWN:    return "REENTRY_COOLDOWN";
         case REJECT_TIME_FILTER:         return "TIME_FILTER";
         case REJECT_GAP_PAUSE:           return "GAP_PAUSE";
         case REJECT_DAILY_LOSS:          return "DAILY_LOSS_GUARD";
         case REJECT_NEWS:                return "NEWS_FILTER";
         case REJECT_AGGREGATE_RISK:      return "AGGREGATE_RISK";
         case REJECT_PENDING_LIMIT:       return "PENDING_LIMIT";
         case REJECT_ORDER_SEND:          return "ORDER_SEND";
         case REJECT_MARGIN_LEVEL:        return "MARGIN_LEVEL_GUARD";
         case REJECT_LOT_TOO_SMALL:       return "LOT_BELOW_BROKER_MIN";
         case REJECT_SL_BELOW_MIN:        return "SL_TIGHTER_THAN_MIN_SKIPPED";
         case REJECT_SL_ABOVE_MAX:        return "SL_WIDER_THAN_MAX";
         case REJECT_VARIANT_NOT_ALLOWED: return "VARIANT_NOT_WHITELISTED";
         case REJECT_CLUSTER_TOO_CLOSE:   return "SIBLING_TOO_CLOSE_MERGE";
         case REJECT_ENTRY_TOO_FAR:       return "ENTRY_BEYOND_MAX_ATR_DISTANCE";
         case REJECT_POI_STALE:           return "POI_EXCEEDED_MAX_AGE";
         case REJECT_SUNDAY_OPEN:         return "SUNDAY_REOPEN_WINDOW";
         case REJECT_EQUITY_DD:           return "EQUITY_DRAWDOWN_BREAKER";
         case REJECT_SETUP_GRADE:         return "SETUP_GRADE_D";
         case REJECT_ENTRY_STOPS_DISTANCE: return "ENTRY_STOPS_DISTANCE";
         default:                         return "UNKNOWN";
        }
     }

   void MarkEvaluation(long uniqueKey)
     {
      if(uniqueKey != 0 && m_lastEvaluationKey == uniqueKey) return;
      m_evaluations++;
      if(uniqueKey != 0) m_lastEvaluationKey = uniqueKey;
     }

   void Record(ENUM_SIGNAL_REJECT_REASON reason, long uniqueKey = 0)
     {
      int idx = (int)reason;
      if(idx < 0 || idx >= SIGNAL_REJECT_REASON_COUNT) return;
      // Count category presence once per market minute. A candidate key alone
      // is insufficient because cycling many POIs makes the previous key recur
      // on every tick and inflates counts by millions.
      long minuteKey = (long)TimeCurrent() / 60;
      if(minuteKey != 0 && m_lastKeys[idx] == minuteKey) return;
      m_counts[idx]++;
      if(minuteKey != 0) m_lastKeys[idx] = minuteKey;
     }

   long GetCount(ENUM_SIGNAL_REJECT_REASON reason) const
     {
      int idx = (int)reason;
      return (idx >= 0 && idx < SIGNAL_REJECT_REASON_COUNT) ? m_counts[idx] : 0;
     }

   long GetTotalRejects() const
     {
      long total = 0;
      for(int i = 0; i < SIGNAL_REJECT_REASON_COUNT; i++) total += m_counts[i];
      return total;
     }

   //+------------------------------------------------------------------+
   //| Execution-lifecycle telemetry                                     |
   //+------------------------------------------------------------------+
   void RecordPendingPlaced()    { m_pendingPlaced++; }
   void RecordPendingFilled()    { m_pendingFilled++; }
   void RecordPendingExpired()   { m_pendingExpired++; }
   void RecordPendingCancelled() { m_pendingCancelled++; }
   // AUDIT FIX (#11): removed unused GetPendingPlaced/Filled/Expired/Cancelled().
   // PrintSummary()/PrintFinalSummary() read m_pendingPlaced etc. directly;
   // these public getters were never called from anywhere.

  void RecordClampedSL()        { m_clampedSL++; }
  // AUDIT FIX (#11): removed unused GetClampedSL() -- same reasoning as above.

  // H1 — the RAW structural stop distance, recorded before the min/max policy
  // runs, so the operator can calibrate InpMinSLPips / InpMaxSLPips against
  // the structure the EA actually finds instead of against a guess.
  void RecordNaturalSL(double pips)
    {
      if(pips <= 0.0) return;
      m_natSLCount++;
      m_natSLSum += pips;
      if(m_natSLMin <= 0.0 || pips < m_natSLMin) m_natSLMin = pips;
      if(pips > m_natSLMax) m_natSLMax = pips;
      int b = (int)MathFloor(pips / YANSTD_NATSL_BUCKET_PIPS);
      if(b < 0) b = 0;
      if(b >= YANSTD_NATSL_BUCKETS) b = YANSTD_NATSL_BUCKETS - 1;
      m_natSLHist[b]++;
     }

   // H4 — a position whose 50/25/25 split could not be expressed in broker
   // volume. The audit measured 1,325 of these (37.8% of all trades).
   void RecordStagedExitFailure()    { m_stagedExitFailures++; }
   // AUDIT FIX (#11): removed unused GetStagedExitFailures().

   // H7 — TRADE_RETCODE_INVALID_STOPS on a protective stop modification.
   void RecordModifySL10016()     { m_modifySL10016++; }
   void RecordRedundantModify()   { m_redundantModify++; }
   void RecordModifySL10016Recovered() { m_modifySL10016Recovered++; }
   void RecordUnprotectedPosition() { m_unprotectedPositions++; }
   void RecordGapPause()          { m_gapPauseEvents++; }

   // H3 — time invalidation. `repeat` distinguishes the first close request
   // for a ticket from the redundant re-requests that produced 4,290 journal
   // lines for 154 distinct tickets in the measured run.
   void RecordTimeInvalidation(bool repeat)
     {
      if(repeat) m_timeInvalidationRepeat++;
      else       m_timeInvalidationCloses++;
     }
   // AUDIT FIX (#11): removed unused GetTimeInvalidationCloses()/GetTimeInvalidationRepeat().

   // L2 — circuit-breaker activations.
   void RecordCircuitBreakerHalt() { m_circuitBreakerHalts++; }
   // M2 — Friday auto-close executions (the audit found ~2.8% of Fridays).
   void RecordFridayClose()        { m_fridayCloses++; }
   // AUDIT FIX (#11): removed unused GetFridayCloses().

   // L4: record only finite intraday gaps; normal weekend closure is not a data
   // quality defect. The caller supplies the observed bar interval.
   void RecordDataGap(long missingMinutes)
     {
      RecordDataGap(missingMinutes, DATA_GAP_UNEXPECTED);
     }
   void RecordDataGap(long missingMinutes, ENUM_DATA_GAP_KIND kind)
     {
      if(missingMinutes <= 0 || kind == DATA_GAP_NONE) return;
      if(kind == DATA_GAP_UNEXPECTED)
        {
         m_dataGapEvents++;
         m_dataGapMinutes += missingMinutes;
         m_dataGapUnexpected++;
        }
      else if(kind == DATA_GAP_NORMAL_SESSION_BREAK)
         m_dataGapSessionBreak++;
      else if(kind == DATA_GAP_WEEKEND_OR_HOLIDAY)
         m_dataGapWeekendHoliday++;
     }
   void RecordLotClamp() { m_lotClamp++; }
   void RecordLotFallback() { m_lotFallback++; }
   void RecordStructuralTargetOpen() { m_structuralTargetOpen++; }
   void RecordTargetSource(ENUM_TARGET_SOURCE src)
     {
      int i = (int)src;
      if(i >= 0 && i < 5) m_targetSourceCount[i]++;
     }
   void RecordStructuralRR(const double rr)
     {
      if(rr <= 0.0) return;
      m_structuralRRSamples++;
      m_structuralRRSum += rr;
     }
   long LotClampCount() const { return m_lotClamp; }
   long LotFallbackCount() const { return m_lotFallback; }
   // AUDIT FIX (#11): removed unused GetDataGapEvents()/GetDataGapMinutes().
   // See CHANGELOG.md for the full list of removed getters (#11); counters
   // remain fully recorded and are read directly by PrintSummary()/
   // PrintFinalSummary().

   //+------------------------------------------------------------------+
   //| Closed-trade attribution                                          |
   //+------------------------------------------------------------------+
   // Called once per completed position from OnTradeTransaction.
   void RecordClosedTrade(double profit, double rMultiple, int direction,
                          int variant, ENUM_SESSION_TYPE session,
                          datetime closeTimeUTC, int grade = -1)
     {
      int vi = variant;
      if(vi >= 0 && vi < ENTRY_VARIANT_COUNT) m_byVariant[vi].Add(profit, rMultiple);
      else m_closedWithoutVariant++;

      int gi = grade;
      if(gi >= 0 && gi <= 9) m_byGrade[gi].Add(profit, rMultiple);
      else
        {
         m_byGrade[10].Add(profit, rMultiple);
         m_closedWithoutGrade++;
        }

      int di = (direction == POSITION_TYPE_BUY) ? 0 : 1;
      m_byDirection[di].Add(profit, rMultiple);

      int si = (int)session;
      if(si >= 0 && si < 6) m_bySession[si].Add(profit, rMultiple);

      MqlDateTime dt;
      TimeToStruct(closeTimeUTC, dt);
      m_byYear[YearIndex(dt.year)].Add(profit, rMultiple);

      if(m_oosStart > 0 && closeTimeUTC >= m_oosStart) m_oosSegment.Add(profit, rMultiple);
      else                                             m_isSegment.Add(profit, rMultiple);
     }

   //+------------------------------------------------------------------+
   //| L2 — equity drawdown tracking (called every tick, O(1))           |
   //+------------------------------------------------------------------+
   void UpdateEquityPeak()
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0) return;
      if(equity > m_peakEquity) m_peakEquity = equity;
      if(m_peakEquity > 0.0)
        {
         double ddPct = (m_peakEquity - equity) / m_peakEquity * 100.0;
         if(ddPct > m_maxEquityDDPct) m_maxEquityDDPct = ddPct;
        }
     }
   double GetEquityDDPct() const { return m_maxEquityDDPct; }

   //+------------------------------------------------------------------+
   //| L5 — compact monthly heartbeat (was 14 lines x 236 blocks)        |
   //+------------------------------------------------------------------+
   void PrintMonthlySummary(int activePOIs, int totalTrades, int totalWins, double balance)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      double fillRate = (m_pendingPlaced > 0)
                        ? 100.0 * (double)m_pendingFilled / (double)m_pendingPlaced : 0.0;
      Print("[YANSTD MONTHLY] ", StringFormat("%04d.%02d", dt.year, dt.mon),
            " | Balance=", DoubleToString(balance, 2),
            " | Trades=", totalTrades,
            " | WR=", DoubleToString(CalcWinRate(totalWins, totalTrades), 1), "%",
            " | ActivePOIs=", activePOIs,
            " | Pending fill=", DoubleToString(fillRate, 1), "%",
            " (", m_pendingFilled, "/", m_pendingPlaced, ")",
            " | SLclamped=", m_clampedSL,
            " | stagedFail=", m_stagedExitFailures,
            " | sl10016=", m_modifySL10016);
     }

   void PrintSummary(string trigger = "PERIODIC")
     {
      long total = GetTotalRejects();
      Print("[YANSTD DIAGNOSTIC] ", trigger,
            " | Evaluations=", m_evaluations,
            " | Category-minute occurrences=", total);
      if(total <= 0) return;
      for(int i = 0; i < SIGNAL_REJECT_REASON_COUNT; i++)
        {
         if(m_counts[i] <= 0) continue;
         double pct = 100.0 * (double)m_counts[i] / (double)total;
         Print("[YANSTD DIAGNOSTIC] ", Label((ENUM_SIGNAL_REJECT_REASON)i),
               "=", m_counts[i], " (", DoubleToString(pct, 2), "%)");
        }
      m_lastSummaryTime = TimeCurrent();
     }

   //+------------------------------------------------------------------+
   //| L5 — end-of-run report. Every line here is a number the audit     |
   //| had to reconstruct from a 25 MB journal after the fact.           |
   //+------------------------------------------------------------------+
   void PrintFinalSummary(string trigger = "DEINIT")
     {
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Print("[YANSTD FINAL] ", trigger, " — RUN SUMMARY");
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

      //---- Section 1: integrity counters. All four targets are ZERO. ----
      Print("[YANSTD FINAL] — INTEGRITY COUNTERS (target = 0)");
      Print("[YANSTD FINAL]   SL clamped to min/max pip bound (H1) : ", m_clampedSL,
            (m_clampedSL == 0 ? "  OK" : "  <-- R:R, lot size and TP distance were computed from a fabricated stop"));
      Print("[YANSTD FINAL]   Staged exits not broker-valid (H4)   : ", m_stagedExitFailures,
            (m_stagedExitFailures == 0 ? "  OK" : "  <-- TP2/runner never existed for these trades"));
      Print("[YANSTD FINAL]   SafeModifySL error 10016 (H7)        : ", m_modifySL10016,
            (m_modifySL10016 == 0 ? "  OK" : "  <-- broker rejected an attempted SL upgrade"));
      Print("[YANSTD FINAL]   Redundant modify skipped            : ", m_redundantModify);
      Print("[YANSTD FINAL]   10016 recovered on retry            : ", m_modifySL10016Recovered);
      Print("[YANSTD FINAL]   Redundant time-invalidation retries  : ", m_timeInvalidationRepeat,
            (m_timeInvalidationRepeat == 0 ? "  OK" : "  <-- close request required escalation"));
      Print("[YANSTD FINAL]   Positions with no server SL after failure: ", m_unprotectedPositions);
      Print("[YANSTD FINAL]   Time invalidation closes (H3)        : ", m_timeInvalidationCloses,
            " (distinct tickets closed)");

      //---- Section 1b: H1 stop-distance calibration -------------------
      if(m_natSLCount > 0)
        {
         Print("[YANSTD FINAL] — NATURAL STOP DISTANCE, BEFORE MIN/MAX POLICY (H1)");
         Print("[YANSTD FINAL]   Samples=", m_natSLCount,
               " | min=", DoubleToString(m_natSLMin, 1),
               " pip | avg=", DoubleToString(m_natSLSum / (double)m_natSLCount, 1),
               " pip | max=", DoubleToString(m_natSLMax, 1), " pip");
         Print("[YANSTD FINAL]   Percentiles: p05=", DoubleToString(NatSLPercentile(5.0), 1),
               " p10=", DoubleToString(NatSLPercentile(10.0), 1),
               " p25=", DoubleToString(NatSLPercentile(25.0), 1),
               " p50=", DoubleToString(NatSLPercentile(50.0), 1),
               " p75=", DoubleToString(NatSLPercentile(75.0), 1),
               " p90=", DoubleToString(NatSLPercentile(90.0), 1),
               " p95=", DoubleToString(NatSLPercentile(95.0), 1), " pip");
         Print("[YANSTD FINAL]   HOW TO USE: natural SL is preserved up to InpMaxSLPips;",
               " wider setups stay eligible and execute at the configured hard cap.",
               " InpMinSLPips remains the lower acceptance floor.");
         string h1line = "[YANSTD FINAL]   Hist ";
         for(int b = 0; b < YANSTD_NATSL_BUCKETS; b++)
           {
            if(m_natSLHist[b] <= 0) continue;
            string lbl = (b == YANSTD_NATSL_BUCKETS - 1)
                         ? ("80+")
                         : DoubleToString(b * YANSTD_NATSL_BUCKET_PIPS, 0);
            double share = 100.0 * (double)m_natSLHist[b] / (double)m_natSLCount;
            h1line += lbl + "p:" + DoubleToString(share, 1) + "%  ";
           }
         Print(h1line);
        }

      //---- Section 2: pending-order lifecycle (M5 fill rate) ----------
      if(m_pendingPlaced > 0)
        {
         double fillRate = 100.0 * (double)m_pendingFilled / (double)m_pendingPlaced;
         Print("[YANSTD FINAL] — PENDING ORDER LIFECYCLE (M5)");
         Print("[YANSTD FINAL]   Placed=", m_pendingPlaced,
               " | Filled=", m_pendingFilled,
               " | Expired=", m_pendingExpired,
               " | Cancelled=", m_pendingCancelled);
         Print("[YANSTD FINAL]   Fill rate=", DoubleToString(fillRate, 2), "%",
               (fillRate >= 55.0 ? "  OK (>=55%)" : "  <-- below the 55% target; extend InpLimitExpirationBars or tighten InpMaxEntryDistanceATR"));
        }

      //---- Section 3: protection / risk events ------------------------
      Print("[YANSTD FINAL] — PROTECTION EVENTS");
      Print("[YANSTD FINAL]   Circuit-breaker halts (L2) : ", m_circuitBreakerHalts);
      Print("[YANSTD FINAL]   Friday auto-closes (M2)    : ", m_fridayCloses,
            (m_fridayCloses > 0 ? "  OK (feature is live)" : "  <-- never fired; verify the weekend-close trigger"));
      Print("[YANSTD FINAL]   Max equity drawdown (L2)   : ", DoubleToString(m_maxEquityDDPct, 2), "%");
      Print("[YANSTD FINAL]   Data gaps unexpected (L4)   : ", m_dataGapUnexpected,
            " events / ", m_dataGapMinutes, " missing minutes");
      Print("[YANSTD FINAL]   Session breaks (normal)     : ", m_dataGapSessionBreak);
      Print("[YANSTD FINAL]   Weekend/holiday gaps        : ", m_dataGapWeekendHoliday);
      Print("[YANSTD FINAL]   LOT_CLAMP / LOT_FALLBACK    : ", m_lotClamp, " / ", m_lotFallback);
      Print("[YANSTD FINAL]   LOT_POLICY_CAP / LOT_MAX_CLAMP: ", g_lotPolicyCapCount, " / ", g_lotMaxClampCount,
            (g_lotMaxClampCount > 0 ? "  <-- broker SYMBOL_VOLUME_MAX absorbed a request; lower InpMaxLot or InpRiskPercent" : ""));
      Print("[YANSTD FINAL]   STRUCTURAL_TARGET_OPEN      : ", m_structuralTargetOpen);
      Print("[YANSTD FINAL]   Target source PERSISTED / MSNR / M15 / EMERGENCY : ",
            m_targetSourceCount[1], " / ", m_targetSourceCount[2], " / ",
            m_targetSourceCount[3], " / ", m_targetSourceCount[4]);
      if(m_structuralTargetOpen > 0 && m_pendingFilled > 0 &&
         m_targetSourceCount[4] * 10 > m_pendingFilled)
         Print("[YANSTD FINAL]   WARNING: emergency 4R target >10% of fills");
      Print("[YANSTD FINAL]   Gap-pause activations             : ", m_gapPauseEvents);
      if(m_structuralRRSamples > 0)
         Print("[YANSTD FINAL]   Structural RR samples       : ", m_structuralRRSamples,
               " avg=", DoubleToString(m_structuralRRSum / (double)m_structuralRRSamples, 2));

      //---- Section 4: performance slices ------------------------------
      Print("[YANSTD FINAL] — PERFORMANCE BY DIRECTION (M8)");
      PrintBucket("BUY",  m_byDirection[0], true);
      PrintBucket("SELL", m_byDirection[1], true);

      Print("[YANSTD FINAL] — PERFORMANCE BY SESSION (M1)");
      string sessNames[6] = {"NONE","ASIA","LONDON","NEWYORK","OVERLAP","UNKNOWN"};
      for(int i = 0; i < 6; i++) PrintBucket(sessNames[i], m_bySession[i]);

      Print("[YANSTD FINAL] — PERFORMANCE BY ENTRY VARIANT (H2)");
      Print("[YANSTD FINAL]   closed without variant : ", m_closedWithoutVariant);
      string varNames[ENTRY_VARIANT_COUNT] = {"OB_15","OB_45","FVG_50","FIB_618","FIB_705","FIB_790"};
      for(int i = 0; i < ENTRY_VARIANT_COUNT; i++) PrintBucket(varNames[i], m_byVariant[i], false, false);

      Print("[YANSTD FINAL] — PERFORMANCE BY GRADE");
      Print("[YANSTD FINAL]   closed without grade   : ", m_closedWithoutGrade);
      string gradeNames[11] = {"S+","S","A+","A","B+","B","C+","C","D+","D","UNKNOWN"};
      for(int i = 0; i < 11; i++) PrintBucket(gradeNames[i], m_byGrade[i], false, false);

      //---- Section 5: L3 in-sample / out-of-sample --------------------
      if(m_oosStart > 0)
        {
         Print("[YANSTD FINAL] — IS / OOS SPLIT (L3)");
         Print("[YANSTD FINAL]   OOS boundary=", TimeToString(m_oosStart, TIME_DATE));
         PrintBucket("IN-SAMPLE",     m_isSegment, true);
         PrintBucket("OUT-OF-SAMPLE", m_oosSegment, true);
         Print("[YANSTD FINAL]   NOTE: OOS profit factor is the only figure that carries",
               " evidential weight. An IS PF above 1.10 with a materially lower OOS PF indicates curve-fitting.");
        }

      //---- Section 6: L6 per-year with confidence intervals -----------
      Print("[YANSTD FINAL] — PER YEAR WITH 95% CONFIDENCE INTERVAL (L6)");
      Print("[YANSTD FINAL]   Year    n     WR%     PF    ExpR      95% CI on ExpR      readable?");
      for(int i = 0; i < YANSTD_DIAG_YEARS; i++)
        {
         if(m_byYear[i].trades <= 0) continue;
         double half = m_byYear[i].CI95HalfWidth();
         // A year with <100 trades cannot support a conclusion: the CI is
         // wider than the effect it is meant to measure.
         bool readable = (m_byYear[i].trades >= 100);
         Print("[YANSTD FINAL]   ", YANSTD_DIAG_YEAR0 + i,
               StringFormat("  %5d  %5.1f  %5.2f  %+7.4f   [%+6.3f , %+6.3f]   %s",
                            m_byYear[i].trades, m_byYear[i].WinRate(),
                            m_byYear[i].ProfitFactor(), m_byYear[i].ExpectancyR(),
                            m_byYear[i].ExpectancyR() - half,
                            m_byYear[i].ExpectancyR() + half,
                            readable ? "yes" : "NO (n<100)"));
        }

      //---- Section 7: rejection funnel --------------------------------
      PrintSummary(trigger);
      Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
     }
  };

#endif // YANSTD_SIGNALDIAGNOSTICS_MQH
