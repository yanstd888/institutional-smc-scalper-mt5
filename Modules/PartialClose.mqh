//+------------------------------------------------------------------+
//|                                                PartialClose.mqh  |
//|                      YANSTD EA — Partial Close & BEP Logic      |
//+------------------------------------------------------------------+
#ifndef YANSTD_PARTIALCLOSE_MQH
#define YANSTD_PARTIALCLOSE_MQH
#include "Defines.mqh"
#include "OrderManager.mqh"

enum ENUM_STAGED_FALLBACK
  {
   STAGED_FALLBACK_CLOSE_ALL = 0, // close the whole position at TP1 (legacy silent downgrade)
   STAGED_FALLBACK_HOLD_FULL = 1  // leave the position whole and let the runner/trail manage it
  };

class CPartialClose
{
private:
   COrderManager *m_om;
   CSignalDiagnostics *m_diag;
   int           m_stagedFallback;

public:
                 CPartialClose() : m_om(NULL), m_diag(NULL),
                                   m_stagedFallback(STAGED_FALLBACK_CLOSE_ALL) {}
   void Init(COrderManager *om) { m_om = om; }
   void SetDiagnostics(CSignalDiagnostics *diag) { m_diag = diag; }
   void SetStagedFallback(int mode) { m_stagedFallback = mode; }

