//+------------------------------------------------------------------+
//|                                                SignalEngine.mqh  |
//|                    YANSTD EA — Hybrid MSNR + SMC Signal Engine   |
//|                    (MSNR Mapping -> M15 Bias -> M5 POI -> M3)    |
//|                                   v4.0   |  2026-08-31           |
//+------------------------------------------------------------------+
#ifndef YANSTD_SIGNALENGINE_MQH
#define YANSTD_SIGNALENGINE_MQH

#include "Defines.mqh"
#include "FVGValidator.mqh"
#include "ZigZagEngine.mqh"
#include "RiskCalculator.mqh"
#include "SmartBrain.mqh"
#include "SessionManager.mqh"
#include "SignalDiagnostics.mqh"
#include "MSNREngine.mqh"

class CSignalEngine
{
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_htfPeriod;       // PERIOD_M15
   ENUM_TIMEFRAMES  m_mtfPeriod;       // PERIOD_M5
   ENUM_TIMEFRAMES  m_ltfPeriod;       // PERIOD_M3

   // ZigZag Parameters
   int              m_m15Depth, m_m15Dev, m_m15Back;
   int              m_m5Depth,  m_m5Dev,  m_m5Back;
   int              m_m3Depth,  m_m3Dev,  m_m3Back;

   // MSNR Engine Dependency
   CMSNREngine     *m_msnr;
   bool             m_useMSNR;

   // SMC Precision Rules
   double           m_fvgMinMultiplier;// FVG Gap multiplier * Spread
   double           m_fibMatchTolerance;// Nearest discrete Fibonacci ratio tolerance
   int              m_zoneMaxBars;     // Bar expiration limit for M5 POI Zone
   int              m_poiScanBars;     // Configurable M5 historical POI lookback
   double           m_slBufferPips;    // Buffer SL in pips
   int              m_maxSpreadPoints; // Max spread allowed in points
   double           m_minSLPips;       // Min broker-digit-aware pip distance
   double           m_maxSLPips;       // Max broker-digit-aware pip distance
   int              m_poiInvalidationCloses;
   double           m_poiInvalidationBufferPips;

   // Risk-reward targets
   double           m_tp1RR;
   double           m_tp2RR;
   double           m_poiPartialPips;
   bool             m_useDynamicRisk;
   double           m_maxAggregateRiskPct;
   bool             m_useDynamicSLBuffer;
   double           m_slATRMult;
   int              m_atrPeriod;   // ATR Engine: period for dynamic SL buffer/bounds (default 14)
   double           m_fvgATRMult;  // ATR Engine: M5 FVG min gap = ATR(M5) * this (default 0.30)
   bool             m_useATRStopBounds;
   double           m_slMinATRMult;
   double           m_slMaxATRMult;
   bool             m_useLiquiditySweepBoost;
   bool             m_requireM3Sweep;   // v4.34: joint Tahap-4 gate (sweep AND CHoCH)
   bool             m_useOTEBoost;

   bool             m_brainExplorationMode;

   double           m_minSoftScore;
   bool             m_allowCounterBias;
   int              m_counterBiasStagnationBars;
   double           m_counterBiasMinScore;
   int              m_chochTransitionMaxBars;
   bool             m_useADXSoftFeature;
   double           m_marketADX;
   double           m_plusDI;
   double           m_minusDI;
   double           m_minADX;
   double           m_adxSoftPenalty;
   ENUM_SETUP_MODE m_setupMode;
   int              m_pureLadder;

   // Active POI Storage — circular buffer. Logical index 0 is the oldest
   // live zone; physical slot = (m_poiHead + logical) % MAX_ZONES. Eviction
   // of the oldest entry is O(1) (advance head) instead of shifting 299
   // fat SMC_Zone structs.
   SMC_Zone         m_poiStore[MAX_ZONES];
   int              m_poiCount;
   int              m_poiHead;
   long             m_poiRevision;
   long             m_poiObjSeq;   // AUDIT FIX: monotonic counter for unique object names

   // Structure event history (chart/attribution only; never read by entry logic).
   SStructureEvent  m_m15Events[YANSTD_STRUCT_EVENT_MAX];
   int              m_m15EventCount;
   SStructureEvent  m_m3Events[YANSTD_STRUCT_EVENT_MAX];
   int              m_m3EventCount;

   int PoiPhys(const int logical) const
     {
      return (m_poiHead + logical) % MAX_ZONES;
     }

   void EvictOldestPOI()
     {
      if(m_poiCount <= 0) return;
      int phys = PoiPhys(0);
      ObjectDelete(0, m_poiStore[phys].objName);
      ObjectDelete(0, m_poiStore[phys].objName + "_LBL");
      ObjectDelete(0, m_poiStore[phys].fvgObjName);
      ObjectDelete(0, m_poiStore[phys].fvgObjName + "_LBL");
      m_poiHead = (m_poiHead + 1) % MAX_ZONES;
      m_poiCount--;
      m_poiRevision++;
     }

   // One-pass compact that keeps chronological order in the ring so logical 0
   // stays the oldest live zone (required by EvictOldestPOI).
   void CompactExpiredPOIs()
     {
      int n = m_poiCount;
      int write = 0;
      for(int i = 0; i < n; i++)
        {
         int src = PoiPhys(i);
         m_poiStore[src].barAge++;
         bool lostPrimaryAlignment = false;
         if(m_useMSNR && m_msnr != NULL)
           {
            m_poiStore[src].primaryMSNRZoneIdx =
               m_msnr.FindBestOverlappingMapZone(m_poiStore[src].bottom,
                                                 m_poiStore[src].top,
                                                 m_poiStore[src].type, 3.0);
           }
         if((m_zoneMaxBars > 0 && m_poiStore[src].barAge > m_zoneMaxBars) ||
            m_poiStore[src].isMitigated || !m_poiStore[src].isActive || lostPrimaryAlignment)
           {
            ObjectDelete(0, m_poiStore[src].objName);
            ObjectDelete(0, m_poiStore[src].objName + "_LBL");
            ObjectDelete(0, m_poiStore[src].fvgObjName);
            ObjectDelete(0, m_poiStore[src].fvgObjName + "_LBL");
            continue;
           }
         int dst = PoiPhys(write);
         if(dst != src)
            m_poiStore[dst] = m_poiStore[src];
         write++;
        }
      if(write != n)
         m_poiRevision++;
      m_poiCount = write;
     }


   // Engine & AI Dependencies
   CZigZagEngine    m_zz;
   CSmartBrain     *m_brain;
   CSessionManager *m_session;
   CSignalDiagnostics *m_diagnostics;
   CRiskCalculator  m_rc;

   // Last Evaluated State
   ENUM_SIGNAL_TYPE m_structureTrend;  // Macro Market Structure (BOS HH / LL)
   ENUM_SIGNAL_TYPE m_htfBias;         // Pro-Trend Qualified Bias (Discount Longs / Premium Shorts)
   double           m_m15Equilibrium;
   double           m_m15SwingHigh;
   double           m_m15SwingLow;
   bool             m_m15HaveStructure;
   SMC_SwingPoint   m_m15LastHigh;
   SMC_SwingPoint   m_m15PrevHigh;
   SMC_SwingPoint   m_m15LastLow;
   SMC_SwingPoint   m_m15PrevLow;
   double           m_protectedHigh;
   double           m_protectedLow;
   ENUM_STRUCTURE_EVENT m_lastStructureEvent;
   double           m_lastBreakLevel;
   datetime         m_lastBreakTime;
   datetime         m_structureTrendSince;
   ENUM_SIGNAL_TYPE m_pendingReversal;      // CHoCH direction awaiting confirming BOS
   datetime         m_pendingReversalSince;
   // M3 micro-structure state (chart/attribution only; never gates entries)
   ENUM_SIGNAL_TYPE m_m3Trend;
   double           m_m3ProtectedHigh;
   double           m_m3ProtectedLow;
   ENUM_SIGNAL_TYPE m_m3PendingReversal;
   datetime         m_m3PendingSince;
   datetime         m_m3LastBar;
   double           m_trendBullPct;
   datetime         m_cachedLTFStructureBar;
   bool             m_cachedHaveLTFStructure;
   SMC_SwingPoint   m_cachedLTFHigh;
   SMC_SwingPoint   m_cachedLTFPrevHigh;
   SMC_SwingPoint   m_cachedLTFLow;
   SMC_SwingPoint   m_cachedLTFPrevLow;

public:
   CSignalEngine() : m_symbol(""),
                     m_htfPeriod(PERIOD_M15), m_mtfPeriod(PERIOD_M5), m_ltfPeriod(PERIOD_M3),
                     m_m15Depth(12), m_m15Dev(5), m_m15Back(3),
                     m_m5Depth(8),   m_m5Dev(3),  m_m5Back(3),
                     m_m3Depth(5),   m_m3Dev(2),  m_m3Back(2),
                     m_fvgMinMultiplier(1.5), m_fibMatchTolerance(0.030),
                     m_zoneMaxBars(50), m_poiScanBars(1200),
                     m_slBufferPips(1.5), m_maxSpreadPoints(50),
                      m_minSLPips(0.0), m_maxSLPips(0.0),
                     m_poiInvalidationCloses(2), m_poiInvalidationBufferPips(8.0),
                     m_tp1RR(1.5), m_tp2RR(2.0), m_poiPartialPips(80.0),
                     m_useDynamicRisk(true), m_useDynamicSLBuffer(true), m_slATRMult(0.20),
                     m_maxAggregateRiskPct(0.0),
                     m_useATRStopBounds(true), m_slMinATRMult(0.35), m_slMaxATRMult(2.50),
                     m_useLiquiditySweepBoost(true), m_requireM3Sweep(true), m_useOTEBoost(true), 

                      m_brainExplorationMode(false),
 m_minSoftScore(45.0),
                     m_allowCounterBias(true), m_counterBiasStagnationBars(16),
                     m_counterBiasMinScore(75.0), m_chochTransitionMaxBars(12),
                     m_useADXSoftFeature(false), m_marketADX(0.0),
                     m_plusDI(0.0), m_minusDI(0.0),
                     m_minADX(20.0), m_adxSoftPenalty(10.0),
                     m_poiCount(0), m_poiHead(0), m_poiRevision(0), m_poiObjSeq(0), m_msnr(NULL), m_useMSNR(true),
                     m_brain(NULL), m_session(NULL), m_diagnostics(NULL),
                     m_structureTrend(SIGNAL_NONE),
                     m_htfBias(SIGNAL_NONE), m_m15Equilibrium(0.0),
                     m_m15SwingHigh(0.0), m_m15SwingLow(0.0),
                     m_m15HaveStructure(false),
                     m_protectedHigh(0.0), m_protectedLow(0.0),
                     m_lastStructureEvent(STRUCTURE_EVENT_NONE),
                     m_lastBreakLevel(0.0), m_lastBreakTime(0), m_structureTrendSince(0),
                     m_pendingReversal(SIGNAL_NONE), m_pendingReversalSince(0),
                     m_trendBullPct(50.0), m_cachedLTFStructureBar(0),
                     m_cachedHaveLTFStructure(false),
                     m_setupMode(SETUP_SMC_PRIMARY), m_pureLadder(0) {}
   ~CSignalEngine()
    {
     // AUDIT FIX: cleanup all active POI chart objects on deinit
     for(int i = 0; i < m_poiCount; i++)
       {
        int phys = PoiPhys(i);
        ObjectDelete(0, m_poiStore[phys].objName);
        ObjectDelete(0, m_poiStore[phys].objName + "_LBL");
        ObjectDelete(0, m_poiStore[phys].fvgObjName);
        ObjectDelete(0, m_poiStore[phys].fvgObjName + "_LBL");
       }
    }

   void SetPureLadder(int ladder) { m_pureLadder = MathMax(0, MathMin(3, ladder)); }

   void SetSetupMode(const ENUM_SETUP_MODE mode)
     {
      m_setupMode = mode;
     }

   ENUM_SETUP_MODE GetSetupMode() const { return m_setupMode; }

   void SetMSNREngine(CMSNREngine *msnr, bool useMSNR = true)
     {
      m_msnr = msnr;
      m_useMSNR = useMSNR;
   }

   // Dynamic Spread Auto-Detection: allows the EA to update the live
   // rejection threshold every tick (from CSpreadMonitor) instead of only
   // once at Init(). Clamped defensively so a bad input can never disable
   // the spread guard entirely.
   void SetMaxSpreadPoints(int maxSpreadPoints)
     {
     m_maxSpreadPoints = MathMax(1, maxSpreadPoints);
     }

   void SetMarketADX(double adx, double minimumADX, double maximumPenalty, bool enabled,
                     double plusDI = 0.0, double minusDI = 0.0)
     {
      m_marketADX = MathMax(0.0, adx);
      m_plusDI = MathMax(0.0, plusDI);
      m_minusDI = MathMax(0.0, minusDI);
      m_minADX = MathMax(0.0, minimumADX);
      m_adxSoftPenalty = MathMax(0.0, maximumPenalty);
      m_useADXSoftFeature = enabled;
     }

   // ATR Engine: override the ATR period used for the dynamic SL buffer/bounds.
   void SetATRPeriod(int atrPeriod) { m_atrPeriod = (atrPeriod > 0) ? atrPeriod : 14; }
   void SetFVGATRMult(double mult) { m_fvgATRMult = (mult > 0.0) ? mult : 0.30; }
   void SetATRStopBounds(bool enabled, double minMult, double maxMult)
     {
      m_useATRStopBounds = enabled;
      m_slMinATRMult = MathMax(0.0, minMult);
      m_slMaxATRMult = MathMax(0.0, maxMult);
     }

   void SetRequireM3Sweep(bool requireSweep) { m_requireM3Sweep = requireSweep; }
   void SetPoiPartialPips(double pips) { m_poiPartialPips = MathMax(0.0, pips); }

