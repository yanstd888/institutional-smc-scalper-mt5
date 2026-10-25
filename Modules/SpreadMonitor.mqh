//+------------------------------------------------------------------+
//|                                               SpreadMonitor.mqh  |
//|              YANSTD EA — Dynamic Spread Auto-Detection Engine    |
//|                                    v1.0  |  2026-08-31           |
//+------------------------------------------------------------------+
#ifndef YANSTD_SPREADMONITOR_MQH
#define YANSTD_SPREADMONITOR_MQH
#include "Defines.mqh"

class CSpreadMonitor
  {
private:
   int      m_buffer[];
   int      m_capacity;
   int      m_count;      // number of valid samples currently stored (<= m_capacity)
   int      m_head;       // next write index
   long     m_sum;        // running sum of samples currently in the buffer
   long     m_sumSq;      // running sum of squares of samples currently in the buffer
   int      m_lastRaw;    // most recent raw spread sample (points)

public:
            CSpreadMonitor() : m_capacity(0), m_count(0), m_head(0),
                                m_sum(0), m_sumSq(0), m_lastRaw(0) {}

   void Init(int capacity = 200)
     {
      m_capacity = MathMax(20, capacity);
      ArrayResize(m_buffer, m_capacity);
      ArrayInitialize(m_buffer, 0);
      m_count   = 0;
      m_head    = 0;
      m_sum     = 0;
      m_sumSq   = 0;
      m_lastRaw = 0;
     }

   // Feed one live tick's spread (points). O(1).
   void Sample(int spreadPoints)
     {
      if(m_capacity <= 0) Init(200);
      if(spreadPoints < 0) spreadPoints = 0;
      m_lastRaw = spreadPoints;

      if(m_count < m_capacity)
        {
         m_buffer[m_head] = spreadPoints;
         m_sum   += spreadPoints;
         m_sumSq += (long)spreadPoints * (long)spreadPoints;
         m_count++;
        }
      else
        {
         int old = m_buffer[m_head];
         m_sum   += spreadPoints - old;
         m_sumSq += (long)spreadPoints * (long)spreadPoints - (long)old * (long)old;
         m_buffer[m_head] = spreadPoints;
        }
      m_head = (m_head + 1) % m_capacity;
     }

   double GetMean() const
     {
      if(m_count <= 0) return 0.0;
      return (double)m_sum / (double)m_count;
     }

   double GetStdDev() const
     {
      if(m_count <= 1) return 0.0;
      double mean = GetMean();
      double variance = ((double)m_sumSq / (double)m_count) - (mean * mean);
      if(variance < 0.0) variance = 0.0; // guard against fp rounding
      return MathSqrt(variance);
     }

   // Dynamic threshold in points: mean + k*stddev, clamped to [floorPts, capPts].
   // Falls back to capPts until enough samples have been collected so the
   // EA behaves exactly like the static input during warm-up.
   double GetDynamicThreshold(double kMultiplier, int floorPts, int capPts, int minSamples = 30) const
     {
      if(capPts < floorPts) capPts = floorPts;
      if(m_count < minSamples) return (double)capPts;

      double raw = GetMean() + MathMax(0.0, kMultiplier) * GetStdDev();
      return Clamp(raw, (double)floorPts, (double)capPts);
     }

   void Reset()
     {
      m_count = 0;
      m_head  = 0;
      m_sum   = 0;
      m_sumSq = 0;
      if(m_capacity > 0) ArrayInitialize(m_buffer, 0);
     }
  };

#endif // YANSTD_SPREADMONITOR_MQH
//+------------------------------------------------------------------+
