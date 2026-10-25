//+------------------------------------------------------------------+
//|                                              RiskCalculator.mqh  |
//|                      YANSTD EA — Lot Size & Risk Calculation     |
//+------------------------------------------------------------------+
#ifndef YANSTD_RISKCALCULATOR_MQH
#define YANSTD_RISKCALCULATOR_MQH
#include "Defines.mqh"

class CRiskCalculator
{
private:
   string m_symbol;
   datetime m_lastMinLotWarning;
   ENUM_LOT_SIZE_STATUS m_lastStatus;
   bool m_rejectBelowMinLot;

public:
   CRiskCalculator() : m_symbol(""), m_lastMinLotWarning(0),
                       m_lastStatus(LOT_STATUS_OK), m_rejectBelowMinLot(false) {}
   ENUM_LOT_SIZE_STATUS LastLotStatus() const { return m_lastStatus; }
   void SetRejectBelowMinLot(const bool reject) { m_rejectBelowMinLot = reject; }

   void Init(string symbol)
     {
      m_symbol = (symbol == NULL || symbol == "") ? Symbol() : symbol;
     }

   double CalcLotSize(double riskPct, double slPips, string symbol = NULL,
                      double entryPrice = 0.0, ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY)
     {
      string sym = (symbol == NULL || symbol == "") ? m_symbol : symbol;
      if(sym == "") sym = Symbol();
      m_lastStatus = LOT_STATUS_OK;
      if(slPips <= 0)
        {
         m_lastStatus = LOT_STATUS_INVALID;
         return 0.0;
        }

      double balance   = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                                 AccountInfoDouble(ACCOUNT_EQUITY));
      double riskAmt   = balance * riskPct / 100.0;
      double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(balance <= 0.0 || riskAmt <= 0.0 || point <= 0.0)
        {
         m_lastStatus = LOT_STATUS_INVALID;
         return 0.0;
        }

      double slPoints  = slPips * GetPipFactor(sym);
      double slDistance = slPoints * point;
      double referencePrice = entryPrice;
      if(referencePrice <= 0.0)
         referencePrice = (orderType == ORDER_TYPE_SELL)
                          ? SymbolInfoDouble(sym, SYMBOL_BID)
                          : SymbolInfoDouble(sym, SYMBOL_ASK);

      // OrderCalcProfit uses the broker's contract size, tick-value conversion
      // and account currency. This is more portable than relying solely on a
      // sometimes stale/zero SYMBOL_TRADE_TICK_VALUE immediately after login.
      double lossAtOneLot = 0.0;
      double valPerLot = 0.0;
      if(referencePrice > 0.0 &&
         OrderCalcProfit(orderType, sym, 1.0, referencePrice,
                         (orderType == ORDER_TYPE_SELL)
                         ? referencePrice + slDistance : referencePrice - slDistance,
                         lossAtOneLot))
         valPerLot = MathAbs(lossAtOneLot);

      // Fallback for symbols/brokers which temporarily reject OrderCalcProfit.
      if(valPerLot <= 0.0)
        {
         double tickVal = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
         if(tickVal <= 0.0) tickVal = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize > 0.0 && tickVal > 0.0)
            valPerLot = (slDistance / tickSize) * tickVal;
        }
      if(valPerLot <= 0)
        {
         m_lastStatus = LOT_STATUS_FALLBACK;
         LogSystemWarning("RiskCalculator", "CalcLotSize",
                          "LOT_FALLBACK calculator metadata missing -> 0.01");
         return EnforceBrokerMinLot(YANSTD_HARD_MIN_LOT, sym);
        }

      double rawLot = riskAmt / valPerLot;
      double minLot = EffectiveBrokerMinLot(sym);
      double rounded = RoundLotToStep(rawLot, sym);

      // Entry already passed structurally: never drop a positive risk-lot
      // below the broker floor (0.01 on this account / custom XAU symbol).
      if(rawLot > 0.0 && rawLot < minLot)  // AUDIT FIX: check rawLot not rounded (rounded is always >= minLot)
        {
         // AUDIT FIX M-3: optional reject instead of silently exceeding InpRiskPercent.
         if(m_rejectBelowMinLot)
           {
            m_lastStatus = LOT_STATUS_INVALID;
            LogSystemWarning("RiskCalculator", "CalcLotSize",
                             StringFormat("Ditolak: risk-lot %.5f < broker min %.2f, dan InpRejectBelowMinLot=true",
                                          rawLot, minLot));
            return 0.0;
           }
         double clamped = EnforceBrokerMinLot(minLot, sym);
         m_lastStatus = LOT_STATUS_CLAMP;
         datetime nowC = TimeCurrent();
         if(m_lastMinLotWarning == 0 || nowC - m_lastMinLotWarning >= 60)
           {
            LogSystemWarning("RiskCalculator", "CalcLotSize",
                             StringFormat("LOT_CLAMP valid %.5f -> broker min %.2f "
                                          "(requested risk %.3f%%, balance=%.2f, SL=%.1fp)",
                                          rawLot, clamped, riskPct, balance, slPips));
            m_lastMinLotWarning = nowC;
           }
         return clamped;
        }
      return rounded;
     }

   // Full min+max+step clamp via EnforceBrokerMinLot / NormalizeLotToBrokerLimits.
   // Name kept for call-site compatibility; NormalizeLotForRisk is the accurate alias.
   double NormalizeLotForRisk(double lot, string symbol = NULL)
     {
      string sym = (symbol == NULL || symbol == "") ? m_symbol : symbol;
      if(sym == "") sym = Symbol();
      if(lot <= 0.0)
         return 0.0;
      return EnforceBrokerMinLot(lot, sym);
     }

   double RoundLotToStep(double lot, string symbol = NULL)
     {
      return NormalizeLotForRisk(lot, symbol);
     }

};

#endif // YANSTD_RISKCALCULATOR_MQH
