//+------------------------------------------------------------------+
//|                                                 OrderManager.mqh |
//|                   YANSTD EA — Order Execution & Management       |
//|                                    v2.4  |  2026-09-03           |
//+------------------------------------------------------------------+
#ifndef YANSTD_ORDERMANAGER_MQH
#define YANSTD_ORDERMANAGER_MQH
#include "Defines.mqh"
#include "SignalDiagnostics.mqh"
#include <Trade/Trade.mqh>

#define YANSTD_CLOSE_ESCALATE_SECONDS 5

// Lifecycle of a managed close request. Once a close has been asked for, the
// EA must stop asking on every tick and wait for the trade transaction to
// confirm it; re-issuing is what produced 4,290 journal lines for 154 tickets.
enum ENUM_CLOSE_STATE
  {
   CLOSE_NONE = 0,        // no close requested
   CLOSE_PENDING = 1,     // requested, awaiting DEAL_ENTRY_OUT
   CLOSE_ESCALATED = 2,   // retried as a market order after the deadline
   CLOSE_UNMANAGED = 3    // gave up; position is running without EA protection
  };

struct SCloseRequest
  {
   ulong              ticket;
   ENUM_CLOSE_STATE   state;
   datetime           firstRequest;
   bool               logged;
  };

struct SPosTrack
{
   ulong    ticket;
   double   tp1Level;
   double   tp2Level;
   double   initialLots;
   double   openPrice;
   int      posType;
   double   initialRiskPrice;
   double   initialRiskMoney;
   double   maxFavorableR;
   double   maxAdverseR;
   double   maxSpreadPoints;
   datetime lastSeenTime;
   double   tp1CloseLots;
   double   tp2CloseLots;
   double   runnerLots;
   bool     scaleOutEnabled;
   bool     tp1Done;
   bool     bepDone;
   bool     milestoneDone; // Stage 2b milestone state persists across ticks
   bool     tp2Done;
   datetime tp2Time;
   bool     trailActive;
   int      brainBucketIdx;
   ulong    setupEventId;
   double   brainEvidenceWeight;
   double   serverTP;
   int      targetSource;
   bool     needsTargetRecovery;
   int      entryVariant;
   int      setupGrade;
};

class COrderManager
{
private:
   CTrade     m_trade;
   ulong      m_magic;
   int        m_slippage;
   SPosTrack  m_tracks[];
   int        m_trackCount;
   string     m_trackFile;
   double     m_defaultTP1RR;
   double     m_defaultTP2RR;
   double     m_defaultTP1ClosePct;
   double     m_defaultTP2ClosePct;
   double     m_minScaleOutInitialLots;
   bool       m_autoRoundExitLots;
   double     m_marginBufferPct;      // Fix R1: required free-margin safety cushion (%)
   int        m_maxRetryAttempts;     // Fix backlog#3: extra attempts after the first send (0 = no retry)
   int        m_retryDelayMs;         // Fix backlog#3: delay between retry attempts
   datetime   m_marketClosedUntil;    // suppress repeated requests after broker retcode 10018

   // H3: in-flight close requests, so a close is asked for once per ticket
   // and escalated on a deadline instead of being re-sent every tick.
   SCloseRequest m_closeReqs[];
   int           m_closeReqCount;

   CSignalDiagnostics *m_diag;        // H1/H3/H4/H7 integrity counters
   bool       m_lastRejectWasEntryStopsTooClose; // flag to distinguish pre-send guard from broker failure

   ulong      m_posCacheTickets[];
   int        m_posCacheCount;
   int        m_posCacheRawTotal;     // PositionsTotal() at last cache build; -1 = never built
   void       RebuildPositionCache();
   // AUDIT FIX: shared fill logic keyed by ticket identity (not cache index),
   // so callers that snapshot tickets up front are immune to the cache being
   // rebuilt/reordered mid-loop when a position closes between calls.
   bool       FillPositionByTicket(ulong ticket, SPositionInfo &info);

