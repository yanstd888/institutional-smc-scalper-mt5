//+------------------------------------------------------------------+
//|                                              SessionManager.mqh  |
//|                      YANSTD EA — Session Detection               |
//+------------------------------------------------------------------+
#ifndef YANSTD_SESSIONMANAGER_MQH
#define YANSTD_SESSIONMANAGER_MQH
#include "Defines.mqh"

class CSessionManager
{
private:
   int               m_testerWinterOffset;
   bool              m_testerUseEuropeanDST;

public:
   // AUDIT FIX (#3): made public so other modules (e.g. CNewsFilter) can call
   // the single, hour-aware DST implementation instead of duplicating a
   // day-only approximation of their own — the two used to disagree by a
   // few hours across the two yearly DST transition days.
   bool IsEuropeanDST(datetime serverTime) const
     {
      if(!m_testerUseEuropeanDST) return false;
      MqlDateTime dt;
      TimeToStruct(serverTime, dt);
      if(dt.mon < 3 || dt.mon > 10) return false;
      if(dt.mon > 3 && dt.mon < 10) return true;
      int lastSunday = LastSundayOfMonth(dt.year, dt.mon);
      if(dt.mon == 3)
         return (dt.day > lastSunday || (dt.day == lastSunday && dt.hour >= m_testerWinterOffset + 1));
      return (dt.day < lastSunday || (dt.day == lastSunday && dt.hour < m_testerWinterOffset + 2));
     }

                     CSessionManager() : m_testerWinterOffset(2), m_testerUseEuropeanDST(true) {}
   void              Init(int testerWinterOffset = 2, bool testerUseEuropeanDST = true)
     {
      m_testerWinterOffset   = testerWinterOffset;
      m_testerUseEuropeanDST = testerUseEuropeanDST;
     }

   // True simulated UTC based on historical tick/bar time
   datetime GetSimulatedUTC() const
     {
      return ConvertServerToUTC(TimeCurrent());
     }

   int GetConfiguredTesterOffsetHours(datetime serverTime) const
     {
      return m_testerWinterOffset + (IsEuropeanDST(serverTime) ? 1 : 0);
     }

   datetime ConvertServerToUTC(datetime serverTime) const
     {
      if(!MQLInfoInteger(MQL_TESTER))
        {
         datetime brokerNow = TimeTradeServer();
         if(brokerNow <= 0) brokerNow = TimeCurrent();
         datetime gmtNow = TimeGMT();
         if(gmtNow <= 0)
            return serverTime - GetConfiguredTesterOffsetHours(serverTime) * 3600;

         // M5: TimeGMT()/TimeTradeServer() only ever measure TODAY's broker-GMT
         // offset. Reusing that single reading to convert an arbitrary
         // historical serverTime is wrong by a full hour for any deal that
         // falls on the other side of a DST transition from "now" (e.g.
         // converting a July deal's close time while running in January, or a
         // January deal's close time while running in July) -- exactly the
         // "session history live" drift this fixes. Instead of treating the
         // live reading as a universal historical offset, back it out to the
         // broker's winter (non-DST) baseline using the same configured
         // European-DST calendar the tester branch already relies on
         // (IsEuropeanDST()/m_testerUseEuropeanDST), then re-apply DST for the
         // date actually being converted -- not for today. When serverTime IS
         // "now" (the overwhelmingly common case: session detection, day/
         // session rollover, trade-time filters) IsEuropeanDST(serverTime)
         // equals IsEuropeanDST(brokerNow), so this reduces to exactly the old
         // live auto-detected offset -- no behavior change there.
         int liveOffsetSeconds   = (int)MathRound((double)(brokerNow - gmtNow) / 1800.0) * 1800;
         int winterOffsetSeconds = liveOffsetSeconds - (IsEuropeanDST(brokerNow)  ? 3600 : 0);
         int histOffsetSeconds   = winterOffsetSeconds + (IsEuropeanDST(serverTime) ? 3600 : 0);
         return serverTime - histOffsetSeconds;
        }
      else
        {
         int serverOffsetHours = GetConfiguredTesterOffsetHours(serverTime);
         return serverTime - serverOffsetHours * 3600;
        }
     }