   void Init(string symbol,
             ENUM_TIMEFRAMES htf = PERIOD_M15, ENUM_TIMEFRAMES mtf = PERIOD_M5, ENUM_TIMEFRAMES ltf = PERIOD_M3,
             int m15Depth = 12, int m15Dev = 5, int m15Back = 3,
             int m5Depth  = 8,  int m5Dev  = 3, int m5Back  = 3,
             int m3Depth  = 5,  int m3Dev  = 2, int m3Back  = 2,
               double fvgMinMult = 1.5, double fibMatchTolerance = 0.030,
               int zoneMaxBars = 50, int poiScanBars = 1200,
             double slBufferPips = 1.5, int maxSpreadPoints = 50,
               double tp1RR = 1.5, double tp2RR = 2.0,
              bool useDynamicRisk = true,
                double minSLPips = 30.0, double maxSLPips = 60.0,
              bool useDynamicSLBuffer = true, double slATRMult = 0.20,
                bool useLiquiditySweepBoost = true, bool useOTEBoost = true, 

                double minSoftScore = 45.0, bool allowCounterBias = true,
                int counterBiasStagnationBars = 16, double counterBiasMinScore = 75.0,
                int chochTransitionMaxBars = 12,
                int poiInvalidationCloses = 2, double poiInvalidationBufferPips = 8.0)
   {
      m_symbol           = (symbol == NULL || symbol == "") ? Symbol() : symbol;
      m_htfPeriod        = htf;
      m_mtfPeriod        = mtf;
      m_ltfPeriod        = ltf;
      m_m15Depth         = m15Depth;
      m_m15Dev           = m15Dev;
      m_m15Back          = m15Back;
      m_m5Depth          = m5Depth;
      m_m5Dev            = m5Dev;
      m_m5Back           = m5Back;
      m_m3Depth          = m3Depth;
      m_m3Dev            = m3Dev;
      m_m3Back           = m3Back;
      m_fvgMinMultiplier = fvgMinMult;
      m_fibMatchTolerance = MathMax(0.001, MathMin(0.10, fibMatchTolerance));
      m_zoneMaxBars      = zoneMaxBars;
      m_poiScanBars      = MathMax(100, poiScanBars);
      m_slBufferPips     = slBufferPips;
      m_maxSpreadPoints  = maxSpreadPoints;
      m_tp1RR            = tp1RR;
      m_tp2RR            = tp2RR;
      m_useDynamicRisk   = useDynamicRisk;
      m_useDynamicSLBuffer = useDynamicSLBuffer;
      m_slATRMult        = slATRMult;
      if(m_atrPeriod <= 0) m_atrPeriod = 14; // ATR Engine default; override via SetATRPeriod()
      m_useLiquiditySweepBoost = useLiquiditySweepBoost;
      m_useOTEBoost      = useOTEBoost;

      m_minSoftScore = MathMax(0.0, minSoftScore);
      m_allowCounterBias = allowCounterBias;
      m_counterBiasStagnationBars = MathMax(1, counterBiasStagnationBars);
      m_counterBiasMinScore = MathMax(m_minSoftScore, counterBiasMinScore);
      m_chochTransitionMaxBars = MathMax(1, chochTransitionMaxBars);
      m_minSLPips        = (minSLPips > 0.0) ? minSLPips : 0.0;
      m_maxSLPips        = (maxSLPips > 0.0) ? maxSLPips : 0.0;
      m_poiInvalidationCloses = MathMax(1, poiInvalidationCloses);
      m_poiInvalidationBufferPips = MathMax(0.0, poiInvalidationBufferPips);
      m_poiCount         = 0;
      m_poiHead          = 0;
      m_structureTrend   = SIGNAL_NONE;
      m_htfBias          = SIGNAL_NONE;
      m_protectedHigh    = 0.0;
      m_protectedLow     = 0.0;
      m_lastStructureEvent = STRUCTURE_EVENT_NONE;
      m_lastBreakLevel   = 0.0;
      m_lastBreakTime    = 0;
      m_structureTrendSince = 0;
      m_pendingReversal = SIGNAL_NONE;
      m_pendingReversalSince = 0;
      m_cachedLTFStructureBar = 0;
      m_cachedHaveLTFStructure = false;
      m_m15EventCount = 0;
      m_m3EventCount = 0;
      m_m3Trend = SIGNAL_NONE;
      m_m3ProtectedHigh = 0.0;
      m_m3ProtectedLow = 0.0;
      m_m3PendingReversal = SIGNAL_NONE;
      m_m3PendingSince = 0;
      m_m3LastBar = 0;

      m_zz.Init(m_symbol);
      m_rc.Init(m_symbol);
   }

   bool IsInOTEZone(double price, double swingHigh, double swingLow, ENUM_ZONE_TYPE type)
   {
      // AUDIT H1: invalid swing has no OTE window. Fail-closed to match ClassifyFibLevel().
      if(swingHigh <= swingLow) return false;
      double range = swingHigh - swingLow;
      double pip   = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      if(type == ZONE_DEMAND)
      {
         // Optional MSNR/SMC location window: 0.618 to 0.786 (classic OTE far).
         double ote618 = swingHigh - 0.618 * range;
         double ote786 = swingHigh - 0.786 * range;
         return (price <= (ote618 + 3.0 * pip) && price >= (ote786 - 3.0 * pip));
      }
      else
      {
         double ote618 = swingLow + 0.618 * range;
         double ote786 = swingLow + 0.786 * range;
         return (price >= (ote618 - 3.0 * pip) && price <= (ote786 + 3.0 * pip));
      }
   }

   ENUM_FIB_LEVEL ClassifyFibLevel(double price, double swingHigh, double swingLow, ENUM_ZONE_TYPE type)
   {
      if(swingHigh <= swingLow) return FIB_LEVEL_NONE;
      double range = swingHigh - swingLow;
      double ratio = (type == ZONE_DEMAND) ? (swingHigh - price) / range : (price - swingLow) / range;
      double bestDistance = MathAbs(ratio - 0.618);
      ENUM_FIB_LEVEL bestLevel = FIB_LEVEL_618;
      double distance = MathAbs(ratio - 0.705);
      if(distance < bestDistance) { bestDistance = distance; bestLevel = FIB_LEVEL_705; }
      distance = MathAbs(ratio - 0.786);
      if(distance < bestDistance) { bestDistance = distance; bestLevel = FIB_LEVEL_790; }
      return (bestDistance <= m_fibMatchTolerance) ? bestLevel : FIB_LEVEL_NONE;
   }

   void SetTrendBullPct(double bullPct)
   {
      m_trendBullPct = MathMax(0.0, MathMin(100.0, bullPct));
   }

   void ClassifyPattern(double price, const SMC_Zone &zone,
                        ENUM_POI_PROFILE &poiProfile,
                        ENUM_OB_MITIGATION &obMitigation,
                        ENUM_FVG_MITIGATION &fvgMitigation,
                        ENUM_FIB_LEVEL &fibLevel)
   {
      poiProfile = zone.hasFVG ? POI_PROFILE_OB_FVG : POI_PROFILE_OB_ONLY;
      double width = zone.top - zone.bottom;
      double obDepth = 0.5;
      if(width > 0.0)
         obDepth = (zone.type == ZONE_DEMAND) ? (price - zone.bottom) / width
                                              : (zone.top - price) / width;
      obDepth = MathMax(0.0, MathMin(1.0, obDepth));
      double distance15 = MathAbs(obDepth - 0.15);
      double distance45 = MathAbs(obDepth - 0.45);
      double distance50 = MathAbs(obDepth - 0.50);
      if(distance15 <= distance45 && distance15 <= distance50) obMitigation = OB_MITIGATION_15;
      else if(distance45 <= distance50)                         obMitigation = OB_MITIGATION_45;
      else                                                       obMitigation = OB_MITIGATION_50;

      fvgMitigation = FVG_MITIGATION_NONE;
      if(zone.hasFVG && zone.fvgTop > zone.fvgBottom)
        {
         double gap = zone.fvgTop - zone.fvgBottom;
         double fill = (zone.type == ZONE_DEMAND) ? (zone.fvgTop - price) / gap
                                                   : (price - zone.fvgBottom) / gap;
         if(fill >= 0.35 && fill <= 0.65)
            fvgMitigation = FVG_MITIGATION_50;
        }
      fibLevel = ClassifyFibLevel(price, zone.fiboSwingHigh, zone.fiboSwingLow, zone.type);
   }

   string GetSetupTypeString(ENUM_SMC_ENTRY_TYPE t)
   {
      switch(t)
      {
         case ENTRY_TYPE_OB_15:    return "OB 15%";
         case ENTRY_TYPE_OB_45:    return "OB 45%";
         case ENTRY_TYPE_FVG_50:   return "FVG 50% CE";
         case ENTRY_TYPE_FIB_618:  return "FIB 0.618 Minimum";
         case ENTRY_TYPE_FIB_705:  return "FIB 0.705 OTE";
         case ENTRY_TYPE_FIB_790:  return "FIB 0.786 Deep";
      }
      return "MSNR/SMC Setup";
   }

   void SetDependencies(CSmartBrain *brain = NULL, CSessionManager *session = NULL)
   {
      m_brain   = brain;
      m_session = session;
   }

   int               GetPOICount()    { return m_poiCount; }
   long              GetPoiRevision() { return m_poiRevision; }
   void              BumpPoiRevision() { m_poiRevision++; }
   ENUM_SIGNAL_TYPE  GetHTFBias()        { return m_htfBias; }
   void SetPOIPendingLayer(int idx, ENUM_SMC_ENTRY_TYPE setupType, bool hasLimit,
                           ulong setupEventId = 0)
   {
      if(idx < 0 || idx >= m_poiCount) return;
      int st = (int)setupType;
      if(st < 0 || st >= ENTRY_VARIANT_COUNT) return;
      m_poiStore[PoiPhys(idx)].hasPendingLayer[st] = hasLimit;
      if(hasLimit && setupEventId > 0) m_poiStore[PoiPhys(idx)].pendingEventId[st] = setupEventId;
      else if(!hasLimit)               m_poiStore[PoiPhys(idx)].pendingEventId[st] = 0;
      bool anyPending = false;
      for(int k = 0; k < ENTRY_VARIANT_COUNT; k++)
         if(m_poiStore[PoiPhys(idx)].hasPendingLayer[k]) { anyPending = true; break; }
      m_poiStore[PoiPhys(idx)].hasPendingLimit = anyPending;
   }

   void SetDiagnostics(CSignalDiagnostics *diagnostics = NULL)
     {
      m_diagnostics = diagnostics;
     }

   long DiagnosticKey(int poiIndex, int salt = 0)
     {
      datetime barTime = iTime(m_symbol, m_ltfPeriod, 0);
      return ((long)barTime * 10000) + (long)(poiIndex + 1) * 32 + salt;
     }

   void RecordReject(ENUM_SIGNAL_REJECT_REASON reason, int poiIndex = -1, int salt = 0)
     {
      if(m_diagnostics == NULL) return;
      m_diagnostics.Record(reason, DiagnosticKey(poiIndex, salt));
     }

   ENUM_SETUP_GRADE EvaluateSetupGrade(const int primaryZone,
                                       const bool m3Confirmed,
                                       const bool kingAgainst,
                                       const double entryPrice,
                                       const double slPrice,
                                       const double tp2Price,
                                       const ENUM_ZONE_TYPE side,
                                       const bool poiInOTE = false)
     {
      SMSNR_Zone map;
      bool hasMap = false;
      ENUM_MSNR_ZONE_TYPE mapType = MSNR_ZONE_NONE;
      ENUM_MSNR_FRESH_STATUS fresh = MSNR_PARTIAL;
      bool inOTE = false;
      bool mitigated = true;

      if(m_useMSNR && m_msnr != NULL && m_msnr.GetZone(primaryZone, map))
        {
         hasMap = (!map.isKingSNR && (MsnrIsQml(map.msnrType) || MsnrIsKeyLevel(map.msnrType)));
         mapType = map.msnrType;
         fresh = map.freshStatus;
         inOTE = map.isInOTE;
         mitigated = (map.isMitigated || !map.isActive);

        }
      else
        {
         // SMC modes: a missing map is a soft overlay miss, not a dead zone.
         mitigated = false;
         if(poiInOTE)
            inOTE = true;
        }

      if(m_setupMode == SETUP_PURE_SMC)
         return ClassifySetupGradePureSMC(inOTE, m3Confirmed, kingAgainst, m_pureLadder);
      return ClassifySetupGradeSMCPrimary(hasMap, mapType, fresh, inOTE, kingAgainst, mitigated);
     }

   void SetBrainExplorationMode(bool enabled) { m_brainExplorationMode = enabled; }