   bool IsTradeSessionOpen(string symbol)
   {
      datetime serverNow = TimeTradeServer();
      if(serverNow <= 0) serverNow = TimeCurrent();
      MqlDateTime nowParts;
      TimeToStruct(serverNow, nowParts);
      int nowSeconds = nowParts.hour * 3600 + nowParts.min * 60 + nowParts.sec;
      bool sessionMetadataFound = false;
      for(uint index = 0; index < 24; index++)
      {
         datetime fromTime = 0, toTime = 0;
         if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)nowParts.day_of_week,
                                    index, fromTime, toTime)) break;
         sessionMetadataFound = true;
         MqlDateTime fromParts, toParts;
         TimeToStruct(fromTime, fromParts);
         TimeToStruct(toTime, toParts);
         int fromSeconds = fromParts.hour * 3600 + fromParts.min * 60 + fromParts.sec;
         int toSeconds   = toParts.hour * 3600 + toParts.min * 60 + toParts.sec;
         if(fromSeconds == toSeconds) return true; // broker denotes a 24-hour session
         if(fromSeconds < toSeconds && nowSeconds >= fromSeconds && nowSeconds < toSeconds) return true;
         if(fromSeconds > toSeconds && (nowSeconds >= fromSeconds || nowSeconds < toSeconds)) return true;
      }
      // Missing metadata is not proof of a closed market. Let the trade server
      // decide in that case; only an explicit out-of-session result blocks here.
      return !sessionMetadataFound;
   }

   bool CanSendTradeRequest(string symbol)
   {
      datetime now = TimeCurrent();
      if(m_marketClosedUntil > now) return false;
      return IsTradeSessionOpen(symbol);
   }

   void RegisterTradeFailure(uint retcode)
   {
      if(retcode == TRADE_RETCODE_MARKET_CLOSED)
         m_marketClosedUntil = MathMax(m_marketClosedUntil, TimeCurrent() + 60);
   }

   bool EnsureTrackCapacity(int required)
     {
      if(required <= ArraySize(m_tracks)) return true;
      int current = ArraySize(m_tracks);
      int target = MathMax(required, MathMax(64, current * 2));
      return (ArrayResize(m_tracks, target, 64) >= required);
     }

   //+------------------------------------------------------------------+
   //| H3 — close-request bookkeeping                                    |
   //+------------------------------------------------------------------+
   int  FindCloseReq(ulong ticket)
     {
      for(int i = 0; i < m_closeReqCount; i++)
         if(m_closeReqs[i].ticket == ticket) return i;
      return -1;
     }

   void BeginCloseRequest(ulong ticket)
     {
      int idx = FindCloseReq(ticket);
      if(idx >= 0) return;                        // already tracked
      if(ArrayResize(m_closeReqs, m_closeReqCount + 1, 32) < m_closeReqCount + 1) return;
      m_closeReqs[m_closeReqCount].ticket       = ticket;
      m_closeReqs[m_closeReqCount].state        = CLOSE_PENDING;
      m_closeReqs[m_closeReqCount].firstRequest = TimeCurrent();
      m_closeReqs[m_closeReqCount].logged       = false;
      m_closeReqCount++;
     }

   void EndCloseRequest(ulong ticket)
     {
      for(int i = m_closeReqCount - 1; i >= 0; i--)
        {
         if(m_closeReqs[i].ticket != ticket) continue;
         for(int j = i; j < m_closeReqCount - 1; j++) m_closeReqs[j] = m_closeReqs[j+1];
         m_closeReqCount--;
         return;
        }
     }

   void PurgeCloseRequests()
     {
      for(int i = m_closeReqCount - 1; i >= 0; i--)
         if(!PositionSelectByTicket(m_closeReqs[i].ticket)) EndCloseRequest(m_closeReqs[i].ticket);
     }

   // H4: can this initial volume be split 50/25/25 in broker-legal steps?
   // Exposed as a predicate so the ENTRY gate can refuse to open a position
   // it will never be able to scale out of, instead of discovering it at TP1
   // and silently downgrading the whole exit plan to "close everything".
   bool CanScaleOut(string symbol, double initialLots, double tp1Pct, double tp2Pct)
     {
      double tp1Lots = 0.0, tp2Lots = 0.0, runnerLots = 0.0;
      bool enabled = false;
      BuildScaleOutPlan(symbol, initialLots, tp1Pct, tp2Pct, tp1Lots, tp2Lots, runnerLots, enabled);
      return enabled;
     }

   double FloorVolumeToStep(double volume, string symbol)
   {
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) return 0.0;
      return NormalizeDouble(MathFloor((volume + 1e-12) / step) * step, 8);
   }

   bool CheckMarginSafety(ENUM_ORDER_TYPE orderType, double lots, double price, string &failReason)
   {
      if(lots <= 0.0) { failReason = "invalid lot size"; return false; }
      if(price <= 0.0)
         price = (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT ||
                  orderType == ORDER_TYPE_BUY_STOP)
                 ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                 : SymbolInfoDouble(Symbol(), SYMBOL_BID);

      double requiredMargin = 0.0;
      if(!OrderCalcMargin(orderType, Symbol(), lots, price, requiredMargin))
      {
         // Broker/terminal could not compute margin (e.g. symbol not fully
         // synced yet). Fail safe: block the trade rather than assume it's OK.
         failReason = StringFormat("OrderCalcMargin failed, error=%d", GetLastError());
         return false;
      }

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double bufferMult = 1.0 + MathMax(0.0, m_marginBufferPct) / 100.0;
      double requiredWithBuffer = requiredMargin * bufferMult;

      if(requiredWithBuffer > freeMargin)
      {
         failReason = StringFormat("insufficient margin: need %.2f (incl. %.0f%% buffer), free=%.2f",
                                    requiredWithBuffer, m_marginBufferPct, freeMargin);
         return false;
      }
      return true;
   }

   double CalcInitialRiskMoney(string symbol, double riskPrice, double lots)
   {
      if(riskPrice <= 0.0 || lots <= 0.0) return 0.0;
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValue <= 0.0)
         tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;
      return (riskPrice / tickSize) * tickValue * lots;
   }

   void BuildScaleOutPlan(string symbol, double initialLots,
                          double tp1Pct, double tp2Pct,
                          double &tp1Lots, double &tp2Lots,
                          double &runnerLots, bool &enabled)
   {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      initialLots   = NormalizeDouble(initialLots, 8);
      double rawTP1 = initialLots * tp1Pct / 100.0;
      double rawTP2 = initialLots * tp2Pct / 100.0;
      tp1Lots       = FloorVolumeToStep(rawTP1, symbol);
      tp2Lots       = FloorVolumeToStep(rawTP2, symbol);
      runnerLots    = NormalizeDouble(initialLots - tp1Lots - tp2Lots, 8);

      enabled = (initialLots + 1e-12 >= m_minScaleOutInitialLots &&
                 minLot > 0.0 && step > 0.0 && tp1Pct > 0.0 && tp2Pct > 0.0 &&
                 tp1Pct + tp2Pct < 100.0 &&
                 tp1Lots >= minLot && tp2Lots >= minLot && runnerLots >= minLot &&
                 MathAbs(runnerLots - FloorVolumeToStep(runnerLots, symbol)) <= step * 1e-6);
      if(!m_autoRoundExitLots &&
         (MathAbs(rawTP1 - tp1Lots) > step * 1e-6 || MathAbs(rawTP2 - tp2Lots) > step * 1e-6))
         enabled = false;

      if(!enabled)
      {
         tp1Lots    = initialLots;
         tp2Lots    = 0.0;
         runnerLots = 0.0;
      }
   }

   void SaveTracks()
   {
      if(MQLInfoInteger(MQL_TESTER) || m_trackFile == "") return;
      int handle = FileOpen(m_trackFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE) return;
      FileWriteInteger(handle, 502);
      FileWriteInteger(handle, m_trackCount);
      if(m_trackCount > 0) FileWriteArray(handle, m_tracks, 0, m_trackCount);
      FileClose(handle);
   }

   void LoadTracks()
   {
      m_trackCount = 0;
      if(MQLInfoInteger(MQL_TESTER) || m_trackFile == "") return;
      int handle = FileOpen(m_trackFile, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE) return;
      int version = FileReadInteger(handle);
      int count   = FileReadInteger(handle);
       if(version == 502 && count >= 0 && count <= 100000 && EnsureTrackCapacity(count))
      {
         if(count == 0 || FileReadArray(handle, m_tracks, 0, count) == (uint)count)
            m_trackCount = count;
      }
      FileClose(handle);
   }

    bool HasMatchingPosition(const string comment)
    {
       for(int i = PositionsTotal() - 1; i >= 0; i--)
       {
          ulong ticket = PositionGetTicket(i);
          if(ticket > 0 && (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic &&
             PositionGetString(POSITION_SYMBOL) == Symbol() &&
             PositionGetString(POSITION_COMMENT) == comment)
             return true;
       }
       return false;
    }

    bool HasMatchingPending(const string comment)
    {
       for(int i = OrdersTotal() - 1; i >= 0; i--)
       {
          ulong ticket = OrderGetTicket(i);
          if(ticket > 0 && (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic &&
             OrderGetString(ORDER_SYMBOL) == Symbol() &&
             OrderGetString(ORDER_COMMENT) == comment)
             return true;
       }
       return false;
    }

    bool TradeResultOK(bool allowPlaced = false)
    {
       uint code = m_trade.ResultRetcode();
       return (code == TRADE_RETCODE_DONE || (allowPlaced && code == TRADE_RETCODE_PLACED) ||
               code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_NO_CHANGES);
    }

   void RetryBackoff(int attemptIndex)
   {
      if(m_retryDelayMs <= 0) return;
      if(MQLInfoInteger(MQL_TESTER)) return;
      Sleep(m_retryDelayMs * (attemptIndex + 1));
   }

   ENUM_ORDER_TYPE_FILLING PendingFillingMode()
   {
      long exeMode = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_EXEMODE);
      if(exeMode == SYMBOL_TRADE_EXECUTION_MARKET || exeMode == SYMBOL_TRADE_EXECUTION_EXCHANGE)
         return ORDER_FILLING_RETURN;
      long fill = SymbolInfoInteger(Symbol(), SYMBOL_FILLING_MODE);
      if((fill & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
      if((fill & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   double NormalizeToTick(double price)
   {
      if(price == 0.0) return 0.0;
      double tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
      int digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
      if(tick <= 0.0) return NormalizeDouble(price, digits);
      return NormalizeDouble(MathRound(price / tick) * tick, digits);
   }

   // AUDIT H4: broker min distance for a NEW entry. Do not silently pull SL/TP
   // closer-to-price here — that would change risk% without recomputing lot.
   double BrokerMinEntryStopDistance()
   {
      const string sym = Symbol();
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      double spread = SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID);
      double stops  = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double freeze = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
      if(point <= 0.0) point = _Point;
      if(spread < 0.0) spread = 0.0;
      return MathMax(stops, freeze) * point + spread;
   }

   bool RejectIfEntryStopsTooClose(const string tag, const bool isBuy,
                                   const double price, const double sl, const double tp)
   {
      m_lastRejectWasEntryStopsTooClose = false;
      if(price <= 0.0) return false;
      const double minDist = BrokerMinEntryStopDistance();
      if(sl > 0.0)
        {
         const double slDist = isBuy ? (price - sl) : (sl - price);
         if(slDist < minDist)
           {
            m_lastRejectWasEntryStopsTooClose = true;
            if(m_diag != NULL) m_diag.Record(REJECT_ENTRY_STOPS_DISTANCE, (long)TimeCurrent());
            LogSystemWarning("OrderManager", tag,
                             StringFormat("Rejected: SL closer than Stops/Freeze+spread | price=%.5f sl=%.5f dist=%.5f min=%.5f",
                                          price, sl, slDist, minDist));
            return true;
           }
        }
      if(tp > 0.0)
        {
         const double tpDist = isBuy ? (tp - price) : (price - tp);
         if(tpDist < minDist)
           {
            m_lastRejectWasEntryStopsTooClose = true;
            if(m_diag != NULL) m_diag.Record(REJECT_ENTRY_STOPS_DISTANCE, (long)TimeCurrent());
            LogSystemWarning("OrderManager", tag,
                             StringFormat("Rejected: TP closer than Stops/Freeze+spread | price=%.5f tp=%.5f dist=%.5f min=%.5f",
                                          price, tp, tpDist, minDist));
            return true;
           }
        }
      return false;
   }

public:
   void    SetDiagnostics(CSignalDiagnostics *diag) { m_diag = diag; }
   bool    LastRejectWasEntryStopsTooClose() const { return m_lastRejectWasEntryStopsTooClose; }

   void    Init(ulong magic, int slippage, double defaultTP1RR = 1.5, double defaultTP2RR = 2.0,
                double defaultTP1ClosePct = 50.0, double defaultTP2ClosePct = 25.0,
                bool autoRoundExitLots = true, double minScaleOutInitialLots = 0.08,
                double marginBufferPct = 20.0, int maxRetryAttempts = 2, int retryDelayMs = 250);
   bool    OpenBuy(double lots, double sl, double tp, string comment = "");
   bool    OpenSell(double lots, double sl, double tp, string comment = "");
   bool    PlaceBuyLimit(double price, double lots, double sl, double tp, string comment = "", datetime expiration = 0);
   bool    PlaceSellLimit(double price, double lots, double sl, double tp, string comment = "", datetime expiration = 0);
   bool    ModifySL(ulong ticket, double newSL);
   bool    SafeModifySL(ulong ticket, double newSL, double currentTP, int posType);
   bool    PartialClose(ulong ticket, double lots);
   bool    ClosePosition(ulong ticket);
   // H3: managed close. Returns false immediately when a close is already in
   // flight for this ticket, so callers in a per-tick loop cannot re-issue it.
   bool    RequestManagedClose(ulong ticket, string reason);
   void    AuditCloseRequests();
   bool    CloseAllByMagic();
   bool    DeleteAllPendingByMagic();
   bool    DeletePendingByType(ENUM_ORDER_TYPE type);
   bool    DeletePendingTicket(ulong ticket);
   bool    HasOpenPosition();
   int     CountOpenPositions();
   int     CountPendingOrders();
   bool    GetPosition(int index, SPositionInfo &info);
   // AUDIT FIX: ticket-stable variant. Use this from any loop that snapshots
   // tickets first, so a position closing mid-loop cannot cause another
   // not-yet-processed position to be skipped or reprocessed under a stale index.
   bool    GetPositionByTicket(ulong ticket, SPositionInfo &info);
   void    RegisterNewTrack(ulong ticket, double tp1Level, double tp2Level, int brainBucketIdx,
                              double tp1ClosePct = 50.0, double tp2ClosePct = 25.0,
                              ulong setupEventId = 0, double brainEvidenceWeight = 1.0,
                              double serverTP = 0.0, ENUM_TARGET_SOURCE targetSource = TARGET_NONE,
                              bool reconstructed = false);
   bool    ApplyServerTP(ulong ticket, double newTP);
   bool    UpdateTrackTarget(ulong ticket, double serverTP, double tp1Level,
                             ENUM_TARGET_SOURCE source);
   bool    RecalcTrackFromFill(ulong ticket, double fillPrice, double slPrice);
   int     TrackCount() const { return m_trackCount; }
   bool    GetTrackTicket(const int index, ulong &ticket) const;
   bool    TrackNeedsTargetRecovery(ulong ticket) const;
   ENUM_TARGET_SOURCE GetTrackTargetSource(ulong ticket) const;
   double  GetTrackServerTP(ulong ticket) const;
   bool    IsTracked(ulong ticket);
   bool    IsTrackTP1Done(ulong ticket);
   int     GetTrackBrainBucket(ulong ticket);
   ulong   GetTrackSetupEventId(ulong ticket);
   double  GetTrackBrainEvidenceWeight(ulong ticket);
   void    SetTrackAttribution(ulong ticket, int variant, int grade);
   bool    GetTrackAttribution(ulong ticket, int &variant, int &grade) const;
   bool    GetTrackLearningState(ulong ticket, double &openPrice, int &posType,
                                 double &initialLots, double &initialRiskPrice, double &initialRiskMoney,
                                 double &maxFavorableR, double &maxAdverseR, double &maxSpreadPoints);
   void    UpdateTrackExcursion(ulong ticket, double maxFavorableR, double maxAdverseR, double maxSpreadPoints);
   void    UpdateTrackState(const SPositionInfo &pos);
   void    MarkProtectivePartial(ulong ticket);
   void    RemoveTrack(ulong ticket);
   void    PurgeStaleTracks(); // Remove tracks for positions that no longer exist
   double  GetTotalFloatingPnL();
   // H4: entry-gate predicate — refuse a lot size that cannot be scaled out.
   bool    CanScaleOut(double initialLots, double tp1Pct, double tp2Pct, string symbol = NULL);
};

bool COrderManager::IsTracked(ulong ticket)
{
   if(ticket <= 0) return false;
   for(int k = 0; k < m_trackCount; k++)
      if(m_tracks[k].ticket == ticket) return true;
   return false;
}

bool COrderManager::IsTrackTP1Done(ulong ticket)
{
   if(ticket <= 0) return false;
   for(int k = 0; k < m_trackCount; k++)
      if(m_tracks[k].ticket == ticket) return m_tracks[k].tp1Done;
   return false;
}

//+------------------------------------------------------------------+
void COrderManager::Init(ulong magic, int slippage, double defaultTP1RR, double defaultTP2RR,
                         double defaultTP1ClosePct, double defaultTP2ClosePct,
                         bool autoRoundExitLots, double minScaleOutInitialLots,
                         double marginBufferPct, int maxRetryAttempts, int retryDelayMs)
{
   m_magic      = magic;
   m_slippage   = slippage;
   m_defaultTP1RR = defaultTP1RR;
   m_defaultTP2RR = defaultTP2RR;
   m_defaultTP1ClosePct = defaultTP1ClosePct;
   m_defaultTP2ClosePct = defaultTP2ClosePct;
   m_autoRoundExitLots  = autoRoundExitLots;
   m_minScaleOutInitialLots = minScaleOutInitialLots;
   m_marginBufferPct   = MathMax(0.0, marginBufferPct);
   m_maxRetryAttempts  = (int)MathMax(0.0, (double)maxRetryAttempts); // Fix backlog#3
   m_retryDelayMs      = (int)MathMax(0.0, (double)retryDelayMs);     // Fix backlog#3
   m_marketClosedUntil = 0;
   m_trackCount        = 0;
   m_closeReqCount     = 0;   // H3
   m_lastRejectWasEntryStopsTooClose = false;
   m_diag              = NULL; // H1/H3/H4/H7 counters wired by SetDiagnostics()
   m_posCacheCount     = 0;
   m_posCacheRawTotal  = -1;  // Sentinel forces the first GetPosition() call to build the cache
   ArrayResize(m_closeReqs, 32);
   ArrayResize(m_tracks, 0);
   ArrayResize(m_tracks, 64, 64);
   string server = AccountInfoString(ACCOUNT_SERVER);
   StringReplace(server, "/", "_");
   StringReplace(server, "\\", "_");
   StringReplace(server, ":", "_");
   m_trackFile  = "YANSTD_PosTrack_" + server + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                  "_" + Symbol() + "_" + IntegerToString((long)m_magic) + ".bin";
   StringReplace(m_trackFile, "/", "_");
   StringReplace(m_trackFile, "\\", "_");
    LoadTracks();
    // If an older track-file layout was intentionally ignored, reconstruct
    // management state from any still-open EA positions instead of leaving
    // them without TP/runner protection after an upgrade/restart.
    for(int p = 0; p < PositionsTotal(); p++)
      {
       ulong ticket = PositionGetTicket(p);
       if(ticket == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic ||
          PositionGetString(POSITION_SYMBOL) != Symbol() || IsTracked(ticket)) continue;
       string comment = PositionGetString(POSITION_COMMENT);
       int bucket = -1;
       ulong eventId = 0;
       int bPos = StringFind(comment, "_B");
       if(bPos < 0) bPos = StringFind(comment, "SMC_B");
       if(bPos >= 0)
         {
          int bStart = (StringFind(comment, "SMC_B") == bPos) ? bPos + 5 : bPos + 2;
          bucket = DecodeBase36Signed(comment, bStart);
         }
       int ePos = StringFind(comment, "_E");
       if(ePos >= 0) eventId = DecodeBase36(comment, ePos + 2);
       // Restart fallback: the exact event sibling count lives in YANSTD while
       // the tester is running. A reconstructed matrix track uses the current
       // maximum candidate count rather than the obsolete nine ID slots.
       double evidenceWeight = (StringFind(comment, "_M") >= 0)
                               ? 1.0 / (double)MATRIX_MAX_CANDIDATE_COUNT : 1.0;
       RegisterNewTrack(ticket, 0.0, 0.0, bucket,
                        m_defaultTP1ClosePct, m_defaultTP2ClosePct, eventId, evidenceWeight,
                        0.0, TARGET_NONE, true);
      }
    m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(m_slippage);
   
   m_trade.SetTypeFillingBySymbol(Symbol());
}

//+------------------------------------------------------------------+
bool COrderManager::OpenBuy(double lots, double sl, double tp, string comment)
{
   lots = EnforceBrokerMinLot(lots, Symbol());
   if(lots <= 0.0) return false;
   if(!CanSendTradeRequest(Symbol())) return false;

   double askNow = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   if(sl > 0.0 && sl >= askNow)
     {
      LogSystemWarning("OrderManager", "OpenBuy", "Rejected: SL on wrong side of price");
      return false;
     }
   if(tp > 0.0 && tp <= askNow)
     {
      LogSystemWarning("OrderManager", "OpenBuy", "Rejected: TP on wrong side of price");
      return false;
     }
   if(RejectIfEntryStopsTooClose("OpenBuy", true, askNow, sl, tp))
      return false;

   double nsl = NormalizeToTick(sl);
   double ntp = NormalizeToTick(tp);
   m_trade.SetTypeFillingBySymbol(Symbol());

   bool res = false;
   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

      string marginFail;
      if(!CheckMarginSafety(ORDER_TYPE_BUY, lots, ask, marginFail))
      {
         LogSystemWarning("OrderManager", "OpenBuy", "Blocked — " + marginFail);
         return false;
      }

      bool sent = m_trade.Buy(lots, Symbol(), ask, nsl, ntp, comment);
      res = sent && TradeResultOK();
      if(res) break;

      uint code = m_trade.ResultRetcode();
      if(code == TRADE_RETCODE_PLACED && HasMatchingPosition(comment)) { res = true; break; }
      if(code == TRADE_RETCODE_TIMEOUT)
      {
         if(HasMatchingPosition(comment)) res = true;
         else LogSystemWarning("OrderManager", "OpenBuy", "Timeout outcome unknown; request is not retried to prevent duplicate exposure");
         break;
      }
      RegisterTradeFailure(code);
      LogTradeError("OpenBuy", 0, code, m_trade.ResultComment(),
                    StringFormat("Lot: %.2f, Ask: %.2f, SL: %.2f, attempt: %d/%d",
                                 lots, ask, nsl, attempt + 1, m_maxRetryAttempts + 1));
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      RetryBackoff(attempt);
   }
   return res;
}

//+------------------------------------------------------------------+
bool COrderManager::OpenSell(double lots, double sl, double tp, string comment)
{
   lots = EnforceBrokerMinLot(lots, Symbol());
   if(lots <= 0.0) return false;
   if(!CanSendTradeRequest(Symbol())) return false;

   double bidNow = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(sl > 0.0 && sl <= bidNow)
     {
      LogSystemWarning("OrderManager", "OpenSell", "Rejected: SL on wrong side of price");
      return false;
     }
   if(tp > 0.0 && tp >= bidNow)
     {
      LogSystemWarning("OrderManager", "OpenSell", "Rejected: TP on wrong side of price");
      return false;
     }
   if(RejectIfEntryStopsTooClose("OpenSell", false, bidNow, sl, tp))
      return false;

   double nsl = NormalizeToTick(sl);
   double ntp = NormalizeToTick(tp);
   m_trade.SetTypeFillingBySymbol(Symbol());

   bool res = false;
   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

      string marginFail;
      if(!CheckMarginSafety(ORDER_TYPE_SELL, lots, bid, marginFail))
      {
         LogSystemWarning("OrderManager", "OpenSell", "Blocked — " + marginFail);
         return false;
      }

      bool sent = m_trade.Sell(lots, Symbol(), bid, nsl, ntp, comment);
      res = sent && TradeResultOK();
      if(res) break;

      uint code = m_trade.ResultRetcode();
      if(code == TRADE_RETCODE_PLACED && HasMatchingPosition(comment)) { res = true; break; }
      if(code == TRADE_RETCODE_TIMEOUT)
      {
         if(HasMatchingPosition(comment)) res = true;
         else LogSystemWarning("OrderManager", "OpenSell", "Timeout outcome unknown; request is not retried to prevent duplicate exposure");
         break;
      }
      RegisterTradeFailure(code);
      LogTradeError("OpenSell", 0, code, m_trade.ResultComment(),
                    StringFormat("Lot: %.2f, Bid: %.2f, SL: %.2f, attempt: %d/%d",
                                 lots, bid, nsl, attempt + 1, m_maxRetryAttempts + 1));
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      RetryBackoff(attempt);
   }
   return res;
}

//+------------------------------------------------------------------+
bool COrderManager::PlaceBuyLimit(double price, double lots, double sl, double tp, string comment, datetime expiration)
{
   lots = EnforceBrokerMinLot(lots, Symbol());
   if(lots <= 0.0) return false;
   if(!CanSendTradeRequest(Symbol())) return false;
   double np   = NormalizeToTick(price);
   double nsl  = NormalizeToTick(sl);
   double ntp  = NormalizeToTick(tp);
   if(RejectIfEntryStopsTooClose("PlaceBuyLimit", true, np, nsl, ntp))
      return false;

   string marginFail;
   if(!CheckMarginSafety(ORDER_TYPE_BUY_LIMIT, lots, np, marginFail))
   {
      LogSystemWarning("OrderManager", "PlaceBuyLimit", "Blocked — " + marginFail);
      return false;
   }

   // Check broker capability for ORDER_TIME_SPECIFIED
   ENUM_ORDER_TYPE_TIME typeTime = ORDER_TIME_GTC;
   datetime exp = 0;
   if(expiration > 0)
   {
      long expFlags = SymbolInfoInteger(Symbol(), SYMBOL_EXPIRATION_MODE);
      if((expFlags & SYMBOL_EXPIRATION_SPECIFIED) != 0)
      {
         typeTime = ORDER_TIME_SPECIFIED;
         exp = expiration;
      }
      else
      {
         LogSystemWarning("OrderManager", "PlaceBuyLimit", "Broker does not support specified expiration; unsafe GTC fallback rejected");
         return false;
      }
   }
   m_trade.SetTypeFilling(PendingFillingMode()); // Use the symbol's supported pending-order filling mode

   bool res = false;
   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      bool sent = m_trade.BuyLimit(lots, np, Symbol(), nsl, ntp, typeTime, exp, comment);
      res = sent && TradeResultOK(true);
      if(res) break;

      uint code = m_trade.ResultRetcode();
      if(code == TRADE_RETCODE_TIMEOUT)
      {
         if(HasMatchingPending(comment) || HasMatchingPosition(comment)) res = true;
         else LogSystemWarning("OrderManager", "PlaceBuyLimit", "Timeout outcome unknown; request is not retried to prevent duplicate pending orders");
         break;
      }
      RegisterTradeFailure(code);
      LogTradeError("PlaceBuyLimit", 0, code, m_trade.ResultComment(),
                    StringFormat("Price: %.2f, Lot: %.2f, SL: %.2f, attempt: %d/%d",
                                 np, lots, nsl, attempt + 1, m_maxRetryAttempts + 1));
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      RetryBackoff(attempt);
   }
   m_trade.SetTypeFillingBySymbol(Symbol());
   return res;
}

//+------------------------------------------------------------------+
bool COrderManager::PlaceSellLimit(double price, double lots, double sl, double tp, string comment, datetime expiration)
{
   lots = EnforceBrokerMinLot(lots, Symbol());
   if(lots <= 0.0) return false;
   if(!CanSendTradeRequest(Symbol())) return false;
   double np   = NormalizeToTick(price);
   double nsl  = NormalizeToTick(sl);
   double ntp  = NormalizeToTick(tp);
   if(RejectIfEntryStopsTooClose("PlaceSellLimit", false, np, nsl, ntp))
      return false;

   string marginFail;
   if(!CheckMarginSafety(ORDER_TYPE_SELL_LIMIT, lots, np, marginFail))
   {
      LogSystemWarning("OrderManager", "PlaceSellLimit", "Blocked — " + marginFail);
      return false;
   }

   // Check broker capability for ORDER_TIME_SPECIFIED
   ENUM_ORDER_TYPE_TIME typeTime = ORDER_TIME_GTC;
   datetime exp = 0;
   if(expiration > 0)
   {
      long expFlags = SymbolInfoInteger(Symbol(), SYMBOL_EXPIRATION_MODE);
      if((expFlags & SYMBOL_EXPIRATION_SPECIFIED) != 0)
      {
         typeTime = ORDER_TIME_SPECIFIED;
         exp = expiration;
      }
      else
      {
         LogSystemWarning("OrderManager", "PlaceSellLimit", "Broker does not support specified expiration; unsafe GTC fallback rejected");
         return false;
      }
   }
   m_trade.SetTypeFilling(PendingFillingMode()); // Use the symbol's supported pending-order filling mode

   bool res = false;
   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      bool sent = m_trade.SellLimit(lots, np, Symbol(), nsl, ntp, typeTime, exp, comment);
      res = sent && TradeResultOK(true);
      if(res) break;

      uint code = m_trade.ResultRetcode();
      if(code == TRADE_RETCODE_TIMEOUT)
      {
         if(HasMatchingPending(comment) || HasMatchingPosition(comment)) res = true;
         else LogSystemWarning("OrderManager", "PlaceSellLimit", "Timeout outcome unknown; request is not retried to prevent duplicate pending orders");
         break;
      }
      RegisterTradeFailure(code);
      LogTradeError("PlaceSellLimit", 0, code, m_trade.ResultComment(),
                    StringFormat("Price: %.2f, Lot: %.2f, SL: %.2f, attempt: %d/%d",
                                 np, lots, nsl, attempt + 1, m_maxRetryAttempts + 1));
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      RetryBackoff(attempt);
   }
   m_trade.SetTypeFillingBySymbol(Symbol());
   return res;
}