   int NYShift(datetime utc) { return IsUSDST(utc) ? 0 : 1; }

   ENUM_SESSION_TYPE GetSessionAtUTC(datetime utc)
     {
      MqlDateTime dt;
      TimeToStruct(utc, dt);
      int h  = dt.hour;
      int ny = NYShift(utc); // NY-anchored boundaries shift by one hour in US winter
      // London+NY Overlap: 13:00-17:00 UTC (summer) / 14:00-18:00 (winter)
      if(h >= 13 + ny && h < 17 + ny) return SESSION_OVERLAP;
      // Pure NY session: 17:00-22:00 UTC (summer) / 18:00-23:00 (winter)
      if(h >= 17 + ny && h < 22 + ny) return SESSION_NEWYORK;
      // London session: 08:00 UTC until the overlap begins
      if(h >=  8 && h < 13 + ny) return SESSION_LONDON;
      // Asia: everything else (22/23:00 -> 08:00 UTC)
      return SESSION_ASIA;
     }

   ENUM_SESSION_TYPE GetCurrentSession()
     {
      return GetSessionAtUTC(GetSimulatedUTC());
     }

   //--- ICT Killzone (XAUUSD): London 07-10 UTC, NY 12-14 UTC (fixed GMT per ICT spec)
   // Wider session (08-13 London, 13-17 Overlap) is NOT a killzone — killzone is narrower.
   bool IsKillzoneAtUTC(datetime utc) const
     {
      MqlDateTime dt; TimeToStruct(utc, dt);
      int h = dt.hour;
      return (h >= 7 && h < 10) || (h >= 12 && h < 14);
     }
   ENUM_SESSION_TYPE GetKillzoneAtUTC(datetime utc) const
     {
      if(!IsKillzoneAtUTC(utc)) return SESSION_NONE;
      MqlDateTime dt; TimeToStruct(utc, dt);
      int h = dt.hour;
      if(h >= 7 && h < 10) return SESSION_LONDON_KZ;
      if(h >= 12 && h < 14) return SESSION_NY_KZ;
      return SESSION_NONE;
     }
   bool IsKillzoneNow() const { return IsKillzoneAtUTC(GetSimulatedUTC()); }

   bool HourInRolloverHole(const int hour, const int holeStart, const int holeEnd) const
     {
      if(holeStart == holeEnd) return false;
      if(holeStart < holeEnd)
         return (hour >= holeStart && hour < holeEnd);
      return (hour >= holeStart || hour < holeEnd);
     }

   bool IsFridayCloseWindow(const int closeHourUTC, MqlDateTime &dt)
     {
      TimeToStruct(GetSimulatedUTC(), dt);
      return (dt.day_of_week == 5 && dt.hour >= closeHourUTC);
     }

   bool IsTradeTimeAllowed(int startHour, int endHour, int fridayCutoffHour,
                           ENUM_TIME_FILTER_MODE mode = TIME_FILTER_WINDOW,
                           int holeStartUTC = 20, int holeEndUTC = 23)
     {
      MqlDateTime dt;
      TimeToStruct(GetSimulatedUTC(), dt);

      if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
      if(dt.day_of_week == 5 && dt.hour >= fridayCutoffHour) return false;

      if(mode == TIME_FILTER_ROLLOVER_HOLE)
         return !HourInRolloverHole(dt.hour, holeStartUTC, holeEndUTC);

      if(startHour < endHour)
         return !(dt.hour < startHour || dt.hour >= endHour);
      return !(dt.hour < startHour && dt.hour >= endHour);
     }

};

#endif // YANSTD_SESSIONMANAGER_MQH
