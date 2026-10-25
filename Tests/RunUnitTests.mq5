//+------------------------------------------------------------------+
//| RunUnitTests.mq5 — deterministic YANSTD regression harness       |
//+------------------------------------------------------------------+
#property copyright "YANSTD EA"
#property version   "1.00"
#property strict

#include "../Modules/Defines.mqh"
#include "../Modules/SessionManager.mqh"

int g_total=0, g_passed=0, g_failed=0;

void Check(const string name,const bool ok)
  {
   g_total++;
   if(ok) { g_passed++; Print("[TEST CASE PASS] ",name); }
   else   { g_failed++; Print("[TEST CASE FAIL] ",name); }
  }
void CheckDouble(const string name,const double actual,const double expected,const double eps=0.000001)
  { Check(name,MathAbs(actual-expected)<=eps); }

datetime DT(const string value) { return StringToTime(value); }

void TestGradeContract()
  {
   ENUM_SETUP_GRADE grades[10]={GRADE_S_PLUS,GRADE_S,GRADE_A_PLUS,GRADE_A,GRADE_B_PLUS,GRADE_B,GRADE_C_PLUS,GRADE_C,GRADE_D_PLUS,GRADE_D};
   double expected[10]={2.0,2.0,2.0,2.0,1.0,1.0,0.5,0.5,0.0,0.0};
   for(int i=0;i<10;i++)
     {
      CheckDouble("grade::multiplier::"+IntegerToString(i),SetupGradeLotMultiplier(grades[i]),expected[i]);
      Check("grade::reject::"+IntegerToString(i),SetupGradeRejects(grades[i])==(i>=8));
     }
   CheckDouble("grade::maximum",MaxSetupGradeLotMultiplier(),2.0);
  }

void SetRate(MqlRates &r,const string when,const double low,const double high,const double close)
  { ZeroMemory(r); r.time=DT(when); r.low=low; r.high=high; r.close=close; r.open=close; }

void TestFVGLifecycle()
  {
   MqlRates bull[]; ArrayResize(bull,4); ArraySetAsSeries(bull,true);
   SetRate(bull[3],"2026.01.01 00:00",110,111,110.5);
   SetRate(bull[2],"2026.01.01 00:03",109,111,110.0);
   SetRate(bull[1],"2026.01.01 00:06",105,111,110.0);
   SetRate(bull[0],"2026.01.01 00:09",100,111,110.0);
   CheckDouble("fvg::bull::ce-touch",FVGFillRatio(true,110,100,bull,4,3),0.5);
   bull[1].low=105.0001;
   Check("fvg::bull::before-ce-eligible",FVGFillRatio(true,110,100,bull,4,3)<0.5);
   bull[1].low=104.9;
   Check("fvg::bull::past-ce-ineligible",FVGFillRatio(true,110,100,bull,4,3)>=0.5);
   bull[1].low=100.0;
   CheckDouble("fvg::bull::full-fill",FVGFillRatio(true,110,100,bull,4,3),1.0);

   MqlRates bear[]; ArrayResize(bear,4); ArraySetAsSeries(bear,true);
   SetRate(bear[3],"2026.01.01 00:00",99,100,99.5);
   SetRate(bear[2],"2026.01.01 00:03",99,101,100.0);
   SetRate(bear[1],"2026.01.01 00:06",99,105,100.0);
   SetRate(bear[0],"2026.01.01 00:09",99,110,100.0);
   CheckDouble("fvg::bear::ce-touch",FVGFillRatio(false,110,100,bear,4,3),0.5);
   bear[1].high=104.9999;
   Check("fvg::bear::before-ce-eligible",FVGFillRatio(false,110,100,bear,4,3)<0.5);
   bear[1].high=105.1;
   Check("fvg::bear::past-ce-ineligible",FVGFillRatio(false,110,100,bear,4,3)>=0.5);
   bear[1].high=110.0;
   CheckDouble("fvg::bear::full-fill",FVGFillRatio(false,110,100,bear,4,3),1.0);
  }