//+------------------------------------------------------------------+
bool COrderManager::ModifySL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double currentTP  = PositionGetDouble(POSITION_TP);
   int    posType    = (int)PositionGetInteger(POSITION_TYPE);
   return SafeModifySL(ticket, newSL, currentTP, posType);
}

//+------------------------------------------------------------------+
bool COrderManager::SafeModifySL(ulong ticket, double newSL,
                                    double currentTP, int posType)
{
   if(!PositionSelectByTicket(ticket)) return false;
   string posSymbol = PositionGetString(POSITION_SYMBOL);
   double existingSL = PositionGetDouble(POSITION_SL);
   if(!CanSendTradeRequest(posSymbol)) return false;

   double point  = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
   double tick   = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_SIZE);
   int    digits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
   if(tick <= 0.0) tick = point;

   if(currentTP > 0.0)
     {
      bool crossesTP = (posType == POSITION_TYPE_BUY)  ? (newSL >= currentTP)
                                                       : (newSL <= currentTP);
      if(crossesTP)
         newSL = (posType == POSITION_TYPE_BUY) ? currentTP - tick : currentTP + tick;
     }
   double stopsLvl   = (double)SymbolInfoInteger(posSymbol, SYMBOL_TRADE_STOPS_LEVEL);
   double freezeLvl  = (double)SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double spread     = SymbolInfoDouble(posSymbol, SYMBOL_ASK) - SymbolInfoDouble(posSymbol, SYMBOL_BID);
   double safeBuffer = MathMax(stopsLvl, freezeLvl) * point + MathMax(3.0 * point, spread);
   double nSL = NormalizeDouble(MathRound(newSL / tick) * tick, digits);
   double nTP = (currentTP == 0.0) ? 0.0
                                   : NormalizeDouble(MathRound(currentTP / tick) * tick, digits);

   double curPrice = (posType == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(posSymbol, SYMBOL_BID)
                     : SymbolInfoDouble(posSymbol, SYMBOL_ASK);

   // Directional tick rounding keeps the requested stop on the safe side of
   // the broker's live stops/freeze boundary. MathRound could round a valid
   // boundary one tick toward price and turn it into TRADE_RETCODE_INVALID_STOPS.
   if(posType == POSITION_TYPE_BUY)
      nSL = MathMin(nSL, NormalizeDouble(MathFloor((curPrice - safeBuffer) / tick) * tick, digits));
   else
      nSL = MathMax(nSL, NormalizeDouble(MathCeil((curPrice + safeBuffer) / tick) * tick, digits));

   double existingSLNorm = (existingSL > 0.0)
                           ? NormalizeDouble(MathRound(existingSL / tick) * tick, digits)
                           : 0.0;
   if(existingSLNorm > 0.0 && MathAbs(existingSLNorm - nSL) < tick * 0.5 &&
      MathAbs(nTP - NormalizeDouble(MathRound(currentTP / MathMax(tick, point)) * tick, digits)) < tick * 0.5)
     {
      if(m_diag != NULL)
        {
         static ulong s_redTicket = 0;
         static datetime s_redBar = 0;
         datetime bar = iTime(posSymbol, PERIOD_M3, 0);
         if(ticket != s_redTicket || bar != s_redBar)
           {
            m_diag.RecordRedundantModify();
            s_redTicket = ticket;
            s_redBar = bar;
           }
        }
      return true;
     }

   bool wrongSide = (posType == POSITION_TYPE_BUY) ? (nSL >= curPrice) : (nSL <= curPrice);
   if(wrongSide || MathAbs(curPrice - nSL) < safeBuffer)
   {
      static datetime lastInvalidStopLog = 0;
      if(TimeCurrent() - lastInvalidStopLog >= 60)
        {
         LogSystemWarning("OrderManager", "SafeModifySL",
                          StringFormat("Deferred invalid/too-close SL | ticket=%I64u symbol=%s newSL=%.5f price=%.5f minDist=%.5f",
                                       ticket, posSymbol, nSL, curPrice, safeBuffer));
         lastInvalidStopLog = TimeCurrent();
        }
      return false;
   }

   static ulong  s_lastErrTicket = 0;
   static uint   s_lastErrCode   = 0;
   static datetime s_lastErrTime  = 0;
   bool codeSeen10016 = false;
   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      if(m_trade.PositionModify(ticket, nSL, nTP) && TradeResultOK())
        {
         if(codeSeen10016 && m_diag != NULL)
            m_diag.RecordModifySL10016Recovered();
         return true;
        }

      uint code = m_trade.ResultRetcode();
      RegisterTradeFailure(code);
      bool allowLog = (s_lastErrTicket != ticket) ||
                      (s_lastErrCode != code) ||
                      (TimeCurrent() - s_lastErrTime >= 60);
      if(code == TRADE_RETCODE_INVALID_STOPS)
        {
         codeSeen10016 = true;
         if(m_diag != NULL) m_diag.RecordModifySL10016();
         if(allowLog)
           {
            LogMsg(LOG_LEVEL_ERROR, "SafeModifySL",
                   StringFormat("H7 BUG — broker rejected the stop as invalid (10016) | ticket=%I64u type=%s newSL=%.5f tp=%.5f price=%.5f attempt=%d/%d comment='%s'",
                                ticket, (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                                nSL, nTP, curPrice, attempt + 1, m_maxRetryAttempts + 1,
                                m_trade.ResultComment()));
            s_lastErrTicket = ticket; s_lastErrCode = code; s_lastErrTime = TimeCurrent();
           }
        }
      else
        {
         if(allowLog)
           {
            LogTradeError("SafeModifySL", ticket, code, m_trade.ResultComment(),
                          StringFormat("NewSL: %.2f, CurrentTP: %.2f, attempt: %d/%d",
                                       nSL, nTP, attempt + 1, m_maxRetryAttempts + 1));
            s_lastErrTicket = ticket; s_lastErrCode = code; s_lastErrTime = TimeCurrent();
           }
        }
       if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      RetryBackoff(attempt);
   }

   if(existingSL <= 0.0)
     {
      if(m_diag != NULL) m_diag.RecordUnprotectedPosition();
      SendCriticalAlert("UNPROTECTED_" + (string)ticket,
                        StringFormat("Position %I64u has no server-side SL after protection failed", ticket),
                        300);
     }
   LogMsg(existingSL > 0.0 ? LOG_LEVEL_WARN : LOG_LEVEL_ERROR, "SafeModifySL",
          StringFormat("Protective SL upgrade failed after %d attempts | ticket=%I64u type=%s requestedSL=%.5f existingSL=%.5f tp=%.5f price=%.5f",
                       m_maxRetryAttempts + 1, ticket,
                       (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                       nSL, existingSL, nTP, curPrice));
   return false;
}

//+------------------------------------------------------------------+
bool COrderManager::PartialClose(ulong ticket, double lots)
{
   if(!PositionSelectByTicket(ticket) || lots <= 0.0) return false;
   string sym       = PositionGetString(POSITION_SYMBOL);
   if(!CanSendTradeRequest(sym)) return false;
   double current   = PositionGetDouble(POSITION_VOLUME);
   double minLot    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double step      = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step > 0.0) lots = MathFloor((lots + 1e-12) / step) * step;
   if(lots < minLot || lots >= current || (current - lots) < minLot) return false;

   m_trade.SetTypeFillingBySymbol(sym);
   bool isHedging = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   long posType = PositionGetInteger(POSITION_TYPE);

   bool res = false;
   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      bool sent = false;
      if(isHedging)
         sent = m_trade.PositionClosePartial(ticket, lots);
      else
        {
         if(posType == POSITION_TYPE_BUY)
            sent = m_trade.Sell(lots, sym, 0.0, 0.0, 0.0, "YANSTD Partial");
         else if(posType == POSITION_TYPE_SELL)
            sent = m_trade.Buy(lots, sym, 0.0, 0.0, 0.0, "YANSTD Partial");
        }
      res = sent && TradeResultOK();
      // In the tester CTrade can occasionally return false even though the
      // server retcode is DONE and the requested volume has already changed.
      // Accept success only when both the retcode and the position postcondition
      // confirm it, so a stale successful retcode cannot hide a real failure.
      if(!res && TradeResultOK() && PositionSelectByTicket(ticket))
         res = (PositionGetDouble(POSITION_VOLUME) < current - 1e-12);
      if(res) break;

      uint code = m_trade.ResultRetcode();
      RegisterTradeFailure(code);
      static ulong  s_lastPCTicket = 0;
      static uint   s_lastPCCode   = 0;
      static datetime s_lastPCTime  = 0;
      bool allowPCLog = (s_lastPCTicket != ticket) ||
                        (s_lastPCCode != code) ||
                        (TimeCurrent() - s_lastPCTime >= 60);
      if(allowPCLog)
        {
         LogTradeError("PartialClose", ticket, code, m_trade.ResultComment(),
                       StringFormat("Lots: %.2f, attempt: %d/%d", lots, attempt + 1, m_maxRetryAttempts + 1));
         s_lastPCTicket = ticket; s_lastPCCode = code; s_lastPCTime = TimeCurrent();
        }
      // A timeout can still have partially filled the request. Re-sending the
      // same partial close would close volume twice, so reconcile and leave an
      // unresolved timeout for the next transaction/tick instead of retrying.
      if(code == TRADE_RETCODE_TIMEOUT)
      {
         if(PositionSelectByTicket(ticket) && PositionGetDouble(POSITION_VOLUME) < current - 1e-12)
            res = true;
         else
            LogSystemWarning("OrderManager", "PartialClose", "Timeout outcome unknown; request is not retried to prevent a double partial close");
         break;
      }
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      if(!PositionSelectByTicket(ticket)) break; // position already gone — nothing left to retry
      RetryBackoff(attempt);
   }
   return res;
}