   bool CheckEarlyBEP(SPositionInfo &pos, bool useEarlyBEP, double earlyBEPPips, int bepPlusPips)
     {
      if(!useEarlyBEP || pos.bepDone) return false;
      string sym = (pos.symbol != "") ? pos.symbol : Symbol();
      double pip = SymbolInfoDouble(sym, SYMBOL_POINT) * GetPipFactor(sym);
      if(pip <= 0) return false;

      double curPrice = (pos.posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      double profitPips = 0.0;
      if(pos.posType == POSITION_TYPE_BUY)
         profitPips = (curPrice - pos.openPrice) / pip;
      else
         profitPips = (pos.openPrice - curPrice) / pip;

      if(profitPips >= earlyBEPPips)
        {
         if(ExecuteBEP(pos, bepPlusPips))
           {
            LogMsg(LOG_LEVEL_INFO, "PartialClose",
                   StringFormat("Early BEP Activated @ +%s pips | Ticket=%I64u",
                                DoubleToString(profitPips, 1), pos.ticket));
            return true;
           }
        }
      return false;
     }

   bool CheckAndExecuteTP1(SPositionInfo &pos, bool useTP1, double tp1ClosePct,
                            int bepPlusPips, bool forceEarly = false)
     {
      if(!useTP1)     return false;
      if(pos.tp1Done) return false;
      if(!forceEarly && !IsTP1Hit(pos)) return false; // Opposing-POI guard may request an early close

      if(!pos.scaleOutEnabled)
        {
         string sym = (pos.symbol != "") ? pos.symbol : Symbol();
         double minLot = EffectiveBrokerMinLot(sym);
         double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
         if(pos.tp1CloseLots <= 0.0 || pos.lots <= minLot + 1e-8)
           {
            if(!pos.bepDone)
               ExecuteBEP(pos, bepPlusPips);
            pos.tp1Done = true;
            pos.trailActive = false;
            m_om.UpdateTrackState(pos);
            LogMsg(LOG_LEVEL_INFO, "PartialClose",
                   StringFormat("80-pip step on min-lot runner — SL to BE, no volume cut | Ticket=%I64u",
                                pos.ticket));
            return true;
           }

         if(m_stagedFallback == STAGED_FALLBACK_HOLD_FULL)
           {
            if(m_diag != NULL) m_diag.RecordStagedExitFailure();
            // Keep the whole position. Protect it at break-even and let the
            // trailing/structure logic run; do not discard the runner plan.
            if(!pos.bepDone)
              {
               if(!ExecuteBEP(pos, bepPlusPips) && !pos.bepDone)
                 {
                  LogMsg(LOG_LEVEL_WARN, "ExitPlan",
                         StringFormat("H4 — staged split impossible (lots=%.2f min=%.2f step=%.2f); holding full position but break-even move was rejected | ticket=%I64u",
                                      pos.lots, minLot, step, pos.ticket));
                  return false;
                 }
              }
            pos.tp1Done = true;
            pos.trailActive = true;
            m_om.UpdateTrackState(pos);
            LogMsg(LOG_LEVEL_ERROR, "ExitPlan",
                   StringFormat("H4 — staged volumes were not broker-valid (lots=%.2f min=%.2f step=%.2f); entry gate should have refused this size. Holding FULL position under trail | ticket=%I64u",
                                pos.lots, minLot, step, pos.ticket));
            return true;
           }

         LogMsg(LOG_LEVEL_INFO, "ExitPlan",
                StringFormat("Single-exit fallback: staged split unavailable (lots=%.2f min=%.2f step=%.2f); closing full volume at TP1 | ticket=%I64u",
                             pos.lots, minLot, step, pos.ticket));
         if(!m_om.ClosePosition(pos.ticket)) return false;
         pos.tp1Done = true;
         return true;
        }

      // Move SL first. If the broker rejects BEP, no volume has been closed and
      // the operation can be retried safely without repeated partial closes.
      if(!ExecuteBEP(pos, bepPlusPips) && !pos.bepDone) return false;

       double closeLot = pos.tp1CloseLots;
       // AUDIT FIX: validate remainder stays above broker minimum (mirrors TP2 logic)
       string sym = (pos.symbol != "") ? pos.symbol : Symbol();
       double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
       if(closeLot <= 0.0 || pos.lots - closeLot < minLot)
         {
          if(!m_om.ClosePosition(pos.ticket)) return false;
          pos.lots = 0.0;
          LogMsg(LOG_LEVEL_INFO, "PartialClose",
                 StringFormat("TP1 remainder below broker min (%s); full position closed | Ticket=%I64u",
                              DoubleToString(minLot, 2), pos.ticket));
         }
       else
         {
          if(!m_om.PartialClose(pos.ticket, closeLot)) return false;
          pos.lots = NormalizeDouble(pos.lots - closeLot, 8);
          LogMsg(LOG_LEVEL_INFO, "PartialClose",
                 StringFormat("TP1 %s%% of initial target closed | Ticket=%I64u ClosedLots=%.2f RemainingLots=%.2f",
                              DoubleToString(tp1ClosePct, 1), pos.ticket, closeLot, pos.lots));
         }

      pos.tp1Done = true;
      pos.trailActive = false;
      m_om.UpdateTrackState(pos);
      return true;
     }

   bool CheckAndExecuteTP2(SPositionInfo &pos)
     {
      if(pos.tp2Done)     return false;
      if(!IsTP2Hit(pos))  return false;

      double minLot = SymbolInfoDouble(pos.symbol, SYMBOL_VOLUME_MIN);
      double closeLot = pos.tp2CloseLots;
      if(closeLot <= 0.0 || pos.lots - closeLot < minLot)
        {
         if(!m_om.ClosePosition(pos.ticket)) return false;
         LogMsg(LOG_LEVEL_INFO, "PartialClose",
                StringFormat("TP2 volume no longer supports a valid runner; remaining position closed | Ticket=%I64u",
                             pos.ticket));
        }
      else
        {
         if(!m_om.PartialClose(pos.ticket, closeLot)) return false;
         pos.lots = NormalizeDouble(pos.lots - closeLot, 8);
         LogMsg(LOG_LEVEL_INFO, "PartialClose",
                StringFormat("TP2 25%% of initial target closed | Ticket=%I64u ClosedLots=%.2f RunnerLots=%.2f",
                             pos.ticket, closeLot, pos.lots));
        }
      pos.tp2Done = true;
      pos.tp2Time = TimeCurrent();
      pos.trailActive = true;
      m_om.UpdateTrackState(pos);
      return true;
     }

   bool ExecuteBEP(SPositionInfo &pos, int bepPlusPips)
     {
      string sym   = (pos.symbol != "") ? pos.symbol : Symbol();
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double off   = bepPlusPips * GetPipFactor(sym) * point;
      double newSL = 0;

      double bid  = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask  = SymbolInfoDouble(sym, SYMBOL_ASK);
      double spread   = MathMax(0.0, ask - bid);
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0) tickSize = point;
      long   stopsLvl  = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      long   freezeLvl = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
      double brokerDist = (double)MathMax(stopsLvl, freezeLvl) * point + spread + 2.0 * tickSize;

      if(pos.posType == POSITION_TYPE_BUY)
        {
         newSL = pos.openPrice + off;
         newSL = MathMin(newSL, bid - brokerDist);
         if(newSL < pos.openPrice) return false;
         if(pos.sl > 0 && newSL <= pos.sl) return false;
        }
      else
        {
         newSL = pos.openPrice - off;
         newSL = MathMax(newSL, ask + brokerDist);
         if(newSL > pos.openPrice) return false; // SELL mirror: never move the lock above entry
         if(pos.sl > 0 && newSL >= pos.sl) return false;
        }

      if(m_om.ModifySL(pos.ticket, newSL))
        {
         pos.sl          = newSL;
         pos.bepDone     = true;
         pos.trailActive = true;
         m_om.UpdateTrackState(pos);
         return true;
        }
      return false;
     }

