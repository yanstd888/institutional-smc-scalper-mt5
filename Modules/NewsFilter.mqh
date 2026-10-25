//+------------------------------------------------------------------+
//|                                                NewsFilter.mqh    |
//|                      YANSTD EA — Calendar News Filter            |
//+------------------------------------------------------------------+
#ifndef YANSTD_NEWSFILTER_MQH
#define YANSTD_NEWSFILTER_MQH
#include "Defines.mqh"
#include "SessionManager.mqh"

class CNewsFilter
{
private:
   SNewsEvent m_events[MAX_NEWS];
   int        m_count;
   bool       m_highOnly;
   int        m_preMins;
   int        m_postMins;
   datetime   m_lastRefresh;
   bool       m_calendarAvailable;

   //---- M4: synthetic calendar for the Strategy Tester ------------------
   bool       m_testerSimulate;   // build synthetic events in the tester
   int        m_testerOffsetHrs;  // server = UTC + this (tester assumption)
   bool       m_testerUseDST;     // +1h during European summer
   datetime   m_simWindowStart;   // server-time window already materialised
   datetime   m_fomcOverrides[];  // exact UTC dates supplied by operator

   // AUDIT FIX (#3): shared session manager, used so DST is decided by one
   // hour-aware implementation instead of NewsFilter's own day-only guess.
   CSessionManager *m_session;

   void SortEventsByTime()
     {
      for(int i = 1; i < m_count; i++)
        {
         SNewsEvent key = m_events[i];
         int j = i - 1;
         while(j >= 0 && m_events[j].time > key.time)
           {
            m_events[j + 1] = m_events[j];
            j--;
           }
         m_events[j + 1] = key;
        }
     }

   //==================================================================
   // M4 — synthetic high-impact calendar for the Strategy Tester.
   //
   // PROBLEM: CalendarValueHistory() is unavailable in the tester, so the
   // filter was hard-disabled there while being fully active in live:
   //    "⚠️ [YANSTD TESTER] Economic calendar is unavailable in Strategy
   //     Tester; news filter is bypassed in backtests."
   // Consequently a backtest measured a strategy that trades straight
   // through NFP, FOMC and CPI, and live traded a different one. For
   // XAUUSD that is not a small discrepancy: NFP routinely moves gold
   // 200-500 points in the first minute, against a median stop of 25 pips.
   //
   // SOLUTION: deterministic approximation of the three event families that
   // actually matter for XAUUSD, generated from the calendar rules rather
   // than a hardcoded date table (which would expire).
   //
   // ACCURACY — read this before quoting the result as live-equivalent:
   //  * NFP (first Friday) and CPI (13th, rolled off weekends) are exact in
   //    the overwhelming majority of months.
   //  * FOMC uses an ordinal approximation per meeting month (see
   //    FomcOrdinalForMonth). It is right to within a few days, and it will
   //    be off by a week in some years. The real FOMC calendar is not
   //    expressible as a rule.
   // This exists to stop the backtest from being optimistically blind to
   // news. It is deliberately NOT a substitute for the live calendar, which
   // remains authoritative whenever CalendarValueHistory() succeeds.
   //==================================================================

   // LastSundayOfMonth / IsUSDST live in Defines.mqh (shared with SessionManager).

   // AUDIT FIX (#3): previously a day-only re-implementation of European DST
   // that could disagree with SessionManager::IsEuropeanDST() (hour-aware) by
   // a few hours right around the two yearly transition days. Now delegates
   // to the shared session manager when one has been wired via
   // SetSessionManager(); falls back to the old day-only approximation only
   // if no session manager is available (should not happen in practice).
   bool IsEuropeanSummer(datetime serverTime)
     {
      if(!m_testerUseDST) return false;
      if(m_session != NULL) return m_session.IsEuropeanDST(serverTime);
      MqlDateTime dt;
      TimeToStruct(serverTime, dt);
      if(dt.mon < 3 || dt.mon > 10) return false;
      if(dt.mon > 3 && dt.mon < 10) return true;
      int lastSunday = LastSundayOfMonth(dt.year, dt.mon);
      if(dt.mon == 3)
         return (dt.day > lastSunday || (dt.day == lastSunday && dt.hour >= m_testerOffsetHrs + 1));
      return (dt.day < lastSunday || (dt.day == lastSunday && dt.hour < m_testerOffsetHrs + 2));
     }