//+------------------------------------------------------------------+
bool COrderManager::ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return true;
   string posSymbol = PositionGetString(POSITION_SYMBOL);
   if(!CanSendTradeRequest(posSymbol)) return false;
   m_trade.SetTypeFillingBySymbol(posSymbol);

   static ulong  s_lastCloseTicket = 0;
   static uint   s_lastCloseCode   = 0;
   static datetime s_lastCloseTime  = 0;
   bool res = false;
   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      bool sent = m_trade.PositionClose(ticket);
      res = sent && TradeResultOK();
      // Edge case: CTrade::PositionClose() can return false (send/exec
      // reported failure) even though the last trade result code is
      // actually OK (e.g. broker requote/timeout on the response leg
      // after the position was already closed server-side). When that
      // happens we re-verify by checking whether the position still
      // exists; if it's gone, treat the close as successful. This is
      // intentional double-checking, not a redundant duplicate call.
      if(!res && TradeResultOK())
         res = !PositionSelectByTicket(ticket);
      if(res) break;

      uint code = m_trade.ResultRetcode();
      RegisterTradeFailure(code);
      bool allowLog = (s_lastCloseTicket != ticket) ||
                      (s_lastCloseCode != code) ||
                      (TimeCurrent() - s_lastCloseTime >= 60);
      if(allowLog)
        {
         LogTradeError("ClosePosition", ticket, code, m_trade.ResultComment(),
                       StringFormat("attempt: %d/%d", attempt + 1, m_maxRetryAttempts + 1));
         s_lastCloseTicket = ticket; s_lastCloseCode = code; s_lastCloseTime = TimeCurrent();
        }
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      if(!PositionSelectByTicket(ticket)) { res = true; break; } // already closed — nothing left to retry
      RetryBackoff(attempt);
   }
   return res;
}