   bool CheckMilestoneLock(SPositionInfo &pos, bool useMilestone, double triggerR, double lockR)
     {
      if(!useMilestone || pos.milestoneDone || pos.initialRiskPrice <= 0.0 ||
         pos.maxFavorableR < triggerR) return false;
      string sym = (pos.symbol != "") ? pos.symbol : Symbol();
      if(pos.maxFavorableR >= triggerR)
        {
         double point = SymbolInfoDouble(sym, SYMBOL_POINT);
         double off   = lockR * pos.initialRiskPrice;
          double newSL = (pos.posType == POSITION_TYPE_BUY) ? (pos.openPrice + off) : (pos.openPrice - off); // ponytail: single lock; add tiers only after evidence supports them.

          // AUDIT FIX: enforce broker minimum stop distance (mirrors ExecuteBEP)
          double bid  = SymbolInfoDouble(sym, SYMBOL_BID);
          double ask  = SymbolInfoDouble(sym, SYMBOL_ASK);
          double spread   = MathMax(0.0, ask - bid);
          double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
          if(tickSize <= 0.0) tickSize = point;
          long   stopsLvl  = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
          long   freezeLvl = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
          double brokerDist = (double)MathMax(stopsLvl, freezeLvl) * point + spread + 2.0 * tickSize;
          if(pos.posType == POSITION_TYPE_BUY)
             newSL = MathMin(newSL, bid - brokerDist);
          else
             newSL = MathMax(newSL, ask + brokerDist);

          bool shouldModify = (pos.posType == POSITION_TYPE_BUY) ? (newSL > pos.sl) : (newSL < pos.sl || pos.sl <= 0);
         if(shouldModify)
           {
            if(m_om.ModifySL(pos.ticket, newSL))
              {
               pos.sl            = newSL;
               pos.milestoneDone = true;
               pos.bepDone       = true;  // Fix M3: Lock out CheckEarlyBEP so it can't regress SL to Entry+2p
               pos.trailActive   = true;
               m_om.UpdateTrackState(pos);
               LogMsg(LOG_LEVEL_INFO, "PartialClose",
                      StringFormat("MFE lock %.2fR reached -> SL locked to +%.2fR | Ticket=%I64u",
                                   pos.maxFavorableR, lockR, pos.ticket));
               return true;
              }
           }
        }
      return false;
     }

   bool IsTP1Hit(const SPositionInfo &pos)
     {
      if(pos.tp1Level <= 0) return false;
      string sym = (pos.symbol != "") ? pos.symbol : Symbol();
      if(pos.posType == POSITION_TYPE_BUY)
         return SymbolInfoDouble(sym, SYMBOL_BID) >= pos.tp1Level;
      else
         return SymbolInfoDouble(sym, SYMBOL_ASK) <= pos.tp1Level;
     }

   bool IsTP2Hit(const SPositionInfo &pos)
     {
      if(pos.tp2Level <= 0) return false;
      string sym = (pos.symbol != "") ? pos.symbol : Symbol();
      if(pos.posType == POSITION_TYPE_BUY)
         return SymbolInfoDouble(sym, SYMBOL_BID) >= pos.tp2Level;
      else
         return SymbolInfoDouble(sym, SYMBOL_ASK) <= pos.tp2Level;
     }
};

#endif // YANSTD_PARTIALCLOSE_MQH