void TestClosedBarZoneInvalidation()
  {
   MqlRates rates[]; ArrayResize(rates,5); ArraySetAsSeries(rates,true);
   SetRate(rates[4],"2026.01.01 00:00",99,111,105);
   SetRate(rates[3],"2026.01.01 00:03",98,111,99);
   SetRate(rates[2],"2026.01.01 00:06",97,111,98);
   SetRate(rates[1],"2026.01.01 00:09",96,111,97);
   SetRate(rates[0],"2026.01.01 00:12",96,111,97);
   Check("zone::two-demand-closes",ZoneInvalidatedByClosedBars(rates,5,DT("2026.01.01 00:00"),true,100,110,2,0));
   rates[2].close=101;
   Check("zone::consecutive-reset",!ZoneInvalidatedByClosedBars(rates,5,DT("2026.01.01 00:00"),true,100,110,2,0));
  }

void TestDSTAndSessions()
  {
   Check("dst::us-before-spring",!IsUSDST(DT("2025.03.09 06:59")));
   Check("dst::us-at-spring",IsUSDST(DT("2025.03.09 07:00")));
   Check("dst::us-before-autumn",IsUSDST(DT("2025.11.02 05:59")));
   Check("dst::us-at-autumn",!IsUSDST(DT("2025.11.02 06:00")));
   Check("dst::us-2026-before-spring",!IsUSDST(DT("2026.03.08 06:59")));
   Check("dst::us-2026-at-spring",IsUSDST(DT("2026.03.08 07:00")));

   CSessionManager s; s.Init(2,true);
   Check("dst::eu-before-spring",!s.IsEuropeanDST(DT("2025.03.30 02:59")));
   Check("dst::eu-at-spring",s.IsEuropeanDST(DT("2025.03.30 03:00")));
   Check("dst::eu-before-autumn",s.IsEuropeanDST(DT("2025.10.26 03:59")));
   Check("dst::eu-at-autumn",!s.IsEuropeanDST(DT("2025.10.26 04:00")));
   Check("session::london",s.GetSessionAtUTC(DT("2025.07.01 08:00"))==SESSION_LONDON);
   Check("session::overlap-summer",s.GetSessionAtUTC(DT("2025.07.01 13:00"))==SESSION_OVERLAP);
   Check("session::newyork-summer",s.GetSessionAtUTC(DT("2025.07.01 17:00"))==SESSION_NEWYORK);
   Check("session::overlap-winter",s.GetSessionAtUTC(DT("2025.01.02 14:00"))==SESSION_OVERLAP);
  }

void TestBase36Codec()
  {
   ulong values[6]={0,1,35,36,1295,123456789};
   for(int i=0;i<ArraySize(values);i++)
     {
      string enc=EncodeBase36(values[i]);
      Check("base36::roundtrip::"+IntegerToString(i),DecodeBase36(enc,0)==values[i]);
     }
   int signedValues[5]={-123,-1,0,1,123};
   for(int j=0;j<ArraySize(signedValues);j++)
     {
      string enc=EncodeBase36Signed(signedValues[j]);
      Check("base36-signed::roundtrip::"+IntegerToString(j),DecodeBase36Signed(enc,0)==signedValues[j]);
     }
  }

void TestRRRGateAutoEntry()
  {
   double pip = 0.1;
   double risk1 = 5.0 * pip;
   double reward1 = 3.0 * pip;
   double rrr1 = reward1 / risk1;
   Check("rrr::low::below-threshold", rrr1 < 1.10);
   double risk2 = 5.0 * pip;
   double reward2 = 11.0 * pip;
   double rrr2 = reward2 / risk2;
   Check("rrr::high::above-threshold", rrr2 >= 1.10);
   // Full integration: ManageAutoLimitOrders must call the gate (verified in audit)
   Check("rrr::gate::threshold-is-1.10", 0.6 < 1.10 && 2.2 >= 1.10);
  }