   int TesterOffsetHours(datetime serverTime)
     {
      return m_testerOffsetHrs + (IsEuropeanSummer(serverTime) ? 1 : 0);
     }

   // Server clock -> UTC under the same assumption the rest of the EA uses.
   datetime ToUTC(datetime serverTime)
     {
      return serverTime - TesterOffsetHours(serverTime) * 3600;
     }

   // UTC -> server clock (inverse), used to store events in the same domain
   // as TimeCurrent() so GetStatus() needs no special-casing.
   datetime FromUTC(datetime utc)
     {
      // AUDIT FIX: TesterOffsetHours()/IsEuropeanSummer() decide DST from the
      // month/day/hour of whatever datetime they are given, which is meant
      // to be a SERVER-time value. Calling it directly on `utc` uses the
      // wrong clock to make that decision, which is normally harmless but
      // can flip the DST verdict for a few hours right around the two
      // yearly transition boundaries (and, rarely, across a UTC/server day
      // boundary near midnight). Refine with one extra pass: estimate the
      // server time first, then re-derive the offset from that estimate.
      int approxOffset  = TesterOffsetHours(utc);
      datetime approxServer = utc + approxOffset * 3600;
      int refinedOffset = TesterOffsetHours(approxServer);
      return utc + refinedOffset * 3600;
     }

   // 08:30 ET -> UTC (12:30 during EDT, 13:30 during EST)
   int Us0830ToUTCHour(datetime utc) { return IsUSDST(utc) ? 12 : 13; }
   // 14:00 ET -> UTC (18:00 during EDT, 19:00 during EST)
   int Us1400ToUTCHour(datetime utc) { return IsUSDST(utc) ? 18 : 19; }

   datetime MakeUTC(int year, int mon, int day, int hour, int min)
     {
      MqlDateTime dt;
      ZeroMemory(dt);
      dt.year = year; dt.mon = mon; dt.day = day; dt.hour = hour; dt.min = min; dt.sec = 0;
      return StructToTime(dt);
     }

   int FomcStatementUTCHour(int year, int mon, int day)
     {
      return Us1400ToUTCHour(MakeUTC(year, mon, day, 12, 0));
     }

   void ParseFomcOverrides(string csv)
     {
      ArrayResize(m_fomcOverrides, 0);
      StringTrimLeft(csv);
      StringTrimRight(csv);
      if(csv == "") return;
      string tokens[];
      int count = StringSplit(csv, StringGetCharacter(",", 0), tokens);
      for(int i = 0; i < count; i++)
        {
         string token = tokens[i];
         StringTrimLeft(token);
         StringTrimRight(token);
         if(StringLen(token) != 10 || StringSubstr(token, 4, 1) != "-" ||
            StringSubstr(token, 7, 1) != "-")
           {
            LogSystemWarning("NewsFilter", "ParseFomcOverrides",
                             "Ignored invalid FOMC date '" + token + "'; expected YYYY-MM-DD");
            continue;
           }
         int year = (int)StringToInteger(StringSubstr(token, 0, 4));
         int mon  = (int)StringToInteger(StringSubstr(token, 5, 2));
         int day  = (int)StringToInteger(StringSubstr(token, 8, 2));
         datetime value = MakeUTC(year, mon, day, 0, 0);
         MqlDateTime check;
         TimeToStruct(value, check);
         if(value <= 0 || check.year != year || check.mon != mon || check.day != day)
           {
            LogSystemWarning("NewsFilter", "ParseFomcOverrides",
                             "Ignored invalid FOMC calendar date '" + token + "'");
            continue;
           }
         int slot = ArraySize(m_fomcOverrides);
         if(ArrayResize(m_fomcOverrides, slot + 1, 8) == slot + 1)
            m_fomcOverrides[slot] = value;
        }
     }

   bool FindFomcOverrideDay(int year, int mon, int &day)
     {
      for(int i = 0; i < ArraySize(m_fomcOverrides); i++)
        {
         MqlDateTime dt;
         TimeToStruct(m_fomcOverrides[i], dt);
         if(dt.year == year && dt.mon == mon) { day = dt.day; return true; }
        }
      return false;
     }