bool COrderManager::RequestManagedClose(ulong ticket, string reason)
{
   if(ticket == 0) return false;

   int idx = FindCloseReq(ticket);
   if(idx < 0)
   {
      // First request for this ticket: log once and send.
      BeginCloseRequest(ticket);
      idx = FindCloseReq(ticket);
      if(idx >= 0) m_closeReqs[idx].logged = true;
      if(m_diag != NULL) m_diag.RecordTimeInvalidation(false);
      LogMsg(LOG_LEVEL_INFO, "ManagedClose",
             StringFormat("Closing position | ticket=%I64u reason=%s", ticket, reason));
      bool ok = ClosePosition(ticket);
      if(!ok && idx >= 0) m_closeReqs[idx].state = CLOSE_PENDING;
      return ok;
   }

   // A request is already in flight. Do not count polling as a retry.

   datetime now = TimeCurrent();
   if(m_closeReqs[idx].state == CLOSE_UNMANAGED) return false;

   // A closed trading session means no close request was sent. Keep the
   // position managed and pending; do not age a local preflight rejection into
   // an "unanswered" broker request. This also covers the short cooldown set
   // after TRADE_RETCODE_MARKET_CLOSED.
   if(!PositionSelectByTicket(ticket))
   {
      EndCloseRequest(ticket);
      return true;
   }
   string posSymbol = PositionGetString(POSITION_SYMBOL);
   if(!CanSendTradeRequest(posSymbol)) return false;

   if(now - m_closeReqs[idx].firstRequest < YANSTD_CLOSE_ESCALATE_SECONDS) return false;

   if(m_closeReqs[idx].state == CLOSE_ESCALATED)
   {
      m_closeReqs[idx].state = CLOSE_UNMANAGED;
      LogMsg(LOG_LEVEL_ERROR, "ManagedClose",
             StringFormat("H3 — position could NOT be closed after escalation; marked UNMANAGED and left to server-side protection | ticket=%I64u reason=%s", ticket, reason));
      return false;
   }

   // Deadline passed and it is still open: escalate once.
   if(m_diag != NULL) m_diag.RecordTimeInvalidation(true);
   m_closeReqs[idx].state = CLOSE_ESCALATED;
   LogMsg(LOG_LEVEL_WARN, "ManagedClose",
          StringFormat("Close request unanswered after %d s; escalating | ticket=%I64u reason=%s",
                       (int)(now - m_closeReqs[idx].firstRequest), ticket, reason));
   bool ok = ClosePosition(ticket);
   if(!ok)
   {
      LogMsg(LOG_LEVEL_WARN, "ManagedClose",
             StringFormat("Escalated close also failed; will mark UNMANAGED on the next pass | ticket=%I64u", ticket));
   }
   return ok;
}

//+------------------------------------------------------------------+
//| H3 — drop bookkeeping for positions that no longer exist.         |
//+------------------------------------------------------------------+
void COrderManager::AuditCloseRequests()
{
   PurgeCloseRequests();
}

//+------------------------------------------------------------------+
bool COrderManager::CloseAllByMagic()
{
   bool success = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic &&
         PositionGetString(POSITION_SYMBOL) == Symbol())
        {
         if(!ClosePosition(ticket))
            success = false;
        }
   }
   return success;
}

//+------------------------------------------------------------------+
bool COrderManager::DeleteAllPendingByMagic()
{
   bool success = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic &&
         OrderGetString(ORDER_SYMBOL) == Symbol())
        {
         if(!DeletePendingTicket(ticket))
            success = false;
        }
   }
   return success;
}

//+------------------------------------------------------------------+
bool COrderManager::DeletePendingByType(ENUM_ORDER_TYPE type)
{
   bool success = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic &&
         OrderGetString(ORDER_SYMBOL) == Symbol())
      {
         if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == type)
         {
            if(!DeletePendingTicket(ticket))
               success = false;
         }
      }
   }
   return success;
}

//+------------------------------------------------------------------+
bool COrderManager::DeletePendingTicket(ulong ticket)
{
   if(ticket == 0 || !OrderSelect(ticket)) return false;
   if(OrderGetInteger(ORDER_MAGIC) != (long)m_magic || OrderGetString(ORDER_SYMBOL) != Symbol()) return false;
   if(!CanSendTradeRequest(OrderGetString(ORDER_SYMBOL))) return false;

   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      if(m_trade.OrderDelete(ticket) && TradeResultOK())
         return true;

      uint code = m_trade.ResultRetcode();
      RegisterTradeFailure(code);
      LogTradeError("DeletePendingTicket", ticket, code, m_trade.ResultComment(),
                    StringFormat("Pending order delete, attempt: %d/%d", attempt + 1, m_maxRetryAttempts + 1));
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      if(!OrderSelect(ticket)) return true; // already gone (filled/deleted elsewhere) — treat as success
      RetryBackoff(attempt);
   }
   return false;
}

//+------------------------------------------------------------------+
bool COrderManager::HasOpenPosition()
{
   return CountOpenPositions() > 0;
}

//+------------------------------------------------------------------+
int COrderManager::CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic &&
         PositionGetString(POSITION_SYMBOL) == Symbol())
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
int COrderManager::CountPendingOrders()
{
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic &&
         OrderGetString(ORDER_SYMBOL) == Symbol())
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
void COrderManager::RegisterNewTrack(ulong ticket, double tp1Level, double tp2Level, int brainBucketIdx,
                                      double tp1ClosePct, double tp2ClosePct,
                                      ulong setupEventId, double brainEvidenceWeight,
                                      double serverTP, ENUM_TARGET_SOURCE targetSource,
                                      bool reconstructed)
{
   if(ticket <= 0) return;
   for(int k = 0; k < m_trackCount; k++)
   {
      if(m_tracks[k].ticket == ticket)
      {
         // Already registered — preserve existing position's unique TP1 level and AI bucket
         return;
      }
   }
   if(EnsureTrackCapacity(m_trackCount + 1))
   {
      m_tracks[m_trackCount].ticket         = ticket;
      m_tracks[m_trackCount].tp1Level       = tp1Level;
      m_tracks[m_trackCount].tp2Level       = tp2Level;
      double initialLots = 0.0;
      double actualOpen = 0.0;
      double actualRisk = 0.0;
      int posType = -1;
      string symbol = Symbol();
      if(PositionSelectByTicket(ticket))
        {
         initialLots = PositionGetDouble(POSITION_VOLUME);
         symbol      = PositionGetString(POSITION_SYMBOL);
         actualOpen = PositionGetDouble(POSITION_PRICE_OPEN);
         double actualSL   = PositionGetDouble(POSITION_SL);
         posType            = (int)PositionGetInteger(POSITION_TYPE);
         if(posType == POSITION_TYPE_BUY && actualSL > 0.0 && actualSL < actualOpen)
            actualRisk = actualOpen - actualSL;
         else if(posType == POSITION_TYPE_SELL && actualSL > actualOpen)
            actualRisk = actualSL - actualOpen;
         // H4 FIX: this used to unconditionally recompute tp1Level/tp2Level
         // from actualRisk * default RR, silently discarding any structural
         // target the caller already computed (e.g. SignalEngine's MSNR
         // opposing-zone TP2). The per-field "<= 0.0" checks below already
         // protect any valid (> 0) level the caller passed in, whether this
         // is a fresh registration or a restart-reconstruction call.
         // The fallback must still fire when reconstructed == true — that is
         // exactly the restart-reconstruction path in Init(), which calls
         // RegisterNewTrack with tp1Level/tp2Level == 0.0 because no
         // structural levels are available after a terminal restart. The
         // previous "&& !reconstructed" guard did the opposite of what the
         // comment intended: it skipped the fallback during reconstruction,
         // leaving restarted STAGED/FIXED_RR positions (which rely entirely
         // on these locally tracked levels — they carry no broker-side TP)
         // with tp1Level/tp2Level stuck at 0.0 and unmanaged.
         if(actualRisk > 0.0)
           {
            if(tp1Level <= 0.0)
               m_tracks[m_trackCount].tp1Level = (posType == POSITION_TYPE_BUY)
                                                   ? actualOpen + actualRisk * m_defaultTP1RR
                                                   : actualOpen - actualRisk * m_defaultTP1RR;
            if(tp2Level <= 0.0)
               m_tracks[m_trackCount].tp2Level = (posType == POSITION_TYPE_BUY)
                                                   ? actualOpen + actualRisk * m_defaultTP2RR
                                                   : actualOpen - actualRisk * m_defaultTP2RR;
           }
         if(serverTP <= 0.0)
            serverTP = PositionGetDouble(POSITION_TP);
         }
      m_tracks[m_trackCount].initialLots = initialLots;
      m_tracks[m_trackCount].openPrice = actualOpen;
      m_tracks[m_trackCount].posType = posType;
      m_tracks[m_trackCount].initialRiskPrice = actualRisk;
      m_tracks[m_trackCount].initialRiskMoney = CalcInitialRiskMoney(symbol, actualRisk, initialLots);
      m_tracks[m_trackCount].maxFavorableR = 0.0;
      m_tracks[m_trackCount].maxAdverseR = 0.0;
      double trackPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double trackBid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double trackAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
      m_tracks[m_trackCount].maxSpreadPoints = (trackPoint > 0.0 && trackAsk >= trackBid)
                                                   ? (trackAsk - trackBid) / trackPoint : 0.0;
      m_tracks[m_trackCount].lastSeenTime = TimeCurrent();
      BuildScaleOutPlan(symbol, initialLots, tp1ClosePct, tp2ClosePct,
                        m_tracks[m_trackCount].tp1CloseLots,
                        m_tracks[m_trackCount].tp2CloseLots,
                        m_tracks[m_trackCount].runnerLots,
                        m_tracks[m_trackCount].scaleOutEnabled);
      // Structural POI: tp2 pct = 0 means close down to broker min (0.01) at TP1,
      // leave that runner for the open/target TP. Do not full-close at the 80-pip step.
      if(tp1ClosePct > 0.0 && tp2ClosePct <= 0.0 && initialLots > 0.0)
        {
         double minL = EffectiveBrokerMinLot(symbol);
         if(minL <= 0.0) minL = YANSTD_HARD_MIN_LOT;
         minL = EnforceBrokerMinLot(minL, symbol);
         if(initialLots > minL + 1e-8)
           {
            double closeLots = NormalizeDouble(initialLots - minL, 8);
            closeLots = FloorVolumeToStep(closeLots, symbol);
            if(closeLots >= minL && (initialLots - closeLots) + 1e-12 >= minL)
              {
               m_tracks[m_trackCount].tp1CloseLots = closeLots;
               m_tracks[m_trackCount].tp2CloseLots = 0.0;
               m_tracks[m_trackCount].runnerLots = NormalizeDouble(initialLots - closeLots, 8);
               m_tracks[m_trackCount].scaleOutEnabled = true;
              }
           }
         else
           {
            m_tracks[m_trackCount].tp1CloseLots = 0.0;
            m_tracks[m_trackCount].tp2CloseLots = 0.0;
            m_tracks[m_trackCount].runnerLots = initialLots;
            m_tracks[m_trackCount].scaleOutEnabled = false;
           }
        }
      m_tracks[m_trackCount].tp1Done        = false;
      m_tracks[m_trackCount].bepDone        = false;
      m_tracks[m_trackCount].milestoneDone  = false;
      m_tracks[m_trackCount].tp2Done        = false;
      m_tracks[m_trackCount].tp2Time        = 0;
      m_tracks[m_trackCount].trailActive    = false;
      m_tracks[m_trackCount].brainBucketIdx = brainBucketIdx;
      m_tracks[m_trackCount].setupEventId = setupEventId;
      m_tracks[m_trackCount].brainEvidenceWeight = MathMax(0.01, MathMin(1.0, brainEvidenceWeight));
      m_tracks[m_trackCount].serverTP = serverTP;
      m_tracks[m_trackCount].targetSource = (int)targetSource;
      m_tracks[m_trackCount].needsTargetRecovery = reconstructed ||
         (targetSource == TARGET_NONE && serverTP <= 0.0);
      m_tracks[m_trackCount].entryVariant = -1;
      m_tracks[m_trackCount].setupGrade = -1;
      LogMsg(LOG_LEVEL_INFO, "OrderManager",
             StringFormat("ExitPlan: Ticket=%I64u | Initial=%s | Mode=%s | TP1Lots=%s | TP2Lots=%s | Runner=%s",
                          ticket,
                          DoubleToString(initialLots, 2),
                          (m_tracks[m_trackCount].scaleOutEnabled ? "TP1/TP2/RUNNER" : "FULL_CLOSE_TP1"),
                          DoubleToString(m_tracks[m_trackCount].tp1CloseLots, 2),
                          DoubleToString(m_tracks[m_trackCount].tp2CloseLots, 2),
                          DoubleToString(m_tracks[m_trackCount].runnerLots, 2)));
      m_trackCount++;
      SaveTracks();
   }
   else
   {
      LogMsg(LOG_LEVEL_ERROR, "OrderManager",
             StringFormat("Track storage allocation failed — ticket=%I64u cannot be persisted for position management.",
                          ticket));
   }
}