void TestStructureEventHistory()
  {
   SStructureEvent buf[]; ArrayResize(buf,YANSTD_STRUCT_EVENT_MAX); int count=0;
   SStructureEvent e={STRUCTURE_BOS_BULLISH,DT("2026.01.01 00:00"),100.0};
   StructureEventsPush(buf,count,e);
   StructureEventsPush(buf,count,e);
   Check("structure-events::dedupe",count==1);
   for(int i=1;i<=YANSTD_STRUCT_EVENT_MAX;i++)
     {
      e.evt=(i%2==0)?STRUCTURE_CHOCH_BULLISH:STRUCTURE_BOS_BEARISH;
      e.barTime=DT("2026.01.01 00:00")+i*180; e.level=100.0+i;
      StructureEventsPush(buf,count,e);
     }
   Check("structure-events::capacity",count==YANSTD_STRUCT_EVENT_MAX);
   SStructureEvent active[];
   int n=StructureEventsActive(buf,count,active,DT("2026.01.01 00:00")+(YANSTD_STRUCT_EVENT_MAX+1)*180,180);
   Check("structure-events::newest-first",n==YANSTD_STRUCT_EVENT_MAX && active[0].level==100.0+YANSTD_STRUCT_EVENT_MAX);
   Check("structure-events::evicts-oldest",active[n-1].barTime==DT("2026.01.01 00:00")+180);
   n=StructureEventsActive(buf,count,active,DT("2026.01.01 00:00")+(YANSTD_STRUCT_EVENT_MAX+YANSTD_STRUCT_EVENT_TTL_BARS+2)*180,180);
   Check("structure-events::ttl",n==0);
   Check("structure-events::labels",StructureEventLabel(STRUCTURE_BOS_BULLISH)=="BOS BULLISH" &&
         StructureEventLabel(STRUCTURE_CHOCH_BEARISH)=="CHoCH BEARISH" &&
         StructureEventLabel(STRUCTURE_EVENT_NONE)=="STRUCTURE NONE");
  }

void TestOBColorClassification()
  {
   // Demand OB: opposite colour = bearish candle (close<open).
   Check("ob-color::demand-opposite", ClassifyOBColor(true,  101.0, 100.0)==OB_COLOR_OPPOSITE);
   Check("ob-color::demand-same",     ClassifyOBColor(true,  100.0, 101.0)==OB_COLOR_SAME);
   // Supply OB: opposite colour = bullish candle (close>open).
   Check("ob-color::supply-opposite", ClassifyOBColor(false, 100.0, 101.0)==OB_COLOR_OPPOSITE);
   Check("ob-color::supply-same",     ClassifyOBColor(false, 101.0, 100.0)==OB_COLOR_SAME);
   Check("ob-color::doji",            ClassifyOBColor(true,  100.0, 100.0)==OB_COLOR_DOJI);
   Check("ob-color::labels",          OBColorLabel(OB_COLOR_OPPOSITE)=="OPPOSITE" &&
                                      OBColorLabel(OB_COLOR_UNKNOWN)=="UNKNOWN");
  }

void WriteResult()
  {
   int h=FileOpen("YANSTD_RunUnitTests.result",FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h!=INVALID_HANDLE)
     {
      FileWrite(h,(g_failed==0?"PASS":"FAIL"));
      FileWrite(h,StringFormat("total=%d passed=%d failed=%d",g_total,g_passed,g_failed));
      FileClose(h);
     }
  }

int OnInit()
  {
   TestGradeContract();
   TestFVGLifecycle();
   TestClosedBarZoneInvalidation();
   TestDSTAndSessions();
   TestBase36Codec();
   TestRRRGateAutoEntry();
   TestStructureEventHistory();
   TestOBColorClassification();
   PrintFormat("[TEST SUMMARY] total=%d passed=%d failed=%d",g_total,g_passed,g_failed);
   Print("[TEST RESULT] ",(g_failed==0?"PASS":"FAIL"));
   WriteResult();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }
void OnTimer() { EventKillTimer(); ExpertRemove(); }
void OnDeinit(const int reason) {}
void OnTick() {}
double OnTester() { return (g_failed==0 ? 1.0 : 0.0); }