   bool HasFomcOverrideYear(int year)
     {
      for(int i = 0; i < ArraySize(m_fomcOverrides); i++)
        {
         MqlDateTime dt;
         TimeToStruct(m_fomcOverrides[i], dt);
         if(dt.year == year) return true;
        }
      return false;
     }

   // Returns the `ordinal`-th `weekday` (0=Sunday) of a month.
   // ordinal < 0 means the LAST such weekday.
   int NthWeekdayOfMonth(int year, int mon, int weekday, int ordinal)
     {
      MqlDateTime first;
      ZeroMemory(first);
      first.year = year; first.mon = mon; first.day = 1;
      TimeToStruct(StructToTime(first), first);
      int firstOccurrence = 1 + ((weekday - first.day_of_week) + 7) % 7;
      if(ordinal < 0)
        {
         int daysInMonth = 31;
         if(mon == 4 || mon == 6 || mon == 9 || mon == 11) daysInMonth = 30;
         else if(mon == 2)
            daysInMonth = (((year % 4 == 0) && (year % 100 != 0)) || (year % 400 == 0)) ? 29 : 28;
         int candidate = firstOccurrence;
         while(candidate + 7 <= daysInMonth) candidate += 7;
         return candidate;
        }
      return firstOccurrence + 7 * (ordinal - 1);
     }

   // FOMC meeting months -> which Wednesday of that month carries the
   // statement. Approximation; see the accuracy note above.
   bool FomcOrdinalForMonth(int mon, int &ordinal)
     {
      switch(mon)
        {
         case 1:  ordinal = 4;  return true;  // late January
         case 3:  ordinal = 3;  return true;  // mid March
         case 4:  ordinal = -1; return true;  // last Wednesday (late April)
         case 6:  ordinal = 3;  return true;  // mid June
         case 7:  ordinal = -1; return true;  // last Wednesday (late July)
         case 9:  ordinal = 3;  return true;  // mid September
         case 10: ordinal = 4;  return true;  // late October
         case 12: ordinal = 2;  return true;  // early-mid December
        }
      return false;
     }

   void AppendSynthetic(string name, datetime utc)
     {
      if(m_count >= MAX_NEWS) return;
      datetime serverTime = FromUTC(utc);
      m_events[m_count].id         = (ulong)(m_count + 1);
      m_events[m_count].currency   = "USD";
      m_events[m_count].name       = name;
      m_events[m_count].eventName  = name;
      m_events[m_count].time       = serverTime;
      m_events[m_count].eventTime  = serverTime;
      m_events[m_count].importance = 3;   // CALENDAR_IMPORTANCE_HIGH
      m_count++;
     }

