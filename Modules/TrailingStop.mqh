//+------------------------------------------------------------------+
//|                                               TrailingStop.mqh   |
//|                YANSTD EA — Confirmed-Swing Runner Trailing      |
//+------------------------------------------------------------------+
#ifndef YANSTD_TRAILINGSTOP_MQH
#define YANSTD_TRAILINGSTOP_MQH
#include "Defines.mqh"
#include "OrderManager.mqh"

class CTrailingStop
{
private:
   COrderManager  *m_om;
   ENUM_TIMEFRAMES m_tf;
   int             m_leftBars;
   int             m_rightBars;
   double          m_bufferPips;
   int             m_atrPeriod;        // ATR Engine: period for dynamic trail distance
   double          m_trailDistATRMult; // ATR Engine: runner trail distance = ATR * this
   datetime        m_cachedBarTime;
   double          m_latestSwingLow;
   double          m_latestSwingHigh;
   datetime        m_latestSwingLowTime;
   datetime        m_latestSwingHighTime;

   bool RefreshConfirmedSwings(string symbol)
     {
      datetime barTime = iTime(symbol, m_tf, 0);
      if(barTime <= 0) return false;
      if(barTime == m_cachedBarTime) return true;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int need = MathMax(60, m_leftBars + m_rightBars + 20);
      int copied = CopyRates(symbol, m_tf, 0, need, rates);
      if(copied < m_leftBars + m_rightBars + 3) return false;
      m_cachedBarTime = barTime;

      m_latestSwingLow      = 0.0;
      m_latestSwingHigh     = 0.0;
      m_latestSwingLowTime  = 0;
      m_latestSwingHighTime = 0;

      // Series index 0 is the open candle. Candidate starts after all required
      // right-side candles have closed, so no unconfirmed/repainting pivot is used.
      for(int i = m_rightBars + 1; i < copied - m_leftBars; i++)
        {
         bool isLow  = true;
         bool isHigh = true;

         // AUDIT FIX: allow exact equal lows/highs (double bottoms/tops) as valid pivots
         for(int r = 1; r <= m_rightBars; r++)
           {
            if(rates[i].low  > rates[i-r].low)  isLow  = false;
            if(rates[i].high < rates[i-r].high) isHigh = false;
           }
         for(int l = 1; l <= m_leftBars; l++)
           {
            if(rates[i].low  > rates[i+l].low)  isLow  = false;
            if(rates[i].high < rates[i+l].high) isHigh = false;
           }

         if(isLow && m_latestSwingLowTime == 0)
           {
            m_latestSwingLow     = rates[i].low;
            m_latestSwingLowTime = rates[i].time;
           }
         if(isHigh && m_latestSwingHighTime == 0)
           {
            m_latestSwingHigh     = rates[i].high;
            m_latestSwingHighTime = rates[i].time;
           }
         if(m_latestSwingLowTime > 0 && m_latestSwingHighTime > 0) break;
        }
      return true;
     }

public:
               CTrailingStop() : m_om(NULL), m_tf(PERIOD_M5),
                                  m_leftBars(2), m_rightBars(2), m_bufferPips(10.0),
                                  m_atrPeriod(14), m_trailDistATRMult(1.50),
                                  m_cachedBarTime(0), m_latestSwingLow(0.0), m_latestSwingHigh(0.0),
                                  m_latestSwingLowTime(0), m_latestSwingHighTime(0) {}

   void Init(COrderManager *om)
     {
      m_om = om;
     }

   // ATR Engine wiring (called from OnInit).
   void SetATRParams(int atrPeriod, double trailDistATRMult)
     {
      m_atrPeriod        = (atrPeriod > 0)          ? atrPeriod        : 14;
      m_trailDistATRMult = (trailDistATRMult > 0.0) ? trailDistATRMult : 1.50;
     }

   void SetParams(ENUM_TIMEFRAMES tf, int leftBars, int rightBars, double bufferPips)
     {
      m_tf          = tf;
      m_leftBars    = leftBars;
      m_rightBars   = rightBars;
      m_bufferPips  = bufferPips;
      m_cachedBarTime = 0;
     }

   void Process(SPositionInfo &pos)
     {
      if(m_om == NULL || !pos.tp2Done || !pos.trailActive || pos.tp2Time <= 0) return;
      string sym = (pos.symbol != "") ? pos.symbol : Symbol();
      if(!RefreshConfirmedSwings(sym)) return;

      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double pip   = point * GetPipFactor(sym);
      double atr    = ReadATRAtShift(sym, m_tf, m_atrPeriod, 1); // H4: use formation-shift ATR, not live
      double buffer = (atr > 0.0) ? atr * m_trailDistATRMult : m_bufferPips * pip;
      double newSL = 0.0;

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
         if(m_latestSwingLowTime <= pos.tp2Time || m_latestSwingLow <= 0.0) return;
         newSL = m_latestSwingLow - buffer;
         newSL = MathMin(newSL, bid - brokerDist);
         if(newSL >= bid || (pos.sl > 0.0 && newSL <= pos.sl)) return;
        }
      else if(pos.posType == POSITION_TYPE_SELL)
        {
         if(m_latestSwingHighTime <= pos.tp2Time || m_latestSwingHigh <= 0.0) return;
         newSL = m_latestSwingHigh + buffer;
         newSL = MathMax(newSL, ask + brokerDist);
         if(newSL <= ask || (pos.sl > 0.0 && newSL >= pos.sl)) return;
        }

      if(m_om.ModifySL(pos.ticket, newSL))
        {
         pos.sl = newSL;
         m_om.UpdateTrackState(pos);
         Print("YANSTD RunnerTrail: Confirmed ",
               EnumToString(m_tf), " ",
               (pos.posType == POSITION_TYPE_BUY ? "swing low" : "swing high"),
               " applied | Ticket=", pos.ticket, " | NewSL=", DoubleToString(newSL, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)));
        }
     }
};

#endif // YANSTD_TRAILINGSTOP_MQH