bool COrderManager::GetTrackTicket(const int index, ulong &ticket) const
{
   if(index < 0 || index >= m_trackCount) return false;
   ticket = m_tracks[index].ticket;
   return (ticket > 0);
}

bool COrderManager::TrackNeedsTargetRecovery(ulong ticket) const
{
   for(int k = 0; k < m_trackCount; k++)
      if(m_tracks[k].ticket == ticket)
         return m_tracks[k].needsTargetRecovery ||
                m_tracks[k].targetSource == (int)TARGET_NONE;
   return false;
}

ENUM_TARGET_SOURCE COrderManager::GetTrackTargetSource(ulong ticket) const
{
   for(int k = 0; k < m_trackCount; k++)
      if(m_tracks[k].ticket == ticket)
         return (ENUM_TARGET_SOURCE)m_tracks[k].targetSource;
   return TARGET_NONE;
}

double COrderManager::GetTrackServerTP(ulong ticket) const
{
   for(int k = 0; k < m_trackCount; k++)
      if(m_tracks[k].ticket == ticket)
         return m_tracks[k].serverTP;
   return 0.0;
}

bool COrderManager::ApplyServerTP(ulong ticket, double newTP)
{
   if(ticket <= 0 || !PositionSelectByTicket(ticket)) return false;
   string sym = PositionGetString(POSITION_SYMBOL);
   double sl = PositionGetDouble(POSITION_SL);
   double existingTP = PositionGetDouble(POSITION_TP);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = point;
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double tp = NormalizeDouble(MathRound(newTP / tick) * tick, digits);

   // Pending fills can inherit a valid-on-placement SL/TP that is no longer
   // modifiable at the fill quote. Never submit an unchanged pair: MT5 still
   // revalidates both stops and produces a useless 10016 storm.
   if(existingTP > 0.0 && MathAbs(existingTP - tp) < tick * 0.5)
      return true;

   int posType = (int)PositionGetInteger(POSITION_TYPE);
   double price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                  : SymbolInfoDouble(sym, SYMBOL_ASK);
   double spread = MathMax(0.0, SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID));
   double minDist = MathMax((double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL),
                            (double)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL)) * point +
                    MathMax(3.0 * point, spread);
   bool targetValid = (posType == POSITION_TYPE_BUY) ? (tp > price && tp - price >= minDist)
                                                       : (tp < price && price - tp >= minDist);
   bool stopStillValid = (sl <= 0.0) ||
                         ((posType == POSITION_TYPE_BUY) ? (sl < price && price - sl >= minDist)
                                                         : (sl > price && sl - price >= minDist));
   if(!targetValid || !stopStillValid)
     {
      LogSystemWarning("OrderManager", "ApplyServerTP",
                       StringFormat("Deferred TP modify outside broker stop/freeze distance | ticket=%I64u tp=%.5f sl=%.5f price=%.5f minDist=%.5f",
                                    ticket, tp, sl, price, minDist));
      return false;
     }

   for(int attempt = 0; attempt <= m_maxRetryAttempts; attempt++)
   {
      if(m_trade.PositionModify(ticket, sl, tp) && TradeResultOK())
         return true;
      uint code = m_trade.ResultRetcode();
      RegisterTradeFailure(code);
      if(attempt >= m_maxRetryAttempts || !IsTransientTradeRetcode(code)) break;
      RetryBackoff(attempt);
   }
   return false;
}

bool COrderManager::UpdateTrackTarget(ulong ticket, double serverTP, double tp1Level,
                                      ENUM_TARGET_SOURCE source)
{
   for(int k = 0; k < m_trackCount; k++)
     {
      if(m_tracks[k].ticket != ticket) continue;
      m_tracks[k].serverTP = serverTP;
      if(tp1Level > 0.0)
         m_tracks[k].tp1Level = tp1Level;
      m_tracks[k].targetSource = (int)source;
      m_tracks[k].needsTargetRecovery = (source == TARGET_NONE);
      SaveTracks();
      return true;
     }
   return false;
}

bool COrderManager::RecalcTrackFromFill(ulong ticket, double fillPrice, double slPrice)
{
   for(int k = 0; k < m_trackCount; k++)
     {
      if(m_tracks[k].ticket != ticket) continue;
      if(fillPrice > 0.0)
         m_tracks[k].openPrice = fillPrice;
      string symbol = Symbol();
      double lots = m_tracks[k].initialLots;
      int posType = m_tracks[k].posType;
      if(PositionSelectByTicket(ticket))
        {
         symbol = PositionGetString(POSITION_SYMBOL);
         lots = PositionGetDouble(POSITION_VOLUME);
         posType = (int)PositionGetInteger(POSITION_TYPE);
         if(fillPrice <= 0.0)
            fillPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         if(slPrice <= 0.0)
            slPrice = PositionGetDouble(POSITION_SL);
        }
      double risk = 0.0;
      if(posType == POSITION_TYPE_BUY && slPrice > 0.0 && slPrice < fillPrice)
         risk = fillPrice - slPrice;
      else if(posType == POSITION_TYPE_SELL && slPrice > fillPrice)
         risk = slPrice - fillPrice;
      m_tracks[k].posType = posType;
      m_tracks[k].initialLots = lots;
      m_tracks[k].initialRiskPrice = risk;
      m_tracks[k].initialRiskMoney = CalcInitialRiskMoney(symbol, risk, lots);
      SaveTracks();
      return (risk > 0.0);
     }
   return false;
}

//+------------------------------------------------------------------+
int COrderManager::GetTrackBrainBucket(ulong ticket)
{
   if(ticket <= 0) return -1;
   for(int k = 0; k < m_trackCount; k++)
   {
      if(m_tracks[k].ticket == ticket)
         return m_tracks[k].brainBucketIdx;
   }
   return -1;
}

//+------------------------------------------------------------------+
ulong COrderManager::GetTrackSetupEventId(ulong ticket)
{
   for(int k = 0; k < m_trackCount; k++)
      if(m_tracks[k].ticket == ticket) return m_tracks[k].setupEventId;
   return 0;
}

//+------------------------------------------------------------------+
double COrderManager::GetTrackBrainEvidenceWeight(ulong ticket)
{
   for(int k = 0; k < m_trackCount; k++)
      if(m_tracks[k].ticket == ticket) return m_tracks[k].brainEvidenceWeight;
   return 1.0;
}

void COrderManager::SetTrackAttribution(ulong ticket, int variant, int grade)
{
   for(int k = 0; k < m_trackCount; k++)
     {
      if(m_tracks[k].ticket != ticket) continue;
      if(variant >= 0) m_tracks[k].entryVariant = variant;
      if(grade >= 0)   m_tracks[k].setupGrade = grade;
      SaveTracks();
      return;
     }
}

bool COrderManager::GetTrackAttribution(ulong ticket, int &variant, int &grade) const
{
   variant = -1;
   grade = -1;
   for(int k = 0; k < m_trackCount; k++)
     {
      if(m_tracks[k].ticket != ticket) continue;
      variant = m_tracks[k].entryVariant;
      grade = m_tracks[k].setupGrade;
      return (variant >= 0 || grade >= 0);
     }
   return false;
}