   void BuildSyntheticCalendar(datetime nowServer)
     {
      m_count = 0;
      m_calendarAvailable = true;

      // Generate a +/- 1 month window so events just across a month boundary
      // are present without rebuilding on every call.
      MqlDateTime base;
      TimeToStruct(ToUTC(nowServer), base);
      int y0 = base.year, m0 = base.mon;

      for(int off = -1; off <= 1; off++)
        {
         int y = y0;
         int m = m0 + off;
         while(m < 1)  { m += 12; y--; }
         while(m > 12) { m -= 12; y++; }

         //--- NFP: the first Friday of the month, 08:30 ET ---------------
         int firstFriday = NthWeekdayOfMonth(y, m, 5, 1);
         datetime nfpUTC = MakeUTC(y, m, firstFriday, 12, 30);
         nfpUTC = MakeUTC(y, m, firstFriday, Us0830ToUTCHour(nfpUTC), 30);
         AppendSynthetic("NFP (sim)", nfpUTC);

         //--- CPI: the 13th, rolled off a weekend, 08:30 ET --------------
         int cpiDay = 13;
         datetime probe = MakeUTC(y, m, cpiDay, 12, 0);
         MqlDateTime pd; TimeToStruct(probe, pd);
         if(pd.day_of_week == 6)      cpiDay = 12;   // Saturday -> Friday
         else if(pd.day_of_week == 0) cpiDay = 14;   // Sunday   -> Monday
         datetime cpiUTC = MakeUTC(y, m, cpiDay, 12, 30);
         cpiUTC = MakeUTC(y, m, cpiDay, Us0830ToUTCHour(cpiUTC), 30);
         AppendSynthetic("CPI (sim)", cpiUTC);

         //--- FOMC: statement day, 14:00 ET ------------------------------
         int fomcDay = 0;
         int ordinal = 0;
         bool overrideYear = HasFomcOverrideYear(y);
         bool usedOverride = FindFomcOverrideDay(y, m, fomcDay);
         bool hasFomc = usedOverride;
         // Once an operator supplies any exact date for a year, that year's
         // list is authoritative. Do not add approximate meetings for omitted
         // months, which would create false or duplicate FOMC blocks.
         if(!hasFomc && !overrideYear && FomcOrdinalForMonth(m, ordinal))
           {
            fomcDay = NthWeekdayOfMonth(y, m, 3, ordinal); // 3 = Wednesday
            hasFomc = true;
           }
         if(hasFomc)
           {
            datetime fomcUTC = MakeUTC(y, m, fomcDay,
                                       FomcStatementUTCHour(y, m, fomcDay), 0);
            AppendSynthetic(usedOverride ? "FOMC (override)" : "FOMC (sim)", fomcUTC);
           }
        }

      SortEventsByTime();
     }

public:
              CNewsFilter() : m_count(0), m_highOnly(true), m_preMins(30), m_postMins(30),
                              m_lastRefresh(0), m_calendarAvailable(true),
                              m_testerSimulate(true), m_testerOffsetHrs(2),
                              m_testerUseDST(true), m_simWindowStart(0), m_session(NULL) {}

   // AUDIT FIX (#3): wire in the shared session manager so DST decisions
   // come from one place. Call once during OnInit(), after g_session.Init().
   void SetSessionManager(CSessionManager *session) { m_session = session; }

   void Init(bool highOnly, int preMins, int postMins,
             bool testerSimulate = true, int testerOffsetHrs = 2,
              bool testerUseDST = true, string fomcDatesOverride = "")
     {
      m_highOnly        = highOnly;
      m_preMins         = preMins;
      m_postMins        = postMins;
      m_lastRefresh     = 0;
      m_calendarAvailable = true;
      m_testerSimulate  = testerSimulate;
      m_testerOffsetHrs = testerOffsetHrs;
      m_testerUseDST    = testerUseDST;
      m_simWindowStart  = 0;
      ParseFomcOverrides(fomcDatesOverride);
     }