   void SetMaxAggregateRiskPct(double pct) { m_maxAggregateRiskPct = MathMax(0.0, pct); }
   void              ClearAllPOIPendingLimits()
   {
      for(int i = 0; i < m_poiCount; i++)
      {
         m_poiStore[PoiPhys(i)].hasPendingLimit = false;
         for(int k = 0; k < ENTRY_VARIANT_COUNT; k++) m_poiStore[PoiPhys(i)].hasPendingLayer[k] = false;
      }
   }
   bool SetMatchingPOIPendingLimit(ENUM_ZONE_TYPE type, double orderPrice, bool hasLimit)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      int bestIdx = -1;
      double bestDist = DBL_MAX;
      for(int i = 0; i < m_poiCount; i++)
      {
         if(m_poiStore[PoiPhys(i)].type != type || !m_poiStore[PoiPhys(i)].isActive || m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated) continue;
         if(orderPrice < m_poiStore[PoiPhys(i)].bottom - 5.0 * pip || orderPrice > m_poiStore[PoiPhys(i)].top + 5.0 * pip) continue;
         double mid = (m_poiStore[PoiPhys(i)].top + m_poiStore[PoiPhys(i)].bottom) * 0.5;
         double dist = MathAbs(orderPrice - mid);
         if(dist < bestDist) { bestDist = dist; bestIdx = i; }
      }
      if(bestIdx < 0) return false;
      m_poiStore[PoiPhys(bestIdx)].hasPendingLimit = hasLimit;
      return true;
   }

   bool SetMatchingPOIPendingLayer(ENUM_ZONE_TYPE type, double orderPrice,
                                   ENUM_SMC_ENTRY_TYPE setupType, bool hasLimit)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      int bestIdx = -1;
      double bestDist = DBL_MAX;
      for(int i = 0; i < m_poiCount; i++)
      {
         if(m_poiStore[PoiPhys(i)].type != type || !m_poiStore[PoiPhys(i)].isActive || m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated) continue;
         if(orderPrice < m_poiStore[PoiPhys(i)].bottom - 5.0 * pip || orderPrice > m_poiStore[PoiPhys(i)].top + 5.0 * pip) continue;
         double dist = MathAbs(orderPrice - (m_poiStore[PoiPhys(i)].top + m_poiStore[PoiPhys(i)].bottom) * 0.5);
         if(dist < bestDist) { bestDist = dist; bestIdx = i; }
      }
      if(bestIdx < 0) return false;
      SetPOIPendingLayer(bestIdx, setupType, hasLimit);
      return true;
   }

   bool SetMatchingPOIPendingEvent(ENUM_ZONE_TYPE type, ulong setupEventId,
                                   ENUM_SMC_ENTRY_TYPE setupType, bool hasLimit)
   {
      if(setupEventId == 0) return false;
      int st = (int)setupType;
      if(st < 0 || st >= ENTRY_VARIANT_COUNT) return false;
      for(int i = 0; i < m_poiCount; i++)
      {
         if(m_poiStore[PoiPhys(i)].type != type || !m_poiStore[PoiPhys(i)].isActive ||
            m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated) continue;
         if(m_poiStore[PoiPhys(i)].pendingEventId[st] != setupEventId) continue;
         SetPOIPendingLayer(i, setupType, hasLimit, setupEventId);
         return true;
      }
      return false;
   }

   bool SetMatchingPOIEventTriggered(ENUM_ZONE_TYPE type, ulong setupEventId,
                                     ENUM_SMC_ENTRY_TYPE setupType, int maxLayers = 4)
   {
      if(setupEventId == 0) return false;
      int st = (int)setupType;
      if(st < 0 || st >= ENTRY_VARIANT_COUNT) return false;
      for(int i = 0; i < m_poiCount; i++)
      {
         if(m_poiStore[PoiPhys(i)].type != type || !m_poiStore[PoiPhys(i)].isActive ||
            m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated) continue;
         if(m_poiStore[PoiPhys(i)].pendingEventId[st] != setupEventId) continue;
         SetPOILayerTriggered(i, setupType, maxLayers);
         return true;
      }
      return false;
   }

   bool IsDirectionAllowed(ENUM_SIGNAL_TYPE dir, bool &isCounterTrend)
   {
      isCounterTrend = false;
      if(dir == SIGNAL_NONE) return false;

      // King SNR is HTF storyline bias, not a hard veto. Disagreement uses
      // the existing counter-trend score gate instead of blocking the side.
      if(m_useMSNR && m_msnr != NULL)
      {
         ENUM_SIGNAL_TYPE kingBias = m_msnr.GetKingBias();
         if(kingBias != SIGNAL_NONE && dir != kingBias)
            isCounterTrend = true;
      }

      if(m_structureTrend == SIGNAL_NONE || dir == m_structureTrend) return true;
      // A valid opposing CHoCH opens a stricter counter-trend evaluation path,
      // but macro bias is not flipped until a post-CHoCH BOS confirms it.
      if(m_pendingReversal == dir)
        {
         isCounterTrend = true;
         return true;
        }
      // M15 direction is context, not a veto. The opposing side proceeds to
      // the stricter composite score so SmartBrain can observe/evaluate it.
      if(!m_allowCounterBias) return false;
      if(m_lastBreakTime > 0)
        {
         int barsSinceBreak = iBarShift(m_symbol, m_htfPeriod, m_lastBreakTime, false);
         if(barsSinceBreak >= 0 && barsSinceBreak < m_counterBiasStagnationBars) return false;
        }
      isCounterTrend = true;
      return true;
   }

   double GetMinimumSoftScore(bool counterTrend = false)
     {
      return counterTrend ? m_counterBiasMinScore : m_minSoftScore;
     }

   double ApplyInstitutionalSoftScore(const SMC_Zone &zone, ENUM_SIGNAL_TYPE dir,
                                      double baseScore, bool counterTrend)
   {
      double score = baseScore;
      if(counterTrend) score -= 10.0;
      if(m_useADXSoftFeature && m_marketADX > 0.0 && m_minADX > 0.0 && m_marketADX < m_minADX)
        {
         double weakness = MathMin(1.0, (m_minADX - m_marketADX) / m_minADX);
         score -= m_adxSoftPenalty * weakness;
        }
      if(m_useADXSoftFeature && m_plusDI > 0.0 && m_minusDI > 0.0)
        {
         bool diBull = (m_plusDI > m_minusDI);
         bool sigBull = (dir == SIGNAL_BUY);
         if(diBull == sigBull) score += 5.0;
         else score -= 5.0;
        }
      return MathMax(0.0, MathMin(100.0, score));
   }

   bool IsPOIInvalidated(const SMC_Zone &zone, const MqlRates &rates[], int copied)
   {
      if(copied <= m_poiInvalidationCloses) return false;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double buffer = m_poiInvalidationBufferPips * pip;
      for(int bar = 1; bar <= m_poiInvalidationCloses; bar++)
        {
         if(zone.type == ZONE_DEMAND && rates[bar].close >= zone.bottom - buffer) return false;
         if(zone.type == ZONE_SUPPLY && rates[bar].close <= zone.top + buffer) return false;
        }
      return true;
   }

   // POI invalidation is a lifecycle event, not an entry-side effect.  In
   // particular, a full pending-order book must not postpone invalidation
   // merely because GenerateSignal() is skipped by the capacity guard.
   // A partial retest remains valid; this only applies the configured closed-
   // candle break beyond the far edge of the parent POI.
   int RefreshPOIInvalidation()
   {
      if(m_poiCount <= 0) return 0;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int needed = m_poiInvalidationCloses + 1;
      int copied = CopyRates(m_symbol, m_ltfPeriod, 0, needed, rates);
      if(copied <= m_poiInvalidationCloses) return 0;

      int invalidated = 0;
      for(int i = 0; i < m_poiCount; i++)
      {
         if(!m_poiStore[PoiPhys(i)].isActive || m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated)
            continue;
         if(!IsPOIInvalidated(m_poiStore[PoiPhys(i)], rates, copied)) continue;

         // isMitigated is the existing terminal-state flag consumed by every
         // POI/pending-order guard. Here it represents structural invalidation,
         // never an ordinary 25/50/75 percent mitigation touch.
         m_poiStore[PoiPhys(i)].isMitigated = true;
         m_poiStore[PoiPhys(i)].isActive    = false;
         RecordReject(REJECT_POI_INVALIDATED, i);
         invalidated++;
      }
      if(invalidated > 0)
         m_poiRevision++;
      return invalidated;
   }

   bool              GetPOI(int idx, SMC_Zone &zone)
   {
      if(idx < 0 || idx >= m_poiCount) return false;
      zone = m_poiStore[PoiPhys(idx)];
      return true;
   }
   double            GetM15SwingHigh()   { return m_m15SwingHigh; }
   double            GetM15SwingLow()    { return m_m15SwingLow; }
   double            GetM15Equilibrium() { return m_m15Equilibrium; }
   bool GetM15StructureSwings(SMC_SwingPoint &lastHigh, SMC_SwingPoint &prevHigh,
                              SMC_SwingPoint &lastLow, SMC_SwingPoint &prevLow) const
     {
      lastHigh = m_m15LastHigh; prevHigh = m_m15PrevHigh;
      lastLow  = m_m15LastLow;  prevLow  = m_m15PrevLow;
      return m_m15HaveStructure;
     }
   bool GetM3StructureSwings(SMC_SwingPoint &lastHigh, SMC_SwingPoint &prevHigh,
                             SMC_SwingPoint &lastLow, SMC_SwingPoint &prevLow) const
     {
      lastHigh = m_cachedLTFHigh; prevHigh = m_cachedLTFPrevHigh;
      lastLow  = m_cachedLTFLow;  prevLow  = m_cachedLTFPrevLow;
      return m_cachedHaveLTFStructure;
     }
   void RefreshLTFStructureCache()
     {
      datetime bar = iTime(m_symbol, m_ltfPeriod, 0);
      if(bar == m_cachedLTFStructureBar && m_cachedHaveLTFStructure) return;
      m_cachedHaveLTFStructure = m_zz.GetStructureSwings(m_ltfPeriod, m_m3Depth, m_m3Dev, m_m3Back,
                                                         m_cachedLTFHigh, m_cachedLTFPrevHigh,
                                                         m_cachedLTFLow, m_cachedLTFPrevLow);
      m_cachedLTFStructureBar = bar;
     }
   ENUM_STRUCTURE_EVENT GetLastStructureEvent() { return m_lastStructureEvent; }
   double            GetLastBreakLevel() { return m_lastBreakLevel; }
   datetime          GetLastBreakTime()   { return m_lastBreakTime; }

   // Chart/attribution history. TTL-filtered newest-first. Read-only for display;
   // entry logic keeps using GetLastStructureEvent()/GetLastBreak*() unchanged.
   int GetM15StructureEvents(SStructureEvent &out[])
     { return StructureEventsActive(m_m15Events, m_m15EventCount, out, TimeCurrent(), (int)PeriodSeconds(m_htfPeriod)); }
   int GetM3StructureEvents(SStructureEvent &out[])
     { return StructureEventsActive(m_m3Events, m_m3EventCount, out, TimeCurrent(), (int)PeriodSeconds(m_ltfPeriod)); }

   string GetLastStructureEventLabel()
   {
      return StructureEventLabel(m_lastStructureEvent);
   }

   // Single write path for M15 structure events: keeps the 3 legacy fields
   // (authoritative for trading) then appends to the display ring.
   void RecordM15StructureEvent(const ENUM_STRUCTURE_EVENT evt, const double level, const datetime t)
   {
      m_lastStructureEvent = evt;
      m_lastBreakLevel     = level;
      m_lastBreakTime      = t;
      SStructureEvent e;
      e.evt = evt; e.barTime = t; e.level = level;
      StructureEventsPush(m_m15Events, m_m15EventCount, e);
   }

   // M3 mirror of the M15 recorder. Display/attribution only: the M3 micro
   // structure machine below never gates entries, scores or sizing.
   void RecordM3StructureEvent(const ENUM_STRUCTURE_EVENT evt, const double level, const datetime t)
   {
      SStructureEvent e;
      e.evt = evt; e.barTime = t; e.level = level;
      StructureEventsPush(m_m3Events, m_m3EventCount, e);
   }


   double GetDynamicSLBuffer(double fixedBufferPips, double atrMult = 0.50)
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double pip   = point * GetPipFactor(m_symbol);
      double atr   = GetCachedATR(m_symbol, m_htfPeriod, m_atrPeriod);
      if(atr > 0.0) return atr * atrMult;
      return MathMax(fixedBufferPips * pip, point); // robust fallback (ATR unavailable)
   }

   void ApplyEngineStopBounds(const bool isBuy, const double entryPrice,
                              const double pip, double &sl, double &slP)
   {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double minPips = 0.0, maxPips = 0.0;
      ComputeStopBoundPips(m_symbol, m_htfPeriod, m_atrPeriod, pip,
                           m_minSLPips, m_maxSLPips,
                           m_useATRStopBounds, m_slMinATRMult, m_slMaxATRMult,
                           minPips, maxPips);
      if(ClampStopToBounds(isBuy, entryPrice, pip, digits, minPips, maxPips, sl, slP) &&
         m_diagnostics != NULL)
         m_diagnostics.RecordClampedSL();
   }

   bool IsOpposingZoneHit(int posType, double curPrice, double proximityPips = 5.0)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      for(int i = 0; i < m_poiCount; i++)
      {
         if(!m_poiStore[PoiPhys(i)].isActive || m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated) continue;

         if(posType == POSITION_TYPE_BUY && m_poiStore[PoiPhys(i)].type == ZONE_SUPPLY)
         {
            if(curPrice >= m_poiStore[PoiPhys(i)].bottom - (proximityPips * pip) && curPrice <= m_poiStore[PoiPhys(i)].top + (proximityPips * pip))
               return true;
         }
         else if(posType == POSITION_TYPE_SELL && m_poiStore[PoiPhys(i)].type == ZONE_DEMAND)
         {
            if(curPrice <= m_poiStore[PoiPhys(i)].top + (proximityPips * pip) && curPrice >= m_poiStore[PoiPhys(i)].bottom - (proximityPips * pip))
               return true;
         }
      }
      return false;
   }


   //+------------------------------------------------------------------+
   //| Check if New Bar formed on specified timeframe                  |
   //+------------------------------------------------------------------+
   bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastTime)
   {
      datetime curTime = iTime(m_symbol, tf, 0);
      if(curTime != lastTime && curTime > 0)
      {
         lastTime = curTime;
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| PHASE 1: HTF M15 MACRO BIAS & EQUILIBRIUM                       |
   //+------------------------------------------------------------------+
   void EvaluatePhase1_HTFBias()
   {
      SMC_SwingPoint swHigh, prevHigh, swLow, prevLow;
      if(!m_zz.GetStructureSwings(m_htfPeriod, m_m15Depth, m_m15Dev, m_m15Back,
                                  swHigh, prevHigh, swLow, prevLow))
        {
          m_structureTrend = SIGNAL_NONE;
          m_htfBias = SIGNAL_NONE;
          m_pendingReversal = SIGNAL_NONE;
          m_pendingReversalSince = 0;
          m_m15SwingHigh = 0.0;
          m_m15SwingLow = 0.0;
          m_m15Equilibrium = 0.0;
          m_m15HaveStructure = false;
          return;
        }

      m_m15LastHigh = swHigh;
      m_m15PrevHigh = prevHigh;
      m_m15LastLow  = swLow;
      m_m15PrevLow  = prevLow;
      m_m15HaveStructure = true;
      m_m15SwingHigh   = swHigh.price;
      m_m15SwingLow    = swLow.price;
      m_m15Equilibrium = (m_m15SwingHigh + m_m15SwingLow) / 2.0;

      double close1 = iClose(m_symbol, m_htfPeriod, 1);
      double close2 = iClose(m_symbol, m_htfPeriod, 2);
      double open1  = iOpen(m_symbol, m_htfPeriod, 1);
      double high1  = iHigh(m_symbol, m_htfPeriod, 1);
      double low1   = iLow(m_symbol, m_htfPeriod, 1);
      double candleRange = high1 - low1;
      double bodyRatio = (candleRange > 0.0) ? MathAbs(close1 - open1) / candleRange : 0.0;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double breakBuffer = 0.5 * pip;
      bool displacedBull = (bodyRatio >= 0.55 && close1 > open1);
      bool displacedBear = (bodyRatio >= 0.55 && close1 < open1);

      // CHoCH is only a transition candidate.  Without a confirming BOS in
      // this window the reversal thesis is stale and must be discarded.
      if(m_pendingReversal != SIGNAL_NONE && m_pendingReversalSince > 0)
        {
         int transitionSeconds = m_chochTransitionMaxBars * PeriodSeconds(m_htfPeriod);
         datetime closedBarTime = iTime(m_symbol, m_htfPeriod, 1);
         if(transitionSeconds > 0 && closedBarTime > m_pendingReversalSince + transitionSeconds)
           {
            m_pendingReversal = SIGNAL_NONE;
            m_pendingReversalSince = 0;
           }
        }

      // Initialize direction only from an actual HH+HL or LH+LL sequence.
      // Premium/discount is a location rule and must never fabricate a
      // structural BOS/CHoCH state.
      if(m_structureTrend == SIGNAL_NONE)
      {
         if(swHigh.price > prevHigh.price && swLow.price > prevLow.price)
         {
            m_structureTrend = SIGNAL_BUY;
            m_structureTrendSince = TimeCurrent();
            m_pendingReversal = SIGNAL_NONE;
            m_pendingReversalSince = 0;
            m_protectedLow = swLow.price;
            m_protectedHigh = swHigh.price;
         }
         else if(swHigh.price < prevHigh.price && swLow.price < prevLow.price)
         {
            m_structureTrend = SIGNAL_SELL;
            m_structureTrendSince = TimeCurrent();
            m_pendingReversal = SIGNAL_NONE;
            m_pendingReversalSince = 0;
            m_protectedHigh = swHigh.price;
            m_protectedLow = swLow.price;
         }
      }
      else if(m_structureTrend == SIGNAL_BUY)
      {
         if(m_pendingReversal == SIGNAL_SELL)
           {
            bool postChochLowerHigh = (swHigh.time > m_pendingReversalSince &&
                                       swHigh.price < m_protectedHigh);
            bool postChochLow = (swLow.time > m_pendingReversalSince);
            bool confirmBearBOS = (postChochLowerHigh && postChochLow &&
                                   close2 >= swLow.price &&
                                   close1 < (swLow.price - breakBuffer) && displacedBear);
            bool invalidateBearShift = (m_protectedHigh > 0.0 && close2 <= m_protectedHigh &&
                                        close1 > (m_protectedHigh + breakBuffer) && displacedBull);
            if(confirmBearBOS)
              {
               RecordM15StructureEvent(STRUCTURE_BOS_BEARISH, swLow.price, iTime(m_symbol, m_htfPeriod, 1));
               m_structureTrend = SIGNAL_SELL;
               m_structureTrendSince = TimeCurrent();
               m_pendingReversal = SIGNAL_NONE;
               m_pendingReversalSince = 0;
               m_protectedHigh = swHigh.price;
               m_protectedLow = swLow.price;
              }
            else if(invalidateBearShift)
              {
               RecordM15StructureEvent(STRUCTURE_BOS_BULLISH, m_protectedHigh, iTime(m_symbol, m_htfPeriod, 1));
               m_pendingReversal = SIGNAL_NONE;
               m_pendingReversalSince = 0;
               m_protectedLow = swLow.price;
               m_protectedHigh = swHigh.price;
              }
           }
         else if(m_protectedLow > 0.0 && close2 >= m_protectedLow &&
                 close1 < (m_protectedLow - breakBuffer) && displacedBear)
           {
            // CHoCH is a warning/transition, not an immediate macro trend flip.
            RecordM15StructureEvent(STRUCTURE_CHOCH_BEARISH, m_protectedLow, iTime(m_symbol, m_htfPeriod, 1));
            m_pendingReversal = SIGNAL_SELL;
            m_pendingReversalSince = m_lastBreakTime;
           }
         else if(close2 <= swHigh.price && close1 > (swHigh.price + breakBuffer) && displacedBull)
           {
            RecordM15StructureEvent(STRUCTURE_BOS_BULLISH, swHigh.price, iTime(m_symbol, m_htfPeriod, 1));
            m_protectedLow = swLow.price;
            m_protectedHigh = swHigh.price;
           }
      }
      else if(m_structureTrend == SIGNAL_SELL)
      {
         if(m_pendingReversal == SIGNAL_BUY)
           {
            bool postChochHigherLow = (swLow.time > m_pendingReversalSince &&
                                       swLow.price > m_protectedLow);
            bool postChochHigh = (swHigh.time > m_pendingReversalSince);
            bool confirmBullBOS = (postChochHigherLow && postChochHigh &&
                                   close2 <= swHigh.price &&
                                   close1 > (swHigh.price + breakBuffer) && displacedBull);
            bool invalidateBullShift = (m_protectedLow > 0.0 && close2 >= m_protectedLow &&
                                        close1 < (m_protectedLow - breakBuffer) && displacedBear);
            if(confirmBullBOS)
              {
               RecordM15StructureEvent(STRUCTURE_BOS_BULLISH, swHigh.price, iTime(m_symbol, m_htfPeriod, 1));
               m_structureTrend = SIGNAL_BUY;
               m_structureTrendSince = TimeCurrent();
               m_pendingReversal = SIGNAL_NONE;
               m_pendingReversalSince = 0;
               m_protectedLow = swLow.price;
               m_protectedHigh = swHigh.price;
              }
            else if(invalidateBullShift)
              {
               RecordM15StructureEvent(STRUCTURE_BOS_BEARISH, m_protectedLow, iTime(m_symbol, m_htfPeriod, 1));
               m_pendingReversal = SIGNAL_NONE;
               m_pendingReversalSince = 0;
               m_protectedHigh = swHigh.price;
               m_protectedLow = swLow.price;
              }
           }
         else if(m_protectedHigh > 0.0 && close2 <= m_protectedHigh &&
                 close1 > (m_protectedHigh + breakBuffer) && displacedBull)
           {
            RecordM15StructureEvent(STRUCTURE_CHOCH_BULLISH, m_protectedHigh, iTime(m_symbol, m_htfPeriod, 1));
            m_pendingReversal = SIGNAL_BUY;
            m_pendingReversalSince = m_lastBreakTime;
           }
         else if(close2 >= swLow.price && close1 < (swLow.price - breakBuffer) && displacedBear)
           {
            RecordM15StructureEvent(STRUCTURE_BOS_BEARISH, swLow.price, iTime(m_symbol, m_htfPeriod, 1));
            m_protectedHigh = swHigh.price;
            m_protectedLow = swLow.price;
           }
      }

      m_htfBias = m_structureTrend;
   }

   //+------------------------------------------------------------------+
   //| M3 MICRO STRUCTURE (chart/attribution only)                      |
   //| Mirrors the M15 trend + pending-CHoCH-then-BOS state machine on   |
   //| the LTF slot. Never gates entries, scores or sizing.              |
   //+------------------------------------------------------------------+
   void EvaluateM3Structure()
   {
      datetime bar = iTime(m_symbol, m_ltfPeriod, 0);
      if(bar == m_m3LastBar) return;
      m_m3LastBar = bar;

      SMC_SwingPoint swHigh, prevHigh, swLow, prevLow;
      if(!m_zz.GetStructureSwings(m_ltfPeriod, m_m3Depth, m_m3Dev, m_m3Back,
                                  swHigh, prevHigh, swLow, prevLow))
         return;

      double close1 = iClose(m_symbol, m_ltfPeriod, 1);
      double close2 = iClose(m_symbol, m_ltfPeriod, 2);
      double open1  = iOpen(m_symbol, m_ltfPeriod, 1);
      double high1  = iHigh(m_symbol, m_ltfPeriod, 1);
      double low1   = iLow(m_symbol, m_ltfPeriod, 1);
      double candleRange = high1 - low1;
      double bodyRatio = (candleRange > 0.0) ? MathAbs(close1 - open1) / candleRange : 0.0;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double breakBuffer = 0.5 * pip;
      bool displacedBull = (bodyRatio >= 0.55 && close1 > open1);
      bool displacedBear = (bodyRatio >= 0.55 && close1 < open1);
      datetime barTime = iTime(m_symbol, m_ltfPeriod, 1);

      if(m_m3PendingReversal != SIGNAL_NONE && m_m3PendingSince > 0)
        {
         int transitionSeconds = m_chochTransitionMaxBars * PeriodSeconds(m_ltfPeriod);
         if(transitionSeconds > 0 && barTime > m_m3PendingSince + transitionSeconds)
           {
            m_m3PendingReversal = SIGNAL_NONE;
            m_m3PendingSince = 0;
           }
        }

      if(m_m3Trend == SIGNAL_NONE)
        {
         if(swHigh.price > prevHigh.price && swLow.price > prevLow.price)
           {
            m_m3Trend = SIGNAL_BUY;
            m_m3PendingReversal = SIGNAL_NONE;
            m_m3PendingSince = 0;
            m_m3ProtectedLow = swLow.price;
            m_m3ProtectedHigh = swHigh.price;
           }
         else if(swHigh.price < prevHigh.price && swLow.price < prevLow.price)
           {
            m_m3Trend = SIGNAL_SELL;
            m_m3PendingReversal = SIGNAL_NONE;
            m_m3PendingSince = 0;
            m_m3ProtectedLow = swLow.price;
            m_m3ProtectedHigh = swHigh.price;
           }
        }
      else if(m_m3Trend == SIGNAL_BUY)
        {
         if(m_m3PendingReversal == SIGNAL_SELL)
           {
            bool postChochLowerHigh = (swHigh.time > m_m3PendingSince && swHigh.price < m_m3ProtectedHigh);
            bool postChochLow = (swLow.time > m_m3PendingSince);
            bool confirmBearBOS = (postChochLowerHigh && postChochLow && close2 >= swLow.price &&
                                   close1 < (swLow.price - breakBuffer) && displacedBear);
            bool invalidateBearShift = (m_m3ProtectedHigh > 0.0 && close2 <= m_m3ProtectedHigh &&
                                        close1 > (m_m3ProtectedHigh + breakBuffer) && displacedBull);
            if(confirmBearBOS)
              {
               RecordM3StructureEvent(STRUCTURE_BOS_BEARISH, swLow.price, barTime);
               m_m3Trend = SIGNAL_SELL;
               m_m3PendingReversal = SIGNAL_NONE;
               m_m3PendingSince = 0;
               m_m3ProtectedHigh = swHigh.price;
               m_m3ProtectedLow = swLow.price;
              }
            else if(invalidateBearShift)
              {
               RecordM3StructureEvent(STRUCTURE_BOS_BULLISH, m_m3ProtectedHigh, barTime);
               m_m3PendingReversal = SIGNAL_NONE;
               m_m3PendingSince = 0;
               m_m3ProtectedLow = swLow.price;
               m_m3ProtectedHigh = swHigh.price;
              }
           }
         else if(m_m3ProtectedLow > 0.0 && close2 >= m_m3ProtectedLow &&
                 close1 < (m_m3ProtectedLow - breakBuffer) && displacedBear)
           {
            RecordM3StructureEvent(STRUCTURE_CHOCH_BEARISH, m_m3ProtectedLow, barTime);
            m_m3PendingReversal = SIGNAL_SELL;
            m_m3PendingSince = barTime;
           }
         else if(close2 <= swHigh.price && close1 > (swHigh.price + breakBuffer) && displacedBull)
           {
            RecordM3StructureEvent(STRUCTURE_BOS_BULLISH, swHigh.price, barTime);
            m_m3ProtectedLow = swLow.price;
            m_m3ProtectedHigh = swHigh.price;
           }
        }
      else if(m_m3Trend == SIGNAL_SELL)
        {
         if(m_m3PendingReversal == SIGNAL_BUY)
           {
            bool postChochHigherLow = (swLow.time > m_m3PendingSince && swLow.price > m_m3ProtectedLow);
            bool postChochHigh = (swHigh.time > m_m3PendingSince);
            bool confirmBullBOS = (postChochHigherLow && postChochHigh && close2 <= swHigh.price &&
                                   close1 > (swHigh.price + breakBuffer) && displacedBull);
            bool invalidateBullShift = (m_m3ProtectedLow > 0.0 && close2 >= m_m3ProtectedLow &&
                                        close1 < (m_m3ProtectedLow - breakBuffer) && displacedBear);
            if(confirmBullBOS)
              {
               RecordM3StructureEvent(STRUCTURE_BOS_BULLISH, swHigh.price, barTime);
               m_m3Trend = SIGNAL_BUY;
               m_m3PendingReversal = SIGNAL_NONE;
               m_m3PendingSince = 0;
               m_m3ProtectedLow = swLow.price;
               m_m3ProtectedHigh = swHigh.price;
              }
            else if(invalidateBullShift)
              {
               RecordM3StructureEvent(STRUCTURE_BOS_BEARISH, m_m3ProtectedLow, barTime);
               m_m3PendingReversal = SIGNAL_NONE;
               m_m3PendingSince = 0;
               m_m3ProtectedHigh = swHigh.price;
               m_m3ProtectedLow = swLow.price;
              }
           }
         else if(m_m3ProtectedHigh > 0.0 && close2 <= m_m3ProtectedHigh &&
                 close1 > (m_m3ProtectedHigh + breakBuffer) && displacedBull)
           {
            RecordM3StructureEvent(STRUCTURE_CHOCH_BULLISH, m_m3ProtectedHigh, barTime);
            m_m3PendingReversal = SIGNAL_BUY;
            m_m3PendingSince = barTime;
           }
         else if(close2 >= swLow.price && close1 < (swLow.price - breakBuffer) && displacedBear)
           {
            RecordM3StructureEvent(STRUCTURE_BOS_BEARISH, swLow.price, barTime);
            m_m3ProtectedHigh = swHigh.price;
            m_m3ProtectedLow = swLow.price;
           }
        }
   }

   //+------------------------------------------------------------------+
   //| PHASE 2: MTF M5 POI, IMBALANCE / FVG & ORDER BLOCK SCAN          |
   //+------------------------------------------------------------------+
   void EvaluatePhase2_M5POIs()
   {
      // 1. Increment bar age and drop POIs which are no longer backed by
      // the CURRENT primary hybrid map. Compact is a single O(n) pass
      // (the previous per-item shift was O(n^2) when many zones expired).
      CompactExpiredPOIs();


      // 2. Rebuild M5 POI history. An OB touched to 25% remains valid and can
      // still supply the 50%/75% matrix entries. Only a complete wick-through
      // of the far edge (or the separate structural invalidation flow) retires it.
      MqlRates m5Rates[];
      ArraySetAsSeries(m5Rates, true);
      // Zones older than m_zoneMaxBars are rejected by AddPOI(), so copying the
      // full historical lookback every M5 bar only burns CPU. Keep a small
      // structural context margin; unlimited-age configurations retain the
      // explicitly requested scan depth.
      int historyLookback = (m_zoneMaxBars > 0)
                            ? MathMin(m_poiScanBars, m_zoneMaxBars + 30)
                            : m_poiScanBars;
      int scanBars = MathMax(100, historyLookback);
      int copied = CopyRates(m_symbol, m_mtfPeriod, 0, scanBars, m5Rates);
      if(copied < 10) return;

      MqlRates ltfHistory[];
      ArraySetAsSeries(ltfHistory, true);
      int ltfNeed = scanBars * MathMax(1, PeriodSeconds(m_mtfPeriod) / PeriodSeconds(m_ltfPeriod)) + 10;
      int ltfCopied = CopyRates(m_symbol, m_ltfPeriod, 0, ltfNeed, ltfHistory);

      double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double pip     = point * GetPipFactor(m_symbol);
      // AUDIT FIX H1: this M5 POI rebuild used one scan-wide "now" ATR
      // (atrM5/minGap) for every historical candidate in the loop below --
      // an old candidate's FVG/OB validity could flip on a rescan purely
      // because current volatility changed. minGap and the OB-width bound
      // are now recomputed per candidate inside the loop from that
      // candidate's own formation shift via ReadATRAtShift().
      int fallbackSpreadPts = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(fallbackSpreadPts < 15)  fallbackSpreadPts = 15;
      if(fallbackSpreadPts > 800) fallbackSpreadPts = 800;

      // Keep the additional history above for the structure/RVOL windows, but
      // do not evaluate candidate OBs whose base candle is already older than
      // the configured POI lifetime. AddPOI() would reject those candidates.
      int candidateLimit = m_poiScanBars;
      if(m_zoneMaxBars > 0)
         candidateLimit = MathMax(3, m_zoneMaxBars - 1);
      int scanLimit = MathMin(copied - 3, candidateLimit);
      // M6 (2026-09-13, §53): a candidate's structural validity is decided
      // purely from its own formation-era rates (displacement/FVG/OB checks
      // below) -- current price is never consulted here. Coupling zone
      // *construction* to "is it near price right now" made a POI flicker in
      // and out of the store on every rebuild as price moved, even though
      // nothing about the formation itself changed. Distance-to-current-price
      // is an entry-selection concern (InpMaxEntryDistanceATR), applied only
      // where an entry is actually chosen/placed -- see YANSTD.mq5's limit
      // placement gates.
      // Insert chronologically (oldest -> newest). AddPOI's capacity policy
      // removes index 0, so index 0 must truly remain the oldest zone.
      for(int i = scanLimit - 1; i >= 2; i--)
      {
         // AUDIT FIX H1: formation-era ATR for THIS candidate, read at its
         // own displacement shift (i+1), not "now". Drives minGap (FVG
         // width) and the OB-width bound below.
         double atrM5 = ReadATRAtShift(m_symbol, m_mtfPeriod, (m_atrPeriod > 0 ? m_atrPeriod : 14), i + 1);
         double minGap;
         if(atrM5 > 0.0)
            minGap = atrM5 * (m_fvgATRMult > 0.0 ? m_fvgATRMult : 0.30);
         else
           {
            double fallbackGap = m_fvgMinMultiplier * fallbackSpreadPts * point;
            if(fallbackGap < 1.5 * point * GetPipFactor(m_symbol))
               fallbackGap = 1.5 * point * GetPipFactor(m_symbol);
            minGap = fallbackGap;
           }
         // Feature 2: Displacement Body Ratio (>=65%) & RVOL Filter
         double dispRange = m5Rates[i+1].high - m5Rates[i+1].low;
         double dispBody  = MathAbs(m5Rates[i+1].close - m5Rates[i+1].open);
         double bodyRatio = (dispRange > 0) ? (dispBody / dispRange) : 0.0;

         double avgVol = 0.0;
         int vCount = 0;
         for(int v = i + 2; v < i + 22 && v < copied; v++)
         {
            avgVol += (double)m5Rates[v].tick_volume;
            vCount++;
         }
         if(vCount > 0) avgVol /= (double)vCount;
         bool rvolSpike = (avgVol <= 0) || ((double)m5Rates[i+1].tick_volume >= 1.25 * avgVol);

         // Skip weak displacement if candle is small/indecisive without volume spike
         if(bodyRatio < 0.60 && !rvolSpike) continue;

         // A valid M5 institutional leg must displace through older local
         // structure. H3-FVG (audit 2026-09-12, distinct from the older AUDIT H3
         // pivot-wing note in Defines.mqh): on M5 and above, an impulsive
         // FVG is a MANDATORY qualifier for OB validity, not optional
         // confluence -- see YANSTD_EA_SYSTEM_GUIDE.md §48. (M3 refinement
         // below is the one place FVG stays optional; see haveValidM3OB.)
         double priorHigh = -DBL_MAX, priorLow = DBL_MAX;
         for(int s = i + 2; s < i + 14 && s < copied; s++)
         {
            priorHigh = MathMax(priorHigh, m5Rates[s].high);
            priorLow  = MathMin(priorLow,  m5Rates[s].low);
         }
         bool bullishLeg = (m5Rates[i+1].close > m5Rates[i+1].open && bodyRatio >= 0.60 &&
                            priorHigh > 0.0 && m5Rates[i+1].close > priorHigh);
         bool bearishLeg = (m5Rates[i+1].close < m5Rates[i+1].open && bodyRatio >= 0.60 &&
                            priorLow < DBL_MAX && m5Rates[i+1].close < priorLow);
         bool bullishFVG = ((m5Rates[i].low - m5Rates[i+2].high) > minGap);
         bool bearishFVG = ((m5Rates[i+2].low - m5Rates[i].high) > minGap);

         //================================================================
         // A. BULLISH FVG & DEMAND ORDER BLOCK (DISCOUNT ZONE)
         //================================================================
         // ICT 3-candle imbalance: Candle[i].Low (candle 3) > Candle[i+2].High (candle 1)
         if(bullishLeg && bullishFVG)
         {
            double fvgTop = m5Rates[i].low;
            double fvgBot = m5Rates[i+2].high;
            double fvgMid = (fvgTop + fvgBot) / 2.0;

            // The base immediately before displacement is the OB. Candle
            // colour is irrelevant; displacement + BOS/FVG defines the event.
            int obBar = i + 2;
            if(obBar >= copied) continue;
            double obTop = m5Rates[obBar].high;
            double obBot = m5Rates[obBar].low;

            // Rumus-Teknis Tahap 3: Lebar(Zona_OB_M5) <= 1.5 * ATR(M5,14)
            if(atrM5 > 0.0 && (obTop - obBot) > 1.5 * atrM5) continue;

            // Partial mitigation does not retire the OB. Historical rebuilds
            // use the same two-close M3 invalidation rule as live POIs.
            bool obMitigatedPrior = ZoneInvalidatedByClosedBars(
                                      ltfHistory, ltfCopied, m5Rates[obBar].time,
                                      true, obBot, obTop, m_poiInvalidationCloses,
                                      m_poiInvalidationBufferPips * pip);
            bool fvgMitigatedPrior = false;

            // M1 (2026-09-13, §49): CE 50% (fvgMid) is the sole eligibility
            // cutoff -- already correct here (closed-bar wick, causal scan
            // back from the last closed M5 bar). FVGValidator.mqh and
            // SMCLayerM15.mqh were the two modules still using an 80% fill
            // threshold; both now match this rule.
            for(int k = i - 1; k >= 1; k--)
            {
               if(m5Rates[k].low <= fvgMid)
                  fvgMitigatedPrior = true;
            }

            // H3-FVG: FVG is mandatory for an M5+ OB. Previously a failed
            // structural/mitigation check only blanked the fvg* fields while
            // still registering the zone as a valid demand OB (silently
            // becoming POI_PROFILE_OB_ONLY on M5). Now a disqualified FVG
            // means this candidate is not a valid OB at all on M5+ and is
            // skipped -- it is not demoted to an FVG-less OB.
            if(!obMitigatedPrior && !fvgMitigatedPrior &&
               IsFVGValidWithStructureFromRates(m5Rates, copied, i, m_mtfPeriod))
            {
               AddPOI(ZONE_DEMAND, obTop, obBot, m5Rates[obBar].time, obBar, fvgTop, fvgBot, fvgMid,
                      false, ClassifyOBColor(true, m5Rates[obBar].open, m5Rates[obBar].close));
            }
         }

         //================================================================
         // B. BEARISH FVG & SUPPLY ORDER BLOCK
         //================================================================
         // ICT 3-candle imbalance: Candle[i+2].Low (candle 1) > Candle[i].High (candle 3)
         if(bearishLeg && bearishFVG)
         {
            double fvgTop = m5Rates[i+2].low;
            double fvgBot = m5Rates[i].high;
            double fvgMid = (fvgTop + fvgBot) / 2.0;

            // The base immediately before displacement is the OB. Candle
            // colour is irrelevant; use its full wick-to-wick geometry.
            int obBar = i + 2;
            if(obBar >= copied) continue;
            double obTop = m5Rates[obBar].high;
            double obBot = m5Rates[obBar].low;

            // Rumus-Teknis Tahap 3: Lebar(Zona_OB_M5) <= 1.5 * ATR(M5,14)
            if(atrM5 > 0.0 && (obTop - obBot) > 1.5 * atrM5) continue;

            bool obMitigatedPrior = ZoneInvalidatedByClosedBars(
                                      ltfHistory, ltfCopied, m5Rates[obBar].time,
                                      false, obBot, obTop, m_poiInvalidationCloses,
                                      m_poiInvalidationBufferPips * pip);
            bool fvgMitigatedPrior = false;

            // M1 (2026-09-13, §49): CE 50% (fvgMid) is the sole eligibility
            // cutoff -- see the matching comment on the demand side above.
            for(int k = i - 1; k >= 1; k--)
            {
               if(m5Rates[k].high >= fvgMid)
                  fvgMitigatedPrior = true;
            }

            // H3-FVG: same mandatory-FVG rule as the demand side above -- a
            // disqualified FVG means no valid M5+ OB, not an FVG-less one.
            if(!obMitigatedPrior && !fvgMitigatedPrior &&
               IsFVGValidWithStructureFromRates(m5Rates, copied, i, m_mtfPeriod))
            {
               AddPOI(ZONE_SUPPLY, obTop, obBot, m5Rates[obBar].time, obBar, fvgTop, fvgBot, fvgMid,
                      false, ClassifyOBColor(false, m5Rates[obBar].open, m5Rates[obBar].close));
            }
         }

      }
      if(m_mtfPeriod != m_htfPeriod)
         AddMissingMSNRFallbackPOIs();

   }

   // Add POI with deduplication & width filtering
   void AddPOI(ENUM_ZONE_TYPE type, double top, double bottom, datetime t, int bar,
               double fvgTop = 0, double fvgBot = 0, double fvgMid = 0,
               bool isOTE = false, ENUM_OB_COLOR parentOBColor = OB_COLOR_UNKNOWN)
   {
      int historicalAge = MathMax(0, bar);
      if(m_zoneMaxBars > 0 && historicalAge > m_zoneMaxBars) return;
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      double widthPips = (top - bottom) / pip;
      if(widthPips < 2.0 || widthPips > 250.0) return; // Support Gold (XAUUSD) genuine zones
      // M6 (2026-09-13, §53): a zone that passed structural validation must be
      // stored regardless of how far it currently sits from price -- distance
      // to current price is not a permanent-validity criterion, it is an
      // entry-selection criterion (InpMaxEntryDistanceATR), applied only when
      // an entry is actually chosen/placed. A price-distance gate here used to
      // make a causally-valid POI disappear and reappear across rebuilds
      // purely because price moved, with no change to the formation itself.

      // MSNR is the primary map. Store an M5 refinement only when its area
      // intersects an active MSNR zone with the required structural
      // qualification. OTE is optional by default; strict mode is enforced
      // centrally by EvaluatePrimaryGate(). Keeping every standalone M5 OB/FVG
      // here used to pollute the finite POI array and starve the valid fallback.
      int admittedPrimaryZone = -1;
      if(m_useMSNR && m_msnr != NULL)
        {
         // MSNR map is a soft scoring overlay, never a hard veto: overlap is recorded
         // for grading but never discards the POI. PURE_SMC skips this entirely
         // (m_useMSNR is false and the map is never scanned).
         admittedPrimaryZone = m_msnr.FindBestOverlappingMapZone(bottom, top, type, 3.0);
        }

      for(int i = 0; i < m_poiCount; i++)
      {
         if(m_poiStore[PoiPhys(i)].type == type &&
            MathAbs(m_poiStore[PoiPhys(i)].top - top) / pip < 3.0 &&
            MathAbs(m_poiStore[PoiPhys(i)].bottom - bottom) / pip < 3.0)
             return; // Duplicate
      }

      // Do the formation-time lookup only for a genuinely new zone. The M5
      // scanner rediscovers existing history on every bar, so doing this before
      // deduplication would multiply backtest cost without changing state.
      double formationHigh = 0.0, formationLow = 0.0;
      bool haveFormationRange = GetFormationDealingRange(m_symbol, m_htfPeriod, t,
                                                          m_m15Depth, 180,
                                                          formationHigh, formationLow);
      if(haveFormationRange)
         isOTE = IsInOTEZone(type == ZONE_DEMAND ? top : bottom,
                             formationHigh, formationLow, type);
      else
         isOTE = false;

      if(m_poiCount >= MAX_ZONES)
         EvictOldestPOI(); // O(1) FIFO: advance head, reuse the freed slot as the new tail

      m_poiStore[PoiPhys(m_poiCount)].type             = type;
      m_poiStore[PoiPhys(m_poiCount)].top              = top;
      m_poiStore[PoiPhys(m_poiCount)].bottom           = bottom;
      m_poiStore[PoiPhys(m_poiCount)].createTime       = t;
      m_poiStore[PoiPhys(m_poiCount)].createBar        = bar;
      m_poiStore[PoiPhys(m_poiCount)].barAge           = historicalAge;
      m_poiStore[PoiPhys(m_poiCount)].isMitigated      = false;
      m_poiStore[PoiPhys(m_poiCount)].isExpired        = false;
      m_poiStore[PoiPhys(m_poiCount)].isActive         = true;
      m_poiStore[PoiPhys(m_poiCount)].primaryMSNRZoneIdx = admittedPrimaryZone;
      // hasFVG true HANYA jika caller sudah lolos IsFVGValidWithStructure
      // (koordinat di-nol-kan kalau FVG tidak layak jadi POI entry).
      m_poiStore[PoiPhys(m_poiCount)].hasFVG          = (fvgTop > 0 && fvgBot > 0 && fvgTop > fvgBot);
      m_poiStore[PoiPhys(m_poiCount)].fvgTop          = fvgTop;
      m_poiStore[PoiPhys(m_poiCount)].fvgBottom       = fvgBot;
      m_poiStore[PoiPhys(m_poiCount)].fvgMidpoint     = fvgMid;
      m_poiStore[PoiPhys(m_poiCount)].fvgMitigated    = false;
      m_poiStore[PoiPhys(m_poiCount)].hasPendingLimit = false;
      m_poiStore[PoiPhys(m_poiCount)].isOTE           = isOTE;
      // Provenance only: the colour of the base candle that formed this OB.
      // Never read by any eligibility, score, ranking or lot decision.
      m_poiStore[PoiPhys(m_poiCount)].parentOBColor    = parentOBColor;

      m_poiStore[PoiPhys(m_poiCount)].wasTouched      = false;
      m_poiStore[PoiPhys(m_poiCount)].firstTouchTime  = 0;
      m_poiStore[PoiPhys(m_poiCount)].lastTouchTime   = 0;
      m_poiStore[PoiPhys(m_poiCount)].touchPrice      = 0.0;
      m_poiStore[PoiPhys(m_poiCount)].touchWasFVG    = false;
      m_poiStore[PoiPhys(m_poiCount)].fiboSwingHigh  = formationHigh;
      m_poiStore[PoiPhys(m_poiCount)].fiboSwingLow   = formationLow;
      m_poiStore[PoiPhys(m_poiCount)].m3SweepConfirmed = false;
      m_poiStore[PoiPhys(m_poiCount)].m3SweepTime      = 0;
      m_poiStore[PoiPhys(m_poiCount)].m3SweepLevel     = 0.0;
      m_poiStore[PoiPhys(m_poiCount)].visHasM3OB       = false;
      m_poiStore[PoiPhys(m_poiCount)].visHasM3FVG      = false;
      m_poiStore[PoiPhys(m_poiCount)].visM3OBTop       = 0.0;
      m_poiStore[PoiPhys(m_poiCount)].visM3OBBottom    = 0.0;
      m_poiStore[PoiPhys(m_poiCount)].visM3FVGTop      = 0.0;
      m_poiStore[PoiPhys(m_poiCount)].visM3FVGBottom   = 0.0;
      for(int k = 0; k < ENTRY_VARIANT_COUNT; k++)
      {
         m_poiStore[PoiPhys(m_poiCount)].hasTriggeredLayer[k] = false;
         m_poiStore[PoiPhys(m_poiCount)].hasPendingLayer[k] = false;
         m_poiStore[PoiPhys(m_poiCount)].pendingEventId[k] = 0;
      }
      m_poiStore[PoiPhys(m_poiCount)].layerCount      = 0;
      m_poiStore[PoiPhys(m_poiCount)].tf              = m_mtfPeriod;
      m_poiStore[PoiPhys(m_poiCount)].tfLabel          = StringSubstr(EnumToString(m_mtfPeriod), 7);
      string uniqueId = IntegerToString((long)t) + "_" + IntegerToString(m_poiObjSeq++); // AUDIT FIX: monotonic seq prevents collision
      m_poiStore[PoiPhys(m_poiCount)].objName          = YANSTD_PREFIX + (type == ZONE_DEMAND ? "POI_OB_D_" : "POI_OB_S_") + uniqueId;
      m_poiStore[PoiPhys(m_poiCount)].fvgObjName       = YANSTD_PREFIX + (type == ZONE_DEMAND ? "POI_FVG_D_" : "POI_FVG_S_") + uniqueId;
      m_poiCount++;
      m_poiRevision++;
   }

   // M5 is a refinement layer, not a prerequisite. For every primary M15
   // MSNR zone that already passes the hard Layer-2 OB/FVG confluence, retain
   // the M5 POI when one overlaps; otherwise expose the wider M15 zone to the
   // same M3 touch -> CHoCH -> causal OB/FVG refinement flow.
   void AddMissingMSNRFallbackPOIs()
   {
      if(m_msnr == NULL || !m_useMSNR || m_mtfPeriod == m_htfPeriod) return;
      int zones = m_msnr.GetZoneCount();
      for(int z = 0; z < zones && m_poiCount < MAX_ZONES; z++)
        {
         SMSNR_Zone zone;
         if(!m_msnr.GetZone(z, zone) || !zone.isActive || zone.isMitigated) continue;
         bool demand = MsnrIsDemand(zone.msnrType);
         ENUM_ZONE_TYPE side = demand ? ZONE_DEMAND : ZONE_SUPPLY;

         int qualifiedZone = -1, failureCode = 0;
         if(!m_msnr.EvaluatePrimaryGate(zone.bottom, zone.top, side, 3.0,
                                        qualifiedZone, failureCode)) continue;

         bool hasM5Refinement = false;
         for(int i = 0; i < m_poiCount; i++)
           {
            if(!m_poiStore[PoiPhys(i)].isActive || m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated ||
               m_poiStore[PoiPhys(i)].type != side || m_poiStore[PoiPhys(i)].tf != m_mtfPeriod) continue;
            if(m_poiStore[PoiPhys(i)].top >= zone.bottom && m_poiStore[PoiPhys(i)].bottom <= zone.top)
              {
               hasM5Refinement = true;
               break;
              }
           }
         if(hasM5Refinement) continue;

         int before = m_poiCount;
         double fvgMid = (zone.fvgTop > zone.fvgBottom)
                         ? (zone.fvgTop + zone.fvgBottom) * 0.5 : 0.0;
         AddPOI(side, zone.top, zone.bottom, zone.createTime, 0,
                zone.fvgTop, zone.fvgBottom, fvgMid, zone.isInOTE);
         if(m_poiCount > before)
           {
            int idx = m_poiCount - 1;
            m_poiStore[PoiPhys(idx)].isOTE = zone.isInOTE;
            m_poiStore[PoiPhys(idx)].fiboSwingHigh = zone.fiboSwingHigh;
            m_poiStore[PoiPhys(idx)].fiboSwingLow = zone.fiboSwingLow;
            m_poiStore[PoiPhys(idx)].tf = m_htfPeriod;
            m_poiStore[PoiPhys(idx)].tfLabel = StringSubstr(EnumToString(m_htfPeriod), 7) + "_FALLBACK";
           }
        }
   }

   void SetPOILayerTriggered(int poiIdx, ENUM_SMC_ENTRY_TYPE setupType, int maxLayers = 4)
   {
      if(poiIdx >= 0 && poiIdx < m_poiCount)
      {
         int st = (int)setupType;
         if(st >= 0 && st < ENTRY_VARIANT_COUNT) m_poiStore[PoiPhys(poiIdx)].hasTriggeredLayer[st] = true;
         m_poiStore[PoiPhys(poiIdx)].layerCount++;
         if(m_poiStore[PoiPhys(poiIdx)].layerCount >= maxLayers)
         {
            m_poiStore[PoiPhys(poiIdx)].isMitigated = true;
            m_poiStore[PoiPhys(poiIdx)].isActive    = false;
         }
      }
   }

   bool SetMatchingPOILayerTriggered(ENUM_ZONE_TYPE type, double entryPrice,
                                     ENUM_SMC_ENTRY_TYPE setupType, int maxLayers = 4)
   {
      double pip = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * GetPipFactor(m_symbol);
      int bestIdx = -1;
      double bestDist = DBL_MAX;
      for(int i = 0; i < m_poiCount; i++)
        {
         if(m_poiStore[PoiPhys(i)].type != type || !m_poiStore[PoiPhys(i)].isActive || m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated) continue;
         if(entryPrice < m_poiStore[PoiPhys(i)].bottom - 5.0 * pip || entryPrice > m_poiStore[PoiPhys(i)].top + 5.0 * pip) continue;
         double dist = MathAbs(entryPrice - (m_poiStore[PoiPhys(i)].top + m_poiStore[PoiPhys(i)].bottom) / 2.0);
         if(dist < bestDist) { bestDist = dist; bestIdx = i; }
        }
      if(bestIdx < 0) return false;
      SetPOILayerTriggered(bestIdx, setupType, maxLayers);
      return true;
   }

   SSignal GenerateSignal(double riskPct, bool useRiskPct, double fixedLot,
                          bool invalidatePOI = true, bool mutateState = true)
   {
      SSignal sig;
      sig.direction      = SIGNAL_NONE;
      sig.isValid        = false;
      sig.brainBucketIdx = -1;
      sig.aiConfidence   = 50.0;
      sig.qualityScore   = 0.0;
      sig.refinedOBTop = sig.refinedOBBottom = 0.0;
      sig.refinedFVGTop = sig.refinedFVGBottom = 0.0;
      sig.fiboSwingHigh = sig.fiboSwingLow = 0.0;
      sig.parentOBColor = OB_COLOR_UNKNOWN;
      sig.executionOBColor = OB_COLOR_UNKNOWN;
      sig.setupEventId = 0;
      sig.setupGrade     = GRADE_D;
      sig.gradeLotMult   = 0.0;
      sig.poiProfile     = POI_PROFILE_OB_ONLY;
      sig.obMitigation   = OB_MITIGATION_50;
      sig.fvgMitigation  = FVG_MITIGATION_NONE;
      sig.fibLevel       = FIB_LEVEL_NONE;
      sig.invalidReason  = "SMC Scanning...";
      SSignal bestSig = sig;
      double bestScore = -DBL_MAX;

      // Real-tick tests expose historical spread; zero remains accepted for
      // OHLC datasets/brokers that do not provide one.
      int spreadPts = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(spreadPts > 0 && spreadPts > m_maxSpreadPoints)
        {
            sig.invalidReason = StringFormat("Spread high (%d > %d pts)", spreadPts, m_maxSpreadPoints);
            RecordReject(REJECT_SPREAD);
            return sig;
        }

      // Check current M3 bar close (for invalidation check)
      double m3Close1 = iClose(m_symbol, m_ltfPeriod, 1);
      double point    = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double pip      = point * GetPipFactor(m_symbol);

      SMC_SwingPoint m3SwHigh, m3PrevHigh, m3SwLow, m3PrevLow;
      datetime ltfStructureBar = iTime(m_symbol, m_ltfPeriod, 0);
      if(ltfStructureBar != m_cachedLTFStructureBar)
        {
         m_cachedHaveLTFStructure = m_zz.GetStructureSwings(m_ltfPeriod, m_m3Depth, m_m3Dev, m_m3Back,
                                                            m_cachedLTFHigh, m_cachedLTFPrevHigh,
                                                            m_cachedLTFLow, m_cachedLTFPrevLow);
         m_cachedLTFStructureBar = ltfStructureBar;
        }
      bool haveM3Structure = m_cachedHaveLTFStructure;
      m3SwHigh = m_cachedLTFHigh; m3PrevHigh = m_cachedLTFPrevHigh;
      m3SwLow = m_cachedLTFLow; m3PrevLow = m_cachedLTFPrevLow;

      MqlRates m3Rates[];
      ArraySetAsSeries(m3Rates, true);
      int copiedM3 = CopyRates(m_symbol, m_ltfPeriod, 0, 10, m3Rates);
      if(copiedM3 < 3)
        {
         sig.invalidReason = "LTF data unavailable";
         RecordReject(REJECT_DATA_UNAVAILABLE);
         return sig;
        }
      if(iClose(m_symbol, m_ltfPeriod, 1) <= 0.0)
         m3Close1 = m3Rates[1].close;

      double curAsk = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double curBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double atrM3touch = GetCachedATR(m_symbol, m_ltfPeriod, (m_atrPeriod > 0 ? m_atrPeriod : 14));
      double touchK = (atrM3touch > 0.0 && pip > 0.0) ? MathMax(1.0, (0.10 * atrM3touch) / (1.5 * pip)) : 1.0;

      if(m_diagnostics != NULL) m_diagnostics.MarkEvaluation((long)iTime(m_symbol, m_ltfPeriod, 0));
      if(m_poiCount <= 0) RecordReject(REJECT_NO_ACTIVE_POI);

      for(int i = 0; i < m_poiCount; i++)
      {
         if(!m_poiStore[PoiPhys(i)].isActive || m_poiStore[PoiPhys(i)].isExpired || m_poiStore[PoiPhys(i)].isMitigated) continue;

         int primaryZone = m_poiStore[PoiPhys(i)].primaryMSNRZoneIdx;
         bool counterTrend = false;
         ENUM_SIGNAL_TYPE candidateDir = (m_poiStore[PoiPhys(i)].type == ZONE_DEMAND) ? SIGNAL_BUY : SIGNAL_SELL;
         if(!IsDirectionAllowed(candidateDir, counterTrend))
           {
            RecordReject(REJECT_DIRECTION_BIAS, i);
            continue;
           }
         sig.brainBucketIdx = -1;

         //================================================================
         // A. DEMAND POI / FVG (BULLISH ENTRY AT DISCOUNT RETEST)
         //================================================================
         if(m_poiStore[PoiPhys(i)].type == ZONE_DEMAND)
         {
            // Location was already validated causally against the formation
            // dealing range by the MSNR OTE gate. Rechecking it against the
            // latest, moving M15 equilibrium created a contradictory veto.
            if(IsPOIInvalidated(m_poiStore[PoiPhys(i)], m3Rates, copiedM3))
            {
               if(invalidatePOI)
               {
                m_poiStore[PoiPhys(i)].isMitigated = true;
                m_poiStore[PoiPhys(i)].isActive    = false;
               }
               RecordReject(REJECT_POI_INVALIDATED, i);
               continue;
            }

            // 2. Mitigation Depth Proximity: Order Block Retest or FVG Consequent Encroachment
            bool   inOB_OTE  = (curAsk <= (m_poiStore[PoiPhys(i)].top + 1.5 * pip * touchK) && curAsk >= (m_poiStore[PoiPhys(i)].bottom - 0.5 * pip * touchK));
            bool   inFVG_CE  = (m_poiStore[PoiPhys(i)].hasFVG && curAsk <= (m_poiStore[PoiPhys(i)].fvgMidpoint + 1.5 * pip * touchK)
                                                 && curAsk >= (m_poiStore[PoiPhys(i)].fvgBottom - 1.0 * pip * touchK)); // OPT-A

            if((inOB_OTE || inFVG_CE) && mutateState)
            {
               bool firstTouch = !m_poiStore[PoiPhys(i)].wasTouched || m_poiStore[PoiPhys(i)].touchPrice <= 0.0;
               m_poiStore[PoiPhys(i)].wasTouched = true;
               if(firstTouch) m_poiStore[PoiPhys(i)].firstTouchTime = (copiedM3 > 0 ? m3Rates[0].time : TimeCurrent());
               m_poiStore[PoiPhys(i)].lastTouchTime = TimeCurrent();
               m_poiStore[PoiPhys(i)].touchPrice = firstTouch ? curAsk : MathMin(m_poiStore[PoiPhys(i)].touchPrice, curAsk);
               m_poiStore[PoiPhys(i)].touchWasFVG = m_poiStore[PoiPhys(i)].touchWasFVG || inFVG_CE;
            }
            int confirmSeconds = 6 * PeriodSeconds(m_ltfPeriod);
             if(!m_poiStore[PoiPhys(i)].wasTouched || TimeCurrent() - m_poiStore[PoiPhys(i)].lastTouchTime > confirmSeconds)
             {
               if(m_poiStore[PoiPhys(i)].wasTouched) RecordReject(REJECT_CHOCH_TIMEOUT, i);
               else                     RecordReject(REJECT_NOT_IN_POI, i);
                if(mutateState)
                  {
                   m_poiStore[PoiPhys(i)].wasTouched = false;
                   m_poiStore[PoiPhys(i)].firstTouchTime = 0;
                   m_poiStore[PoiPhys(i)].touchPrice = 0.0;
                   m_poiStore[PoiPhys(i)].touchWasFVG = false;
                   m_poiStore[PoiPhys(i)].m3SweepConfirmed = false;
                   m_poiStore[PoiPhys(i)].m3SweepTime = 0;
                   m_poiStore[PoiPhys(i)].m3SweepLevel = 0.0;
                  }
                 continue;
            }

            ENUM_POI_PROFILE poiProfile;
            ENUM_OB_MITIGATION obMitigation;
            ENUM_FVG_MITIGATION fvgMitigation;
            ENUM_FIB_LEVEL fibLevel;
            ClassifyPattern(m_poiStore[PoiPhys(i)].touchPrice, m_poiStore[PoiPhys(i)], poiProfile, obMitigation, fvgMitigation, fibLevel);

            ENUM_SMC_ENTRY_TYPE setupType = ENTRY_TYPE_OB_45;
            if(m_poiStore[PoiPhys(i)].touchWasFVG && fvgMitigation == FVG_MITIGATION_50)
            {
               setupType = ENTRY_TYPE_FVG_50;
            }
            else if(inOB_OTE)
            {
               setupType = (obMitigation == OB_MITIGATION_15) ? ENTRY_TYPE_OB_15 : ENTRY_TYPE_OB_45;
            }

            // Multi-Layer Exploration: Skip if this specific level already triggered on this POI
            if(m_poiStore[PoiPhys(i)].hasTriggeredLayer[setupType]) { RecordReject(REJECT_LAYER_DUPLICATE, i); continue; }

            // 3a. M3 sell-side liquidity sweep. Detected independently of the
            // CHoCH gate so the sweep timestamp can become the CHoCH anchor.
            // When m_requireM3Sweep is true this is a HARD joint condition
            // with CHoCH (Rumus-Teknis Tahap 4). When false it only boosts score.
            double atrM3s = GetCachedATR(m_symbol, m_ltfPeriod, (m_atrPeriod > 0 ? m_atrPeriod : 14));
            if(mutateState && !m_poiStore[PoiPhys(i)].m3SweepConfirmed)
            {
               double sweepRef = (m3PrevLow.price > 0.0) ? m3PrevLow.price : m3SwLow.price;
               int sweepBars = MathMin(3, copiedM3 - 1);
               // Rumus-Teknis Tahap 4A: Buffer = 0.05 * ATR(M3, 14)
               double sweepDepth = (atrM3s > 0.0) ? (0.05 * atrM3s) : point;
               for(int s = 1; s <= sweepBars && sweepRef > 0.0; s++)
               {
                  if(m3Rates[s].low < sweepRef - sweepDepth && m3Rates[s].close > sweepRef)
                  {
                     m_poiStore[PoiPhys(i)].m3SweepConfirmed = true;
                     m_poiStore[PoiPhys(i)].m3SweepTime = m3Rates[s].time;
                     m_poiStore[PoiPhys(i)].m3SweepLevel = sweepRef;
                     break;
                  }
               }
            }
            // 3b. CHoCH must occur after the initial touch; if a sweep was
            // observed, the sweep becomes the stricter confirmation anchor.
            double bullRange = m3Rates[1].high - m3Rates[1].low;
            double bullBody  = MathAbs(m3Rates[1].close - m3Rates[1].open);
            bool microWasBearish = haveM3Structure &&
                                   (m3SwHigh.price < m3PrevHigh.price && m3SwLow.price < m3PrevLow.price);
            datetime bullAnchor = m_poiStore[PoiPhys(i)].m3SweepConfirmed ? m_poiStore[PoiPhys(i)].m3SweepTime
                                                              : m_poiStore[PoiPhys(i)].firstTouchTime;
            // Rumus-Teknis Tahap 4B: Bullish CHoCH Close > (pivot high + Buffer), Buffer = 0.05 * ATR(M3, 14)
            double chochBuffer = (atrM3s > 0.0) ? (0.05 * atrM3s) : 0.0;
            bool bullChoCH = (bullAnchor > 0 && m3Rates[1].time >= bullAnchor && microWasBearish &&
                              bullRange > 0.0 && bullBody / bullRange >= 0.55 &&
                              m3Rates[1].close > m3Rates[1].open && m3SwHigh.price > 0.0 &&
                              m3Close1 > (m3SwHigh.price + chochBuffer) && m3Rates[2].close <= m3SwHigh.price);
            if(m_requireM3Sweep && !m_poiStore[PoiPhys(i)].m3SweepConfirmed)
              { RecordReject(REJECT_SWEEP_NOT_CONFIRMED, i); continue; }
            bool isBullReversal = bullChoCH;
            if(!isBullReversal) { RecordReject(REJECT_CHOCH_NOT_CONFIRMED, i); continue; }

            double refinedEntry = 0.0;
            double refinedWidth = DBL_MAX;
            double refinedOBTop = 0.0, refinedOBBottom = 0.0;
            double refinedFVGTop = 0.0, refinedFVGBottom = 0.0;
            ENUM_SMC_ENTRY_TYPE refinedType = ENTRY_TYPE_OB_45;
            bool haveValidM3OB = false;
            bool haveValidM3FVG = false;
            ENUM_OB_COLOR refinedOBColor = OB_COLOR_UNKNOWN;
            const int ob = 2;
            const double obSweepDepth = (atrM3s > 0.0) ? (0.05 * atrM3s) : point;
            const double obSweepRef = (m3PrevLow.price > 0.0) ? m3PrevLow.price : m3SwLow.price;
            const bool obCandleIsSweep = (copiedM3 > ob && obSweepRef > 0.0 &&
                                          m3Rates[ob].low < obSweepRef - obSweepDepth &&
                                          m3Rates[ob].close > obSweepRef);
            const bool displacementCreatesFVG = (copiedM3 >= 4 && m3Rates[1].low > m3Rates[3].high);
            if(copiedM3 > ob)
            {
               double width = m3Rates[ob].high - m3Rates[ob].low;
               if(width > 0.0 && obCandleIsSweep)  // AUDIT FIX: FVG decoupled from OB_45 gate
                {
                  refinedOBTop = m3Rates[ob].high;
                  refinedOBBottom = m3Rates[ob].low;
                  refinedWidth = width;
                  refinedEntry = (refinedOBTop + refinedOBBottom) * 0.5;
                  refinedType = ENTRY_TYPE_OB_45;
                  refinedOBColor = ClassifyOBColor(true, m3Rates[ob].open, m3Rates[ob].close);
                  haveValidM3OB = true;
                }
            }
            if(displacementCreatesFVG && IsFVGValidWithStructureFromRates(m3Rates, copiedM3, 1, m_ltfPeriod))
            {
               refinedFVGTop = m3Rates[1].low;
               refinedFVGBottom = m3Rates[3].high;
               double width = refinedFVGTop - refinedFVGBottom;
               if(width > 0.0)
               {
                  haveValidM3FVG = true;
                  if(!haveValidM3OB || width < refinedWidth)
                  {
                     refinedWidth = width;
                     refinedEntry = (refinedFVGTop + refinedFVGBottom) * 0.5;
                     refinedType = ENTRY_TYPE_FVG_50;
                  }
               }
            }
            if(!haveValidM3OB && !haveValidM3FVG)
              { RecordReject(REJECT_OB_NO_FVG, i, 23); continue; }
            {
               const double parentTop    = m_poiStore[PoiPhys(i)].top;
               const double parentBottom = m_poiStore[PoiPhys(i)].bottom;
               const double refTop    = (refinedType == ENTRY_TYPE_FVG_50) ? refinedFVGTop    : refinedOBTop;
               const double refBottom = (refinedType == ENTRY_TYPE_FVG_50) ? refinedFVGBottom : refinedOBBottom;
               const double clampTol  = (atrM3s > 0.0) ? (0.05 * atrM3s) : point;
               if(refTop > parentTop + clampTol || refBottom < parentBottom - clampTol)
                 { RecordReject(REJECT_M3_OUTSIDE_PARENT_ZONE, i, 23); continue; }
            }
            if(refinedEntry <= 0.0 || refinedEntry >= curAsk)
              { RecordReject(REJECT_DISTANCE, i, 23); continue; }
            m_poiStore[PoiPhys(i)].visHasM3OB = (refinedOBTop > refinedOBBottom);
            m_poiStore[PoiPhys(i)].visHasM3FVG = (refinedFVGTop > refinedFVGBottom);
            m_poiStore[PoiPhys(i)].visM3OBTop = refinedOBTop;
            m_poiStore[PoiPhys(i)].visM3OBBottom = refinedOBBottom;
            m_poiStore[PoiPhys(i)].visM3FVGTop = refinedFVGTop;
            m_poiStore[PoiPhys(i)].visM3FVGBottom = refinedFVGBottom;
            setupType = refinedType;
            if(m_poiStore[PoiPhys(i)].hasTriggeredLayer[setupType] || m_poiStore[PoiPhys(i)].hasPendingLayer[setupType])
              { RecordReject(REJECT_LAYER_DUPLICATE, i, 23); continue; }

            // Brain identity must describe the same M3 execution object used
            // by live and matrix, not the wider M5 parent POI.
            SMC_Zone refinedBrainZone = m_poiStore[PoiPhys(i)];
            if(refinedType == ENTRY_TYPE_FVG_50 && refinedFVGTop > refinedFVGBottom)
              {
               refinedBrainZone.top = refinedFVGTop;
               refinedBrainZone.bottom = refinedFVGBottom;
              }
            else if(refinedOBTop > refinedOBBottom)
              {
               refinedBrainZone.top = refinedOBTop;
               refinedBrainZone.bottom = refinedOBBottom;
              }
            else if(refinedFVGTop > refinedFVGBottom)
              {
               refinedBrainZone.top = refinedFVGTop;
               refinedBrainZone.bottom = refinedFVGBottom;
              }
            refinedBrainZone.hasFVG = (refinedFVGTop > refinedFVGBottom);
            refinedBrainZone.fvgTop = refinedFVGTop;
            refinedBrainZone.fvgBottom = refinedFVGBottom;
            refinedBrainZone.fvgMidpoint = refinedBrainZone.hasFVG
                                           ? (refinedFVGTop + refinedFVGBottom) * 0.5 : 0.0;
            ClassifyPattern(refinedEntry, refinedBrainZone,
                            poiProfile, obMitigation, fvgMitigation, fibLevel);

            // 4. Calculate Strict Tight SMC Stop Loss (Below POI Bottom with Dynamic ATR buffer)
            double slBuffer = m_useDynamicSLBuffer ? GetDynamicSLBuffer(m_slBufferPips, m_slATRMult)
                                                   : (m_slBufferPips * pip);
            double bidNow = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            double askNow = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            double executionBuffer = MathMax((double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point,
                                             MathMax(0.0, askNow - bidNow));
            double sl  = refinedBrainZone.bottom - slBuffer - executionBuffer;
            if(m_useMSNR && m_msnr != NULL)
              {
               double qmlHead = 0.0;
               bool qmlDemand = false;
               if(m_msnr.GetQmlHeadPrice(primaryZone, qmlHead, qmlDemand) && qmlDemand && qmlHead > 0.0)
                  sl = MathMin(sl, qmlHead - slBuffer - executionBuffer);
              }
            double slP = (refinedEntry - sl) / pip;
            ApplyEngineStopBounds(true, refinedEntry, pip, sl, slP);

            double riskDistance = refinedEntry - sl;
            double tp1 = 0.0;
            double tp2 = 0.0;
            if(m_useMSNR && m_msnr != NULL)
              {
               double opp = m_msnr.GetNearestOpposingTarget(refinedEntry, ZONE_DEMAND);
               if(opp > refinedEntry)
                 {
                  tp2 = opp;
                  double distPips = (tp2 - refinedEntry) / pip;
                  if(m_poiPartialPips > 0.0 && distPips > m_poiPartialPips)
                     tp1 = refinedEntry + m_poiPartialPips * pip;
                 }
              }
            if(tp2 <= refinedEntry && m_poiPartialPips > 0.0)
              {
               tp1 = refinedEntry + m_poiPartialPips * pip;
               tp2 = 0.0;
              }

            double conf = 88.0;
            SBrainBucketView aiView;
            BrainViewReset(aiView);
            ENUM_SETUP_GRADE grade = EvaluateSetupGrade(primaryZone, true, counterTrend,
                                                       refinedEntry, sl, tp2, ZONE_DEMAND,
                                                       m_poiStore[PoiPhys(i)].isOTE);
            double gradeMult = SetupGradeLotMultiplier(grade);
            if(SetupGradeRejects(grade) || gradeMult <= 0.0)
              { RecordReject(REJECT_SETUP_GRADE, i, 25); continue; }
            if(m_brain != NULL)
            {
               ENUM_SESSION_TYPE sess = (m_session != NULL) ? m_session.GetCurrentSession() : SESSION_ASIA;
                 int bIdx = m_brain.GetBucketIndex(sess, SIGNAL_BUY,
                                                    MathMax((refinedBrainZone.top - refinedBrainZone.bottom)/pip,
                                                            m_msnr.GetZoneWidthPips(primaryZone)), m_trendBullPct,
                                                  poiProfile, obMitigation, fvgMitigation, fibLevel);
               m_brain.GetBucketView(bIdx, aiView);
               conf = aiView.valid ? aiView.confidence : conf;

               // Apply Quality Boosters (display/logging weight only -- never gates entry)
               if(m_useLiquiditySweepBoost && m_poiStore[PoiPhys(i)].m3SweepConfirmed) conf = MathMin(99.0, conf + 12.0);
               if(m_useOTEBoost && m_poiStore[PoiPhys(i)].isOTE)                       conf = MathMin(99.0, conf + 8.0);

               sig.brainBucketIdx = bIdx;
            }

            double smcScore = 50.0;
            if(m_poiStore[PoiPhys(i)].hasFVG) smcScore += 12.0;
            smcScore += MathMax(0.0, (20.0 - m_poiStore[PoiPhys(i)].barAge)) / 20.0 * 10.0;
            if(m_useLiquiditySweepBoost && m_poiStore[PoiPhys(i)].m3SweepConfirmed) smcScore += 12.0;
            if(m_useOTEBoost && m_poiStore[PoiPhys(i)].isOTE) smcScore += 8.0;

            if(m_useMSNR && m_msnr != NULL)
               smcScore += m_msnr.GetConfluenceBonus(curAsk, ZONE_DEMAND, 15.0, 15.0);
            smcScore = ApplyInstitutionalSoftScore(m_poiStore[PoiPhys(i)], SIGNAL_BUY, smcScore, counterTrend);

            double effRisk = riskPct;
            if(!m_brainExplorationMode)
            {
               effRisk *= gradeMult;
               if(m_useDynamicRisk)
                  effRisk *= BrainRiskOverlayMultiplier(aiView);
               if(m_maxAggregateRiskPct > 0.0 && effRisk > m_maxAggregateRiskPct)
                  effRisk = m_maxAggregateRiskPct;
            }
            // Session lot multipliers are disabled (Asia/EU/NY no longer resize).
            double finalScore = smcScore;
            if(finalScore < GetMinimumSoftScore(counterTrend))
              { RecordReject(counterTrend ? REJECT_DIRECTION_BIAS : REJECT_SOFT_SCORE, i, 5); continue; }

            sig.direction    = SIGNAL_BUY;
            sig.entryType    = setupType;
            sig.poiProfile   = poiProfile;
            sig.obMitigation = obMitigation;
            sig.fvgMitigation= fvgMitigation;
            sig.fibLevel     = fibLevel;
            sig.entryPrice   = NormalisePrice(refinedEntry, m_symbol);
            sig.slPrice      = NormalisePrice(sl, m_symbol);
            sig.slPips       = slP;
            sig.tp1Price     = NormalisePrice(tp1, m_symbol);
            sig.tp2Price     = NormalisePrice(tp2, m_symbol);
            sig.tp1Pips      = (tp1 - refinedEntry) / pip;
            sig.tp2Pips      = (tp2 - refinedEntry) / pip;
            sig.riskPct      = effRisk;
            sig.setupGrade   = grade;
            sig.gradeLotMult = gradeMult;
            sig.lotSize      = useRiskPct ? m_rc.CalcLotSize(effRisk, slP, m_symbol,
                                                               refinedEntry, ORDER_TYPE_BUY)
                                            : m_rc.RoundLotToStep(fixedLot);
            if(useRiskPct && m_diagnostics != NULL)
              {
               if(m_rc.LastLotStatus() == LOT_STATUS_CLAMP) m_diagnostics.RecordLotClamp();
               else if(m_rc.LastLotStatus() == LOT_STATUS_FALLBACK) m_diagnostics.RecordLotFallback();
              }
            sig.lotSize      = EnforceBrokerMinLot(sig.lotSize > 0.0 ? sig.lotSize : YANSTD_HARD_MIN_LOT, m_symbol);
            sig.zoneIndex    = i;
            sig.signalTime   = TimeCurrent();
            sig.aiConfidence = conf;
            sig.qualityScore = finalScore;
            sig.refinedOBTop = refinedOBTop;
            sig.refinedOBBottom = refinedOBBottom;
            sig.refinedFVGTop = refinedFVGTop;
            sig.refinedFVGBottom = refinedFVGBottom;
            sig.fiboSwingHigh = m_poiStore[PoiPhys(i)].fiboSwingHigh;
            sig.fiboSwingLow = m_poiStore[PoiPhys(i)].fiboSwingLow;
            // Provenance only (chart/attribution): parent OB colour from the M5
            // zone, execution OB colour from the M3 refinement candle.
            sig.parentOBColor = m_poiStore[PoiPhys(i)].parentOBColor;
            sig.executionOBColor = refinedOBColor;
            sig.isValid      = true;
            sig.invalidReason = counterTrend ? "Counter-bias scalp: strict score passed" : "Best SMC candidate";
            if(finalScore > bestScore) { bestScore = finalScore; bestSig = sig; }
            continue;
         }

         //================================================================
         // B. SUPPLY POI / FVG (BEARISH ENTRY AT PREMIUM RETEST)
         //================================================================
         else if(m_poiStore[PoiPhys(i)].type == ZONE_SUPPLY)
         {
            // Do not apply a second moving-equilibrium veto here. The primary
            // MSNR zone and its M15 SMC overlap already carry the OTE location.

            // 1. Invalidation Check: Candle closed above POI Top -> Invalidated
            if(IsPOIInvalidated(m_poiStore[PoiPhys(i)], m3Rates, copiedM3))
            {
               if(invalidatePOI)
               {
                m_poiStore[PoiPhys(i)].isMitigated = true;
                m_poiStore[PoiPhys(i)].isActive    = false;
               }
               RecordReject(REJECT_POI_INVALIDATED, i);
               continue;
            }

            // 2. Mitigation Depth Proximity: Order Block Retest or FVG Consequent Encroachment
            bool   inOB_OTE  = (curBid >= (m_poiStore[PoiPhys(i)].bottom - 1.5 * pip * touchK) && curBid <= (m_poiStore[PoiPhys(i)].top + 0.5 * pip * touchK));
            bool   inFVG_CE  = (m_poiStore[PoiPhys(i)].hasFVG && curBid >= (m_poiStore[PoiPhys(i)].fvgMidpoint - 1.5 * pip * touchK)
                                                 && curBid <= (m_poiStore[PoiPhys(i)].fvgTop + 1.0 * pip * touchK)); // OPT-A

            if((inOB_OTE || inFVG_CE) && mutateState)
            {
               bool firstTouch = !m_poiStore[PoiPhys(i)].wasTouched || m_poiStore[PoiPhys(i)].touchPrice <= 0.0;
               m_poiStore[PoiPhys(i)].wasTouched = true;
               if(firstTouch) m_poiStore[PoiPhys(i)].firstTouchTime = (copiedM3 > 0 ? m3Rates[0].time : TimeCurrent());
               m_poiStore[PoiPhys(i)].lastTouchTime = TimeCurrent();
               m_poiStore[PoiPhys(i)].touchPrice = firstTouch ? curBid : MathMax(m_poiStore[PoiPhys(i)].touchPrice, curBid);
               m_poiStore[PoiPhys(i)].touchWasFVG = m_poiStore[PoiPhys(i)].touchWasFVG || inFVG_CE;
            }
            int confirmSeconds = 6 * PeriodSeconds(m_ltfPeriod);
             if(!m_poiStore[PoiPhys(i)].wasTouched || TimeCurrent() - m_poiStore[PoiPhys(i)].lastTouchTime > confirmSeconds)
             {
               if(m_poiStore[PoiPhys(i)].wasTouched) RecordReject(REJECT_CHOCH_TIMEOUT, i);
               else                     RecordReject(REJECT_NOT_IN_POI, i);
                if(mutateState)
                  {
                   m_poiStore[PoiPhys(i)].wasTouched = false;
                   m_poiStore[PoiPhys(i)].firstTouchTime = 0;
                   m_poiStore[PoiPhys(i)].touchPrice = 0.0;
                   m_poiStore[PoiPhys(i)].touchWasFVG = false;
                   m_poiStore[PoiPhys(i)].m3SweepConfirmed = false;
                   m_poiStore[PoiPhys(i)].m3SweepTime = 0;
                   m_poiStore[PoiPhys(i)].m3SweepLevel = 0.0;
                  }
                 continue;
            }

            ENUM_POI_PROFILE poiProfile;
            ENUM_OB_MITIGATION obMitigation;
            ENUM_FVG_MITIGATION fvgMitigation;
            ENUM_FIB_LEVEL fibLevel;
            ClassifyPattern(m_poiStore[PoiPhys(i)].touchPrice, m_poiStore[PoiPhys(i)], poiProfile, obMitigation, fvgMitigation, fibLevel);

            ENUM_SMC_ENTRY_TYPE setupType = ENTRY_TYPE_OB_45;
            if(m_poiStore[PoiPhys(i)].touchWasFVG && fvgMitigation == FVG_MITIGATION_50)
            {
               setupType = ENTRY_TYPE_FVG_50;
            }
            else if(inOB_OTE)
            {
               setupType = (obMitigation == OB_MITIGATION_15) ? ENTRY_TYPE_OB_15 : ENTRY_TYPE_OB_45;
            }

            // Multi-Layer Exploration: Skip if this specific level already triggered on this POI
            if(m_poiStore[PoiPhys(i)].hasTriggeredLayer[setupType]) { RecordReject(REJECT_LAYER_DUPLICATE, i); continue; }

            // 3a. M3 buy-side liquidity sweep. Same joint-gate policy as demand.
            double atrM3s = GetCachedATR(m_symbol, m_ltfPeriod, (m_atrPeriod > 0 ? m_atrPeriod : 14));
            if(mutateState && !m_poiStore[PoiPhys(i)].m3SweepConfirmed)
            {
               double sweepRef = (m3PrevHigh.price > 0.0) ? m3PrevHigh.price : m3SwHigh.price;
               int sweepBars = MathMin(3, copiedM3 - 1);
               // Rumus-Teknis Tahap 4A: Buffer = 0.05 * ATR(M3, 14)
               double sweepDepth = (atrM3s > 0.0) ? (0.05 * atrM3s) : point;
               for(int s = 1; s <= sweepBars && sweepRef > 0.0; s++)
               {
                  if(m3Rates[s].high > sweepRef + sweepDepth && m3Rates[s].close < sweepRef)
                  {
                     m_poiStore[PoiPhys(i)].m3SweepConfirmed = true;
                     m_poiStore[PoiPhys(i)].m3SweepTime = m3Rates[s].time;
                     m_poiStore[PoiPhys(i)].m3SweepLevel = sweepRef;
                     break;
                  }
               }
            }
            // 3b. CHoCH closes after touch, or after the sweep when
            // that stronger confirmation is present (always, if required).
            double bearRange = m3Rates[1].high - m3Rates[1].low;
            double bearBody  = MathAbs(m3Rates[1].close - m3Rates[1].open);
            bool microWasBullish = haveM3Structure &&
                                   (m3SwHigh.price > m3PrevHigh.price && m3SwLow.price > m3PrevLow.price);
            datetime bearAnchor = m_poiStore[PoiPhys(i)].m3SweepConfirmed ? m_poiStore[PoiPhys(i)].m3SweepTime
                                                             : m_poiStore[PoiPhys(i)].firstTouchTime;
            // Rumus-Teknis Tahap 4B: Bearish CHoCH Close < (pivot low - Buffer), Buffer = 0.05 * ATR(M3, 14)
            double chochBuffer = (atrM3s > 0.0) ? (0.05 * atrM3s) : 0.0;
            bool bearChoCH = (bearAnchor > 0 && m3Rates[1].time >= bearAnchor && microWasBullish &&
                              bearRange > 0.0 && bearBody / bearRange >= 0.55 &&
                              m3Rates[1].close < m3Rates[1].open && m3SwLow.price > 0.0 &&
                              m3Close1 < (m3SwLow.price - chochBuffer) && m3Rates[2].close >= m3SwLow.price);
            if(m_requireM3Sweep && !m_poiStore[PoiPhys(i)].m3SweepConfirmed)
              { RecordReject(REJECT_SWEEP_NOT_CONFIRMED, i); continue; }
            bool isBearReversal = bearChoCH;
            if(!isBearReversal) { RecordReject(REJECT_CHOCH_NOT_CONFIRMED, i); continue; }

            // Causal M3 refinement (supply). Same two sweep concepts as demand:
            //   m3SweepConfirmed  = window sweep for the Tahap-4 gate / score.
            //   obCandleIsSweep   = rates[2] itself swept buy-side liquidity.
            // OB_45 requires displacement FVG (rates[3].low > rates[1].high)
            // AND obCandleIsSweep. Colour of the base is not a gate.
            double refinedEntry = 0.0;
            double refinedWidth = DBL_MAX;
            double refinedOBTop = 0.0, refinedOBBottom = 0.0;
            double refinedFVGTop = 0.0, refinedFVGBottom = 0.0;
            ENUM_SMC_ENTRY_TYPE refinedType = ENTRY_TYPE_OB_45;
            bool haveValidM3OB = false;
            bool haveValidM3FVG = false;
            ENUM_OB_COLOR refinedOBColor = OB_COLOR_UNKNOWN;
            const int ob = 2;
            const double obSweepDepth = (atrM3s > 0.0) ? (0.05 * atrM3s) : point;
            const double obSweepRef = (m3PrevHigh.price > 0.0) ? m3PrevHigh.price : m3SwHigh.price;
            const bool obCandleIsSweep = (copiedM3 > ob && obSweepRef > 0.0 &&
                                          m3Rates[ob].high > obSweepRef + obSweepDepth &&
                                          m3Rates[ob].close < obSweepRef);
            const bool displacementCreatesFVG = (copiedM3 >= 4 && m3Rates[3].low > m3Rates[1].high);
            if(copiedM3 > ob)
            {
               double width = m3Rates[ob].high - m3Rates[ob].low;
               if(width > 0.0 && obCandleIsSweep)  // AUDIT FIX: FVG decoupled from OB_45 gate
                {
                  refinedOBTop = m3Rates[ob].high;
                  refinedOBBottom = m3Rates[ob].low;
                  refinedWidth = width;
                  refinedEntry = (refinedOBTop + refinedOBBottom) * 0.5;
                  refinedType = ENTRY_TYPE_OB_45;
                  refinedOBColor = ClassifyOBColor(false, m3Rates[ob].open, m3Rates[ob].close);
                  haveValidM3OB = true;
                }
            }
            if(displacementCreatesFVG && IsFVGValidWithStructureFromRates(m3Rates, copiedM3, 1, m_ltfPeriod))
            {
               refinedFVGTop = m3Rates[3].low;
               refinedFVGBottom = m3Rates[1].high;
               double width = refinedFVGTop - refinedFVGBottom;
               if(width > 0.0)
               {
                  haveValidM3FVG = true;
                  if(!haveValidM3OB || width < refinedWidth)
                  {
                     refinedWidth = width;
                     refinedEntry = (refinedFVGTop + refinedFVGBottom) * 0.5;
                     refinedType = ENTRY_TYPE_FVG_50;
                  }
               }
            }
            if(!haveValidM3OB && !haveValidM3FVG)
              { RecordReject(REJECT_OB_NO_FVG, i, 24); continue; }
            {
               const double parentTop    = m_poiStore[PoiPhys(i)].top;
               const double parentBottom = m_poiStore[PoiPhys(i)].bottom;
               const double refTop    = (refinedType == ENTRY_TYPE_FVG_50) ? refinedFVGTop    : refinedOBTop;
               const double refBottom = (refinedType == ENTRY_TYPE_FVG_50) ? refinedFVGBottom : refinedOBBottom;
               const double clampTol  = (atrM3s > 0.0) ? (0.05 * atrM3s) : point;
               if(refTop > parentTop + clampTol || refBottom < parentBottom - clampTol)
                 { RecordReject(REJECT_M3_OUTSIDE_PARENT_ZONE, i, 24); continue; }
            }
            if(refinedEntry <= curBid)
              { RecordReject(REJECT_DISTANCE, i, 24); continue; }
            m_poiStore[PoiPhys(i)].visHasM3OB = (refinedOBTop > refinedOBBottom);
            m_poiStore[PoiPhys(i)].visHasM3FVG = (refinedFVGTop > refinedFVGBottom);
            m_poiStore[PoiPhys(i)].visM3OBTop = refinedOBTop;
            m_poiStore[PoiPhys(i)].visM3OBBottom = refinedOBBottom;
            m_poiStore[PoiPhys(i)].visM3FVGTop = refinedFVGTop;
            m_poiStore[PoiPhys(i)].visM3FVGBottom = refinedFVGBottom;
            setupType = refinedType;
            if(m_poiStore[PoiPhys(i)].hasTriggeredLayer[setupType] || m_poiStore[PoiPhys(i)].hasPendingLayer[setupType])
              { RecordReject(REJECT_LAYER_DUPLICATE, i, 24); continue; }

            SMC_Zone refinedBrainZone = m_poiStore[PoiPhys(i)];
            if(refinedType == ENTRY_TYPE_FVG_50 && refinedFVGTop > refinedFVGBottom)
              {
               refinedBrainZone.top = refinedFVGTop;
               refinedBrainZone.bottom = refinedFVGBottom;
              }
            else if(refinedOBTop > refinedOBBottom)
              {
               refinedBrainZone.top = refinedOBTop;
               refinedBrainZone.bottom = refinedOBBottom;
              }
            else if(refinedFVGTop > refinedFVGBottom)
              {
               refinedBrainZone.top = refinedFVGTop;
               refinedBrainZone.bottom = refinedFVGBottom;
              }
            refinedBrainZone.hasFVG = (refinedFVGTop > refinedFVGBottom);
            refinedBrainZone.fvgTop = refinedFVGTop;
            refinedBrainZone.fvgBottom = refinedFVGBottom;
            refinedBrainZone.fvgMidpoint = refinedBrainZone.hasFVG
                                           ? (refinedFVGTop + refinedFVGBottom) * 0.5 : 0.0;
            ClassifyPattern(refinedEntry, refinedBrainZone,
                            poiProfile, obMitigation, fvgMitigation, fibLevel);

            double slBuffer = m_useDynamicSLBuffer ? GetDynamicSLBuffer(m_slBufferPips, m_slATRMult)
                                                   : (m_slBufferPips * pip);
            double bidNow = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            double askNow = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            double executionBuffer = MathMax((double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point,
                                             MathMax(0.0, askNow - bidNow));
            double sl  = refinedBrainZone.top + slBuffer + executionBuffer;
            if(m_useMSNR && m_msnr != NULL)
              {
               double qmlHead = 0.0;
               bool qmlDemand = false;
               if(m_msnr.GetQmlHeadPrice(primaryZone, qmlHead, qmlDemand) && !qmlDemand && qmlHead > 0.0)
                  sl = MathMax(sl, qmlHead + slBuffer + executionBuffer);
              }
            double slP = (sl - refinedEntry) / pip;
            ApplyEngineStopBounds(false, refinedEntry, pip, sl, slP);

            double tp1 = 0.0;
            double tp2 = 0.0;
            if(m_useMSNR && m_msnr != NULL)
              {
               double opp = m_msnr.GetNearestOpposingTarget(refinedEntry, ZONE_SUPPLY);
               if(opp > 0.0 && opp < refinedEntry)
                 {
                  tp2 = opp;
                  double distPips = (refinedEntry - tp2) / pip;
                  if(m_poiPartialPips > 0.0 && distPips > m_poiPartialPips)
                     tp1 = refinedEntry - m_poiPartialPips * pip;
                 }
              }
            if(tp2 <= 0.0 && m_poiPartialPips > 0.0)
               tp1 = refinedEntry - m_poiPartialPips * pip;

            double conf = 88.0;
            SBrainBucketView aiView;
            BrainViewReset(aiView);
            ENUM_SETUP_GRADE grade = EvaluateSetupGrade(primaryZone, true, counterTrend,
                                                       refinedEntry, sl, tp2, ZONE_SUPPLY,
                                                       m_poiStore[PoiPhys(i)].isOTE);
            double gradeMult = SetupGradeLotMultiplier(grade);
            if(SetupGradeRejects(grade) || gradeMult <= 0.0)
              { RecordReject(REJECT_SETUP_GRADE, i, 26); continue; }
            if(m_brain != NULL)
            {
               ENUM_SESSION_TYPE sess = (m_session != NULL) ? m_session.GetCurrentSession() : SESSION_ASIA;
                 int bIdx = m_brain.GetBucketIndex(sess, SIGNAL_SELL,
                                                    MathMax((refinedBrainZone.top - refinedBrainZone.bottom)/pip,
                                                            m_msnr.GetZoneWidthPips(primaryZone)), 100.0 - m_trendBullPct,
                                                  poiProfile, obMitigation, fvgMitigation, fibLevel);
               m_brain.GetBucketView(bIdx, aiView);
               conf = aiView.valid ? aiView.confidence : conf;

               // Apply Quality Boosters (display/logging weight only -- never gates entry)
               if(m_useLiquiditySweepBoost && m_poiStore[PoiPhys(i)].m3SweepConfirmed) conf = MathMin(99.0, conf + 12.0);
               if(m_useOTEBoost && m_poiStore[PoiPhys(i)].isOTE)                       conf = MathMin(99.0, conf + 8.0);

               sig.brainBucketIdx = bIdx;
            }

            double smcScore = 50.0;
            if(m_poiStore[PoiPhys(i)].hasFVG) smcScore += 12.0;
            smcScore += MathMax(0.0, (20.0 - m_poiStore[PoiPhys(i)].barAge)) / 20.0 * 10.0;
            if(m_useLiquiditySweepBoost && m_poiStore[PoiPhys(i)].m3SweepConfirmed) smcScore += 12.0;
            if(m_useOTEBoost && m_poiStore[PoiPhys(i)].isOTE) smcScore += 8.0;

            if(m_useMSNR && m_msnr != NULL)
               smcScore += m_msnr.GetConfluenceBonus(curBid, ZONE_SUPPLY, 15.0, 15.0);
            smcScore = ApplyInstitutionalSoftScore(m_poiStore[PoiPhys(i)], SIGNAL_SELL, smcScore, counterTrend);

            double effRisk = riskPct;
            if(!m_brainExplorationMode)
            {
               effRisk *= gradeMult;
               if(m_useDynamicRisk)
                  effRisk *= BrainRiskOverlayMultiplier(aiView);
               if(m_maxAggregateRiskPct > 0.0 && effRisk > m_maxAggregateRiskPct)
                  effRisk = m_maxAggregateRiskPct;
            }
            // Session lot multipliers are disabled (Asia/EU/NY no longer resize).
            double finalScore = smcScore;
            if(finalScore < GetMinimumSoftScore(counterTrend))
              { RecordReject(counterTrend ? REJECT_DIRECTION_BIAS : REJECT_SOFT_SCORE, i, 6); continue; }

            sig.direction    = SIGNAL_SELL;
            sig.entryType    = setupType;
            sig.poiProfile   = poiProfile;
            sig.obMitigation = obMitigation;
            sig.fvgMitigation= fvgMitigation;
            sig.fibLevel     = fibLevel;
            sig.entryPrice   = NormalisePrice(refinedEntry, m_symbol);
            sig.slPrice      = NormalisePrice(sl, m_symbol);
            sig.slPips       = slP;
            sig.tp1Price     = NormalisePrice(tp1, m_symbol);
            sig.tp2Price     = NormalisePrice(tp2, m_symbol);
            sig.tp1Pips      = (refinedEntry - tp1) / pip;
            sig.tp2Pips      = (refinedEntry - tp2) / pip;
            sig.riskPct      = effRisk;
            sig.setupGrade   = grade;
            sig.gradeLotMult = gradeMult;
            sig.lotSize      = useRiskPct ? m_rc.CalcLotSize(effRisk, slP, m_symbol,
                                                               refinedEntry, ORDER_TYPE_SELL)
                                            : m_rc.RoundLotToStep(fixedLot);
            if(useRiskPct && m_diagnostics != NULL)
              {
               if(m_rc.LastLotStatus() == LOT_STATUS_CLAMP) m_diagnostics.RecordLotClamp();
               else if(m_rc.LastLotStatus() == LOT_STATUS_FALLBACK) m_diagnostics.RecordLotFallback();
              }
            sig.lotSize      = EnforceBrokerMinLot(sig.lotSize > 0.0 ? sig.lotSize : YANSTD_HARD_MIN_LOT, m_symbol);
            sig.zoneIndex    = i;
            sig.signalTime   = TimeCurrent();
            sig.aiConfidence = conf;
            sig.qualityScore = finalScore;
            sig.refinedOBTop = refinedOBTop;
            sig.refinedOBBottom = refinedOBBottom;
            sig.refinedFVGTop = refinedFVGTop;
            sig.refinedFVGBottom = refinedFVGBottom;
            sig.fiboSwingHigh = m_poiStore[PoiPhys(i)].fiboSwingHigh;
            sig.fiboSwingLow = m_poiStore[PoiPhys(i)].fiboSwingLow;
            // Provenance only (chart/attribution): parent OB colour from the M5
            // zone, execution OB colour from the M3 refinement candle.
            sig.parentOBColor = m_poiStore[PoiPhys(i)].parentOBColor;
            sig.executionOBColor = refinedOBColor;
            sig.isValid      = true;
            sig.invalidReason = counterTrend ? "Counter-bias scalp: strict score passed" : "Best SMC candidate";
            if(finalScore > bestScore) { bestScore = finalScore; bestSig = sig; }
            continue;
         }
      }

      return bestSig;
   }

};

#endif // YANSTD_SIGNALENGINE_MQH