//+------------------------------------------------------------------+
bool COrderManager::GetTrackLearningState(ulong ticket, double &openPrice, int &posType,
                                           double &initialLots, double &initialRiskPrice, double &initialRiskMoney,
                                           double &maxFavorableR, double &maxAdverseR, double &maxSpreadPoints)
{
   for(int k = 0; k < m_trackCount; k++)
   {
      if(m_tracks[k].ticket != ticket) continue;
      openPrice        = m_tracks[k].openPrice;
      posType          = m_tracks[k].posType;
      initialLots      = m_tracks[k].initialLots;
      initialRiskPrice = m_tracks[k].initialRiskPrice;
      initialRiskMoney = m_tracks[k].initialRiskMoney;
      maxFavorableR    = m_tracks[k].maxFavorableR;
      maxAdverseR      = m_tracks[k].maxAdverseR;
      maxSpreadPoints  = m_tracks[k].maxSpreadPoints;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void COrderManager::UpdateTrackExcursion(ulong ticket, double maxFavorableR, double maxAdverseR, double maxSpreadPoints)
{
   for(int k = 0; k < m_trackCount; k++)
   {
      if(m_tracks[k].ticket != ticket) continue;
      double oldMFE = m_tracks[k].maxFavorableR;
      double oldMAE = m_tracks[k].maxAdverseR;
      double oldSpread = m_tracks[k].maxSpreadPoints;
      if(maxFavorableR <= oldMFE && maxAdverseR <= oldMAE && maxSpreadPoints <= oldSpread) return;

      m_tracks[k].maxFavorableR = MathMax(oldMFE, maxFavorableR);
      m_tracks[k].maxAdverseR   = MathMax(oldMAE, maxAdverseR);
      m_tracks[k].maxSpreadPoints = MathMax(oldSpread, maxSpreadPoints);
      // Persist only when a new 0.1R or whole-spread-point band is reached.
      if((int)MathFloor(m_tracks[k].maxFavorableR * 10.0) > (int)MathFloor(oldMFE * 10.0) ||
         (int)MathFloor(m_tracks[k].maxAdverseR * 10.0) > (int)MathFloor(oldMAE * 10.0) ||
         (int)MathFloor(m_tracks[k].maxSpreadPoints) > (int)MathFloor(oldSpread))
         SaveTracks();
      return;
   }
}

//+------------------------------------------------------------------+
void COrderManager::UpdateTrackState(const SPositionInfo &pos)
{
   for(int k = 0; k < m_trackCount; k++)
   {
      if(m_tracks[k].ticket == pos.ticket)
      {
         // AUDIT FIX: delta check prevents synchronous disk write if state has not changed
         bool stateChanged = (m_tracks[k].tp1Done != pos.tp1Done ||
                              m_tracks[k].bepDone != pos.bepDone ||
                              m_tracks[k].milestoneDone != pos.milestoneDone ||
                              m_tracks[k].tp2Done != pos.tp2Done ||
                              m_tracks[k].trailActive != pos.trailActive ||
                              m_tracks[k].brainBucketIdx != pos.brainBucketIdx ||
                              m_tracks[k].scaleOutEnabled != pos.scaleOutEnabled ||
                              m_tracks[k].tp2Time != pos.tp2Time ||
                              MathAbs(m_tracks[k].tp1Level - pos.tp1Level) > 1e-6 ||
                              MathAbs(m_tracks[k].tp2Level - pos.tp2Level) > 1e-6 ||
                              MathAbs(m_tracks[k].openPrice - pos.openPrice) > 1e-6 ||
                              MathAbs(m_tracks[k].initialLots - pos.initialLots) > 1e-6 ||
                              MathAbs(m_tracks[k].tp1CloseLots - pos.tp1CloseLots) > 1e-6 ||
                              MathAbs(m_tracks[k].tp2CloseLots - pos.tp2CloseLots) > 1e-6 ||
                              MathAbs(m_tracks[k].runnerLots - pos.runnerLots) > 1e-6 ||
                              MathAbs(m_tracks[k].maxFavorableR - pos.maxFavorableR) > 0.05 ||
                                                             MathAbs(m_tracks[k].maxAdverseR - pos.maxAdverseR) > 0.05 ||
                                                             MathAbs(m_tracks[k].maxSpreadPoints - pos.maxSpreadPoints) > 0.5);

         m_tracks[k].tp1Level       = pos.tp1Level;
         m_tracks[k].tp2Level       = pos.tp2Level;
         m_tracks[k].initialLots    = pos.initialLots;
         m_tracks[k].openPrice      = pos.openPrice;
         m_tracks[k].posType        = pos.posType;
         m_tracks[k].initialRiskPrice = pos.initialRiskPrice;
         m_tracks[k].initialRiskMoney = pos.initialRiskMoney;
         m_tracks[k].maxFavorableR  = pos.maxFavorableR;
         m_tracks[k].maxAdverseR    = pos.maxAdverseR;
         m_tracks[k].maxSpreadPoints= pos.maxSpreadPoints;
         m_tracks[k].lastSeenTime   = TimeCurrent();
         m_tracks[k].tp1CloseLots   = pos.tp1CloseLots;
         m_tracks[k].tp2CloseLots   = pos.tp2CloseLots;
         m_tracks[k].runnerLots     = pos.runnerLots;
         m_tracks[k].scaleOutEnabled= pos.scaleOutEnabled;
         m_tracks[k].tp1Done        = pos.tp1Done;
         m_tracks[k].bepDone        = pos.bepDone;
         m_tracks[k].milestoneDone  = pos.milestoneDone; // Persist milestone state
         m_tracks[k].tp2Done        = pos.tp2Done;
         m_tracks[k].tp2Time        = pos.tp2Time;
         m_tracks[k].trailActive    = pos.trailActive;
         m_tracks[k].brainBucketIdx = pos.brainBucketIdx;
         if(stateChanged)
            SaveTracks();
         return;
      }
   }
   if(EnsureTrackCapacity(m_trackCount + 1))
   {
      m_tracks[m_trackCount].ticket         = pos.ticket;
      m_tracks[m_trackCount].tp1Level       = pos.tp1Level;
      m_tracks[m_trackCount].tp2Level       = pos.tp2Level;
      m_tracks[m_trackCount].initialLots    = pos.initialLots;
      m_tracks[m_trackCount].openPrice      = pos.openPrice;
      m_tracks[m_trackCount].posType        = pos.posType;
      m_tracks[m_trackCount].initialRiskPrice = pos.initialRiskPrice;
      m_tracks[m_trackCount].initialRiskMoney = pos.initialRiskMoney;
      m_tracks[m_trackCount].maxFavorableR  = pos.maxFavorableR;
      m_tracks[m_trackCount].maxAdverseR    = pos.maxAdverseR;
      m_tracks[m_trackCount].maxSpreadPoints= pos.maxSpreadPoints;
      m_tracks[m_trackCount].lastSeenTime   = TimeCurrent();
      m_tracks[m_trackCount].tp1CloseLots   = pos.tp1CloseLots;
      m_tracks[m_trackCount].tp2CloseLots   = pos.tp2CloseLots;
      m_tracks[m_trackCount].runnerLots     = pos.runnerLots;
      m_tracks[m_trackCount].scaleOutEnabled= pos.scaleOutEnabled;
      m_tracks[m_trackCount].tp1Done        = pos.tp1Done;
      m_tracks[m_trackCount].bepDone        = pos.bepDone;
      m_tracks[m_trackCount].milestoneDone  = pos.milestoneDone; // Initialize from caller state
      m_tracks[m_trackCount].tp2Done        = pos.tp2Done;
      m_tracks[m_trackCount].tp2Time        = pos.tp2Time;
      m_tracks[m_trackCount].trailActive    = pos.trailActive;
      m_tracks[m_trackCount].brainBucketIdx = pos.brainBucketIdx;
      string appendComment = "";
      if(PositionSelectByTicket(pos.ticket)) appendComment = PositionGetString(POSITION_COMMENT);
      int appendEventPos = StringFind(appendComment, "_E");
      m_tracks[m_trackCount].setupEventId = (appendEventPos >= 0)
                                           ? DecodeBase36(appendComment, appendEventPos + 2) : 0;
      m_tracks[m_trackCount].brainEvidenceWeight = (StringFind(appendComment, "_M") >= 0)
                                                   ? 1.0 / (double)MATRIX_MAX_CANDIDATE_COUNT : 1.0;
      m_tracks[m_trackCount].serverTP = 0.0;
      m_tracks[m_trackCount].targetSource = (int)TARGET_NONE;
      m_tracks[m_trackCount].needsTargetRecovery = true;
      m_trackCount++;
      SaveTracks();
   }
   else
   {
      LogMsg(LOG_LEVEL_ERROR, "OrderManager",
             StringFormat("Track storage allocation failed — ticket=%I64u could not be re-registered in SPosTrack.",
                          pos.ticket));
   }
}

//+------------------------------------------------------------------+
// A NEWS_LIVE partial is an early protective scale-out. Mark TP1 as
// completed so the normal TP1 handler never retries its original lot against
// the now-smaller position. TP2 keeps its original initial-lot target when the
// remaining broker volume can still support it and a runner.
void COrderManager::MarkProtectivePartial(ulong ticket)
{
   if(ticket <= 0 || !PositionSelectByTicket(ticket)) return;
   string sym = PositionGetString(POSITION_SYMBOL);
   double remaining = PositionGetDouble(POSITION_VOLUME);
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   for(int k = 0; k < m_trackCount; k++)
     {
      if(m_tracks[k].ticket != ticket) continue;
      m_tracks[k].tp1Done = true;
      m_tracks[k].tp1CloseLots = 0.0;
      if(m_tracks[k].tp2CloseLots <= 0.0 ||
         remaining - m_tracks[k].tp2CloseLots < minLot)
         m_tracks[k].tp2CloseLots = 0.0; // TP2 handler will safely close all.
      m_tracks[k].lastSeenTime = TimeCurrent();
      SaveTracks();
      return;
     }
}

void COrderManager::RebuildPositionCache()
{
   int rawTotal = PositionsTotal();
   m_posCacheCount = 0;
   if(ArraySize(m_posCacheTickets) < rawTotal) ArrayResize(m_posCacheTickets, rawTotal);
   for(int i = 0; i < rawTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      m_posCacheTickets[m_posCacheCount++] = ticket;
   }
   m_posCacheRawTotal = rawTotal;
}

//+------------------------------------------------------------------+
bool COrderManager::GetPosition(int index, SPositionInfo &info)
{
   if(m_posCacheRawTotal != PositionsTotal()) RebuildPositionCache();
   if(index < 0 || index >= m_posCacheCount) return false;

   ulong ticket = m_posCacheTickets[index];
   return FillPositionByTicket(ticket, info);
}

// AUDIT FIX: ticket-stable accessor. Does not touch the index cache at all,
// so it is safe to call from a loop that snapshotted tickets earlier in the
// same tick, even if other positions closed (and the cache was rebuilt) in
// between.
bool COrderManager::GetPositionByTicket(ulong ticket, SPositionInfo &info)
{
   if(ticket == 0) return false;
   return FillPositionByTicket(ticket, info);
}

bool COrderManager::FillPositionByTicket(ulong ticket, SPositionInfo &info)
{
   // The cache only guarantees the ticket existed as of the last rebuild
   // (keyed off PositionsTotal() changing); re-select it by ticket to get
   // live fields and to detect the rare case where it closed and something
   // else opened in the same raw-count "slot" between rebuilds.
   if(!PositionSelectByTicket(ticket)) { RebuildPositionCache(); return false; }
   {
         info.ticket    = ticket;
         info.symbol    = PositionGetString(POSITION_SYMBOL);
         info.posType   = (int)PositionGetInteger(POSITION_TYPE);
         info.type      = info.posType;   // AUDIT FIX: sync backward-compat alias
         info.lots      = PositionGetDouble(POSITION_VOLUME);
         info.volume    = info.lots;
         info.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         info.sl        = PositionGetDouble(POSITION_SL);
         info.tp        = PositionGetDouble(POSITION_TP);
         info.profit    = PositionGetDouble(POSITION_PROFIT);
         info.openTime  = (datetime)PositionGetInteger(POSITION_TIME);

         int trackIdx = -1;
         for(int k = 0; k < m_trackCount; k++)
         {
            if(m_tracks[k].ticket == ticket)
            {
               trackIdx = k;
               break;
            }
         }

         if(trackIdx >= 0)
         {
            m_tracks[trackIdx].lastSeenTime = TimeCurrent();
            info.tp1Level       = m_tracks[trackIdx].tp1Level;
            info.tp2Level       = m_tracks[trackIdx].tp2Level;
             info.initialLots    = m_tracks[trackIdx].initialLots;
             info.initialRiskPrice = m_tracks[trackIdx].initialRiskPrice;
             info.initialRiskMoney = m_tracks[trackIdx].initialRiskMoney;
             info.maxFavorableR  = m_tracks[trackIdx].maxFavorableR;
             info.maxAdverseR    = m_tracks[trackIdx].maxAdverseR;
             info.maxSpreadPoints= m_tracks[trackIdx].maxSpreadPoints;
            info.tp1CloseLots   = m_tracks[trackIdx].tp1CloseLots;
            info.tp2CloseLots   = m_tracks[trackIdx].tp2CloseLots;
            info.runnerLots     = m_tracks[trackIdx].runnerLots;
            info.scaleOutEnabled= m_tracks[trackIdx].scaleOutEnabled;
            info.tp1Done        = m_tracks[trackIdx].tp1Done;
            info.bepDone        = m_tracks[trackIdx].bepDone;
            info.milestoneDone  = m_tracks[trackIdx].milestoneDone; // Restore persisted milestone state
            info.tp2Done        = m_tracks[trackIdx].tp2Done;
            info.tp2Time        = m_tracks[trackIdx].tp2Time;
            info.trailActive    = m_tracks[trackIdx].trailActive;
            info.brainBucketIdx = m_tracks[trackIdx].brainBucketIdx;
            info.entryType      = (ENUM_SMC_ENTRY_TYPE)MathMax(0, m_tracks[trackIdx].entryVariant);
            info.setupGrade     = (ENUM_SETUP_GRADE)MathMax(0, m_tracks[trackIdx].setupGrade);
         }
         else
         {
            double initialRisk = 0.0;
            if(info.posType == POSITION_TYPE_BUY && info.sl > 0.0 && info.sl < info.openPrice)
               initialRisk = info.openPrice - info.sl;
            else if(info.posType == POSITION_TYPE_SELL && info.sl > info.openPrice)
               initialRisk = info.sl - info.openPrice;
            if(initialRisk <= 0.0)
              {
               static datetime s_lastOrphanWarn = 0;
               datetime nwO = TimeCurrent();
               if(s_lastOrphanWarn == 0 || nwO - s_lastOrphanWarn >= 300)
                 {
                  LogSystemWarning("OrderManager", "GetPosition",
                     StringFormat("Untracked position #%I64u %s; original risk unknown -> TP1/TP2 and R-based management disabled for it (swing trailing still applies).",
                                  info.ticket,
                                  (info.sl <= 0.0) ? "has NO stop-loss" : "has SL at/beyond entry"));
                  s_lastOrphanWarn = nwO;
                 }
              }
            if(info.posType == POSITION_TYPE_BUY)
              {
               info.tp1Level = (initialRisk > 0.0) ? info.openPrice + initialRisk * m_defaultTP1RR : 0.0;
               info.tp2Level = (initialRisk > 0.0) ? info.openPrice + initialRisk * m_defaultTP2RR : 0.0;
              }
            else
              {
               info.tp1Level = (initialRisk > 0.0) ? info.openPrice - initialRisk * m_defaultTP1RR : 0.0;
               info.tp2Level = (initialRisk > 0.0) ? info.openPrice - initialRisk * m_defaultTP2RR : 0.0;
              }

             info.tp1Done        = false;
             info.initialLots    = info.lots;
             info.initialRiskPrice = initialRisk;
             info.initialRiskMoney = CalcInitialRiskMoney(info.symbol, initialRisk, info.initialLots);
             info.maxFavorableR  = 0.0;
             info.maxAdverseR    = 0.0;
             double orphanPoint = SymbolInfoDouble(info.symbol, SYMBOL_POINT);
             double orphanBid = SymbolInfoDouble(info.symbol, SYMBOL_BID);
             double orphanAsk = SymbolInfoDouble(info.symbol, SYMBOL_ASK);
             info.maxSpreadPoints = (orphanPoint > 0.0 && orphanAsk >= orphanBid)
                                    ? (orphanAsk - orphanBid) / orphanPoint : 0.0;
            BuildScaleOutPlan(info.symbol, info.initialLots,
                              m_defaultTP1ClosePct, m_defaultTP2ClosePct,
                              info.tp1CloseLots, info.tp2CloseLots,
                              info.runnerLots, info.scaleOutEnabled);
            info.bepDone        = (info.posType == POSITION_TYPE_BUY)
                                  ? (info.sl >= info.openPrice && info.sl > 0.0)
                                  : (info.sl <= info.openPrice && info.sl > 0.0);
            info.milestoneDone  = false; // Brand-new position tracks have no completed milestone
            info.tp2Done        = false;
            info.tp2Time        = 0;
            info.trailActive    = false;
            info.brainBucketIdx = -1;
            info.entryType      = (ENUM_SMC_ENTRY_TYPE)0;  // AUDIT FIX: default to OB_15 for untracked
            info.setupGrade     = GRADE_D;                 // AUDIT FIX: conservative default for untracked
            string posComment = PositionGetString(POSITION_COMMENT);
            int brainPos = StringFind(posComment, "_B");
            if(brainPos < 0) brainPos = StringFind(posComment, "SMC_B");
            if(brainPos >= 0)
              {
               int bStart = (StringFind(posComment, "SMC_B") == brainPos) ? brainPos + 5 : brainPos + 2;
               info.brainBucketIdx = DecodeBase36Signed(posComment, bStart);
              }
            ulong setupEventId = 0;
            int eventPos = StringFind(posComment, "_E");
            if(eventPos >= 0)
               setupEventId = DecodeBase36(posComment, eventPos + 2);
            double evidenceWeight = (StringFind(posComment, "_M") >= 0)
                                    ? 1.0 / (double)MATRIX_MAX_CANDIDATE_COUNT : 1.0;

            if(EnsureTrackCapacity(m_trackCount + 1))
            {
               m_tracks[m_trackCount].ticket         = ticket;
               m_tracks[m_trackCount].tp1Level       = info.tp1Level;
               m_tracks[m_trackCount].tp2Level       = info.tp2Level;
                m_tracks[m_trackCount].initialLots    = info.initialLots;
                m_tracks[m_trackCount].openPrice      = info.openPrice;
                m_tracks[m_trackCount].posType        = info.posType;
                m_tracks[m_trackCount].initialRiskPrice = info.initialRiskPrice;
                m_tracks[m_trackCount].initialRiskMoney = info.initialRiskMoney;
                m_tracks[m_trackCount].maxFavorableR  = 0.0;
                m_tracks[m_trackCount].maxAdverseR    = 0.0;
                m_tracks[m_trackCount].maxSpreadPoints= info.maxSpreadPoints;
                m_tracks[m_trackCount].lastSeenTime   = TimeCurrent();
               m_tracks[m_trackCount].tp1CloseLots   = info.tp1CloseLots;
               m_tracks[m_trackCount].tp2CloseLots   = info.tp2CloseLots;
               m_tracks[m_trackCount].runnerLots     = info.runnerLots;
               m_tracks[m_trackCount].scaleOutEnabled= info.scaleOutEnabled;
               m_tracks[m_trackCount].tp1Done        = false;
               m_tracks[m_trackCount].bepDone        = info.bepDone;
               m_tracks[m_trackCount].milestoneDone  = false; // New tracking slot starts before the milestone
               m_tracks[m_trackCount].tp2Done        = false;
               m_tracks[m_trackCount].tp2Time        = 0;
               m_tracks[m_trackCount].trailActive    = false;
               m_tracks[m_trackCount].brainBucketIdx = info.brainBucketIdx;
               m_tracks[m_trackCount].setupEventId = setupEventId;
               m_tracks[m_trackCount].brainEvidenceWeight = evidenceWeight;
               m_tracks[m_trackCount].serverTP = info.tp;
               m_tracks[m_trackCount].targetSource = (int)TARGET_NONE;
               m_tracks[m_trackCount].needsTargetRecovery = true;
               m_tracks[m_trackCount].entryVariant = -1;
               m_tracks[m_trackCount].setupGrade = -1;
               int tPos = StringFind(posComment, "SMC_T");
               if(tPos >= 0)
                 {
                  m_tracks[m_trackCount].entryVariant = (int)StringToInteger(StringSubstr(posComment, tPos + 5));
                  int gPos = StringFind(posComment, "G", tPos + 5);
                  if(gPos >= 0)
                     m_tracks[m_trackCount].setupGrade = (int)StringToInteger(StringSubstr(posComment, gPos + 1));
                 }
               m_trackCount++;
               SaveTracks();
            }
         }
         return true;
   }
}

void COrderManager::PurgeStaleTracks()
{
   for(int k = m_trackCount - 1; k >= 0; k--)
   {
      bool stillOpen = false;
      for(int p = 0; p < PositionsTotal(); p++)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket > 0 && ticket == m_tracks[k].ticket &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic &&
            PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            stillOpen = true;
            break;
         }
      }
      // The close transaction can arrive after the position vanishes from
      // PositionsTotal(). Start the grace period at that observation, not at
      // the last management update; otherwise a long-held position is purged
      // before its final DEAL_ENTRY_OUT can consume its telemetry.
      if(stillOpen)
        {
         if(m_tracks[k].lastSeenTime < 0) m_tracks[k].lastSeenTime = TimeCurrent();
         continue;
        }
      if(m_tracks[k].lastSeenTime >= 0)
        {
         m_tracks[k].lastSeenTime = (datetime)(-((long)TimeCurrent()));
         SaveTracks();
         continue;
        }
      if(TimeCurrent() + m_tracks[k].lastSeenTime > 300)
      {
         Print("[YANSTD TRACK_PURGED] Ticket=", m_tracks[k].ticket,
               " | MissingSeconds=", (long)(TimeCurrent() + m_tracks[k].lastSeenTime));
         // Shift remaining tracks down
         for(int j = k; j < m_trackCount - 1; j++)
            m_tracks[j] = m_tracks[j + 1];
         m_trackCount--;
         SaveTracks();
      }
   }
}