   void RefreshEvents()
     {
      if(MQLInfoInteger(MQL_TESTER))
        {
         if(!m_testerSimulate) { m_count = 0; m_calendarAvailable = true; return; }

         datetime now = TimeCurrent();
         // Rebuild the synthetic month window only when the simulated clock
         // crosses into a new month (or on the first call).
         MqlDateTime dtCur;
         TimeToStruct(ToUTC(now), dtCur);
         MqlDateTime dtWin;
         TimeToStruct((m_simWindowStart > 0) ? ToUTC(m_simWindowStart) : 0, dtWin);
         if(m_simWindowStart == 0 || dtCur.year != dtWin.year || dtCur.mon != dtWin.mon)
           {
            BuildSyntheticCalendar(now);
            m_simWindowStart = now;
           }
         return;
        }

      datetime now = TimeCurrent();
      if(m_lastRefresh != 0 && now - m_lastRefresh < 3600) return;
      m_lastRefresh = now;
      m_count       = 0;

      string baseCur   = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_BASE);
      string profitCur = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT);

      MqlCalendarValue values[];
      datetime from = now - 86400;
      datetime to   = now + 86400 * 2;

      ResetLastError();
      // CalendarValueHistory returns a count on success (including 0) and -1 on
      // failure. Converting that result to bool inverts both edge cases: -1 is
      // true, while a valid empty window is false.
      int calendarResult = CalendarValueHistory(values, from, to, NULL, NULL);
      if(calendarResult < 0)
        {
         m_calendarAvailable = false;
         LogSystemError("NewsFilter", "RefreshEvents", GetLastError(),
                         "Economic calendar unavailable; new entries are blocked for safety");
         SendCriticalAlert("NEWS_ERROR",
                           "Economic calendar unavailable; new entries are blocked", 1800);
         // Retry in 5 minutes instead of waiting the full hourly cycle, so a
         // transient outage does not block trading for an hour.
         m_lastRefresh = now - 3300;
         return;
        }

      m_calendarAvailable = true;
      if(ArraySize(values) > 0)
        {
         int total = ArraySize(values);
         SNewsEvent relevantEvents[];
         int relevantCount = 0;
         for(int i = 0; i < total; i++)
           {
            MqlCalendarEvent evInfo;
            MqlCalendarCountry country;
            if(!CalendarEventById(values[i].event_id, evInfo)) continue;
            if(m_highOnly && evInfo.importance != CALENDAR_IMPORTANCE_HIGH) continue;
            if(!CalendarCountryById(evInfo.country_id, country)) continue;

            // Only filter for currencies related to our symbol (support XAUUSD, GOLD, synthetic symbols)
            bool relevant = (country.currency == baseCur || country.currency == profitCur ||
                             (baseCur == "XAU" && country.currency == "USD") ||
                             (StringFind(Symbol(), country.currency) >= 0));
            if(!relevant) continue;

            if(ArrayResize(relevantEvents, relevantCount + 1, 64) < relevantCount + 1) continue;
            relevantEvents[relevantCount].id          = values[i].event_id;
            relevantEvents[relevantCount].time        = values[i].time;
            relevantEvents[relevantCount].eventTime   = values[i].time;
            relevantEvents[relevantCount].name        = evInfo.name;
            relevantEvents[relevantCount].eventName   = evInfo.name;
            relevantEvents[relevantCount].currency    = country.currency;
            relevantEvents[relevantCount].importance  = (int)evInfo.importance;
            relevantCount++;
           }
         for(int i = 1; i < relevantCount; i++)
           {
            SNewsEvent key = relevantEvents[i];
            long keyDist = (long)MathAbs((double)((long)key.time - (long)now));
            int j = i - 1;
            while(j >= 0 &&
                  (long)MathAbs((double)((long)relevantEvents[j].time - (long)now)) > keyDist)
              {
               relevantEvents[j + 1] = relevantEvents[j];
               j--;
              }
            relevantEvents[j + 1] = key;
           }
         m_count = MathMin(MAX_NEWS, relevantCount);
         for(int i = 0; i < m_count; i++) m_events[i] = relevantEvents[i];
         SortEventsByTime();
        }
     }

   ENUM_NEWS_STATUS GetStatus()
     {
      // M4: the tester no longer short-circuits to NEWS_CLEAR when the
      // synthetic calendar is enabled -- see RefreshEvents().
      if(MQLInfoInteger(MQL_TESTER) && !m_testerSimulate) return NEWS_CLEAR;
      if(!m_calendarAvailable) return NEWS_ERROR;
      datetime now = TimeCurrent();
      bool anyWarning = false, anyCooling = false;
      for(int i = 0; i < m_count; i++)
        {
         datetime evt = m_events[i].time;
         if(evt <= 0) continue;
         if(now >= evt - 120 && now <= evt + 120) return NEWS_LIVE; // highest severity, stop here
         if(now >= evt - m_preMins * 60 && now < evt) anyWarning = true;
         else if(now > evt && now <= evt + m_postMins * 60) anyCooling = true;
        }
      if(anyWarning) return NEWS_WARNING;
      if(anyCooling) return NEWS_COOLING;
      return NEWS_CLEAR;
     }

   bool IsBlocked()
     {
      ENUM_NEWS_STATUS s = GetStatus();
      return (s == NEWS_WARNING || s == NEWS_LIVE || s == NEWS_COOLING || s == NEWS_ERROR);
     }

   string GetNextEventLabel()
     {
      if(!m_calendarAvailable) return "Economic calendar unavailable";
      datetime now = TimeCurrent();
      for(int i = 0; i < m_count; i++)
        {
         if(m_events[i].time > now)
           {
            int diff = (int)(m_events[i].time - now) / 60;
            int h    = diff / 60;
            int m    = diff % 60;
            return StringFormat("%s  In: %dh %dm  [HIGH]", m_events[i].name, h, m);
           }
        }
      return "No upcoming news";
     }

};

#endif // YANSTD_NEWSFILTER_MQH
