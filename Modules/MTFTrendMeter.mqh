//+------------------------------------------------------------------+
//|                                             MTFTrendMeter.mqh    |
//|                      YANSTD EA — Multi-Timeframe Trend Scoring   |
//+------------------------------------------------------------------+
#ifndef YANSTD_MTFTRENDMETER_MQH
#define YANSTD_MTFTRENDMETER_MQH
#include "Defines.mqh"

class CMTFTrendMeter
{
private:
   string          m_symbol;
   SMTFResult      m_result;
   ENUM_TIMEFRAMES m_tfs[6];

   SMTFData MakeMTFData(double score)
     {
      SMTFData d;
      d.bullPct = score;
      if(score >= 70)       { d.label = "BULL"; d.clr = clrLimeGreen; }
      else if(score >= 56)  { d.label = "BULL"; d.clr = clrGreen; }
      else if(score >= 45)  { d.label = "NEUT"; d.clr = clrGray; }
      else if(score >= 30)  { d.label = "BEAR"; d.clr = clrOrange; }
      else                  { d.label = "BEAR"; d.clr = clrRed; }
      return d;
     }

public:
   CMTFTrendMeter() {}
   ~CMTFTrendMeter() {}

   void Init(string symbol)
     {
      m_symbol = symbol;
      m_tfs[0] = PERIOD_M3;
      m_tfs[1] = PERIOD_M5;
      m_tfs[2] = PERIOD_M15;
      m_tfs[3] = PERIOD_M30;
      m_tfs[4] = PERIOD_H1;
      m_tfs[5] = PERIOD_H4;
     }

   void Calculate()
     {
      double s0 = ScoreTF(0);
      double s1 = ScoreTF(1);
      double s2 = ScoreTF(2);
      double s3 = ScoreTF(3);
      double s4 = ScoreTF(4);
      double s5 = ScoreTF(5);

      m_result.m3  = MakeMTFData(s0);
      m_result.m5  = MakeMTFData(s1);
      m_result.m15 = MakeMTFData(s2);
      m_result.m30 = MakeMTFData(s3);
      m_result.h1  = MakeMTFData(s4);
      m_result.h4  = MakeMTFData(s5);

      double c = s0*0.10 + s1*0.10 + s2*0.25 + s3*0.20 + s4*0.20 + s5*0.15;
      m_result.confluence = c;
      m_result.bullPct    = c;    // alias
      m_result.bias       = GetBias(c);
      m_result.biasLabel  = GetBiasLabel(c);
     }

   SMTFResult GetResult() { return m_result; }

   double ScoreTF(int tfIdx)
     {
      if(tfIdx < 0 || tfIdx >= 6) return 50.0;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, m_tfs[tfIdx], 1, 10, rates);
      if(copied < 10) return 50.0;

      // AUDIT FIX (symmetric scoring): the previous formula started from a
      // base of 10 and only ever ADDED points for bullish evidence, with no
      // equivalent subtraction for bearish evidence. That made a genuinely
      // neutral/choppy market score far below 50 (the "NEUTRAL" midpoint
      // used by GetBias()/GetBiasLabel()), biasing the whole confluence
      // score toward SELL in sideways conditions. The rebuilt formula below
      // starts from 50 and applies each component as a signed +/- swing of
      // the SAME magnitude for the opposite condition, so a perfectly
      // bullish tape scores 100, a perfectly bearish tape scores 0, and a
      // genuinely neutral/mixed tape scores back at ~50.
      double score = 50.0; // Base neutral score

      // 1. Structure Momentum: net direction of the last 3 closed candles.
      //    Range -16..+16 (was 0..+30, one-sided).
      int bullCandles = 0, bearCandles = 0;
      for(int i = 0; i < 3; i++)
        {
         if(rates[i].close > rates[i].open)      bullCandles++;
         else if(rates[i].close < rates[i].open) bearCandles++;
        }
      score += ((bullCandles - bearCandles) / 3.0) * 16.0;

      // 2. Market Structure: higher-high/higher-low strength net of
      //    lower-high/lower-low strength across the last 8 pairs.
      //    Range -20..+20 (was 0..+35, one-sided).
      int hh = 0, hl = 0, lh = 0, ll = 0;
      for(int i = 0; i < 8; i++)
        {
         if(rates[i].high > rates[i+1].high)      hh++;
         else if(rates[i].high < rates[i+1].high) lh++;
         if(rates[i].low  > rates[i+1].low)       hl++;
         else if(rates[i].low  < rates[i+1].low)  ll++;
        }
      double upStrength   = (double)MathMin(hh, hl);   // uptrend needs BOTH higher highs and higher lows
      double downStrength = (double)MathMin(lh, ll);    // downtrend needs BOTH lower highs and lower lows
      score += ((upStrength - downStrength) / 8.0) * 20.0;

      // 3. Price Position in the 10-bar range, centered on the midpoint.
      //    Range -14..+14 (was 0..+25, one-sided).
      double maxH = rates[0].high, minL = rates[0].low;
      for(int i = 1; i < MathMin(10, copied); i++) // AUDIT FIX: defensive bound against array overread
        {
         if(rates[i].high > maxH) maxH = rates[i].high;
         if(rates[i].low  < minL) minL = rates[i].low;
        }
      double rng = maxH - minL;
      if(rng > 0.0)
        {
         double relPos = (rates[0].close - minL) / rng; // 0 = bottom of range, 1 = top
         score += (relPos - 0.5) * 28.0;
        }

      return MathMax(0.0, MathMin(100.0, score));
     }

   string GetBiasLabel(double c)
     {
      if(c < 30)  return "STRONG SELL";
      if(c < 45)  return "SELL";
      if(c <= 55) return "NEUTRAL";
      if(c <= 70) return "BUY";
      return "STRONG BUY";
     }

   ENUM_TREND_BIAS GetBias(double c)
     {
      if(c < 30)  return BIAS_STRONG_BEAR;
      if(c < 45)  return BIAS_BEAR;
      if(c <= 55) return BIAS_NEUTRAL;
      if(c <= 70) return BIAS_BULL;
      return BIAS_STRONG_BULL;
     }

};

#endif // YANSTD_MTFTRENDMETER_MQH