//+------------------------------------------------------------------+
void COrderManager::RemoveTrack(ulong ticket)
{
   for(int k = m_trackCount - 1; k >= 0; k--)
   {
      if(m_tracks[k].ticket != ticket) continue;
      for(int j = k; j < m_trackCount - 1; j++)
         m_tracks[j] = m_tracks[j + 1];
      m_trackCount--;
      SaveTracks();
      return;
   }
}

//+------------------------------------------------------------------+
double COrderManager::GetTotalFloatingPnL()
{
   double total = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic &&
         PositionGetString(POSITION_SYMBOL) == Symbol())
         total += PositionGetDouble(POSITION_PROFIT);
   }
   return total;
}

//+------------------------------------------------------------------+
//| H4 — can this initial volume actually be scaled out 50/25/25 in    |
//| broker-legal volume steps?                                         |
//|                                                                   |
//| In the audited run, 1,325 of 3,509 trades (37.8%) hit             |
//| "Full position closed at TP1 because staged volumes were not       |
//| broker-valid". With XAUUSD at min-lot 0.01 / step 0.01, a 0.02 or  |
//| 0.03 lot position splits into 0.01 / 0.005 -- and 0.005 is below   |
//| the broker minimum. The scale-out plan was therefore impossible    |
//| from the moment the position was opened, and the EA discovered it  |
//| only at TP1, where its only remaining option was to abandon the    |
//| TP2/runner structure entirely.                                     |
//|                                                                   |
//| The check belongs at the ENTRY, not at the exit.                   |
//+------------------------------------------------------------------+
bool COrderManager::CanScaleOut(double initialLots, double tp1Pct, double tp2Pct, string symbol)
{
   string sym = (symbol == NULL || symbol == "") ? Symbol() : symbol;
   return CanScaleOut(sym, initialLots, tp1Pct, tp2Pct);
}

//+------------------------------------------------------------------+
#endif // YANSTD_ORDERMANAGER_MQH
