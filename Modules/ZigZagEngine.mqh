//+------------------------------------------------------------------+
//|                                                 ZigZagEngine.mqh |
//|                    YANSTD EA — Multi-Timeframe ZigZag Engine     |
//|                    (M15 HTF Bias, M5 MTF POI, M3 LTF CHoCH)      |
//|                                   v3.11  |  2026-08-30           |
//+------------------------------------------------------------------+
#ifndef YANSTD_ZIGZAGENGINE_MQH
#define YANSTD_ZIGZAGENGINE_MQH

#include "Defines.mqh"

class CZigZagEngine
{
private:
   string m_symbol;

   // NOTE: unlike the classic MetaTrader ZigZag indicator, `backstep` here is
   // only folded into `confirmationBars` (how many closed bars must exist
   // before a candidate pivot can be evaluated). It is NOT used as a
   // minimum-bar-distance filter between two same-direction pivots. This is
   // a deliberate simplification of the original ZigZag semantics, not an
   // oversight -- documented so it isn't "fixed" into an accidental behavior
   // change later without realizing the difference is intentional.
   //
   // AUDIT H2: ZigZag halfD = max(2, depth/2) is NOT the same knob as
   // InpStructureSwingWing (QML/King = 2) or FVG structure wings (LTF/H1 = 3,
   // H4 = 2). ZigZag Depth is a structure-scale parameter per TF (M15=12,
   // M5=8, M3=5). Do not silently replace halfD with InpStructureSwingWing.
   bool ScanLoaded(const MqlRates &rates[], int copied, int depth, int deviation, int backstep,
                   SMC_SwingPoint &lastHigh, SMC_SwingPoint &prevHigh,
                   SMC_SwingPoint &lastLow,  SMC_SwingPoint &prevLow)
   {
      int halfD = MathMax(2, depth / 2);
      int confirmationBars = MathMax(halfD + 1, backstep + 1);
      double minDeviation = MathMax(0, deviation) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int highs = 0, lows = 0;
      for(int i = confirmationBars; i < copied - halfD && (highs < 2 || lows < 2); i++)
        {
         bool isPeak = IsFractalPivot(rates, copied, i, halfD, halfD, true);
         bool isTrough = IsFractalPivot(rates, copied, i, halfD, halfD, false);
         double neighbourHigh = -DBL_MAX, neighbourLow = DBL_MAX;
         for(int j = 1; j <= halfD; j++)
           {
            neighbourHigh = MathMax(neighbourHigh, MathMax(rates[i+j].high, rates[i-j].high));
            neighbourLow  = MathMin(neighbourLow,  MathMin(rates[i+j].low,  rates[i-j].low));
           }
         if(isPeak && rates[i].high - neighbourHigh < minDeviation) isPeak = false;
         if(isTrough && neighbourLow - rates[i].low < minDeviation) isTrough = false;
         if(isPeak && highs < 2)
           {
            SMC_SwingPoint p;
            p.price = rates[i].high; p.time = rates[i].time; p.bar = i; p.isHigh = true;
            if(highs == 0) lastHigh = p; else prevHigh = p;
            highs++;
           }
         if(isTrough && lows < 2)
           {
            SMC_SwingPoint p;
            p.price = rates[i].low; p.time = rates[i].time; p.bar = i; p.isHigh = false;
            if(lows == 0) lastLow = p; else prevLow = p;
            lows++;
           }
        }
      return (highs == 2 && lows == 2);
   }

public:
   CZigZagEngine() : m_symbol("") {}

   void Init(string symbol)
   {
      m_symbol = symbol;
   }

   // Returns the two newest fully-confirmed highs and lows.  Structure logic
   // must compare a sequence of pivots; a single latest high/low is not enough
   // to distinguish continuation (BOS) from reversal (CHoCH).
   bool GetStructureSwings(ENUM_TIMEFRAMES tf, int depth, int deviation, int backstep,
                           SMC_SwingPoint &lastHigh, SMC_SwingPoint &prevHigh,
                           SMC_SwingPoint &lastLow,  SMC_SwingPoint &prevLow)
   {
      lastHigh.price = prevHigh.price = lastLow.price = prevLow.price = 0.0;
      lastHigh.time  = prevHigh.time  = lastLow.time  = prevLow.time  = 0;
      lastHigh.bar   = prevHigh.bar   = lastLow.bar   = prevLow.bar   = -1;
      lastHigh.isHigh = prevHigh.isHigh = true;
      lastLow.isHigh  = prevLow.isHigh  = false;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int firstWindow = MathMin(600, MathMax(120, depth * 12));
      int copied = CopyRates(m_symbol, tf, 0, firstWindow, rates);
      if(copied < MathMax(30, depth * 3)) return false;
      if(ScanLoaded(rates, copied, depth, deviation, backstep,
                    lastHigh, prevHigh, lastLow, prevLow)) return true;
      if(firstWindow >= 600) return false;
      copied = CopyRates(m_symbol, tf, 0, 600, rates);
      if(copied < MathMax(30, depth * 3)) return false;
      return ScanLoaded(rates, copied, depth, deviation, backstep,
                        lastHigh, prevHigh, lastLow, prevLow);
   }

};

#endif // YANSTD_ZIGZAGENGINE_MQH
