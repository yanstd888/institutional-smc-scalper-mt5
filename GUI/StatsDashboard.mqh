//+------------------------------------------------------------------+
//|                                              StatsDashboard.mqh  |
//|         YANSTD EA — Performance Stats Dashboard (v3.0, 2026-09)  |
//|                                                                  |
//|  Pure PERFORMANCE view built from the account history (deals     |
//|  filtered by the EA magic number). No strategy / pipeline state  |
//|  is rendered here on purpose — see YANSTD_EA_SYSTEM_GUIDE.md §10 |
//|                                                                  |
//|  Layout : title bar · 5 stat cards · equity curve · symbol       |
//|           filter · broker/balance column · compact control strip |
//|  Popups : Calendar (monthly P/L grid) · Daily Summary            |
//|  Themes : dark / light (toggle button)                           |
//|                                                                  |
//|  Efficiency contract                                             |
//|   - History is re-read ONLY when the deal count changes, when    |
//|     OnTradeTransaction marks the view dirty, or every 60 s.      |
//|   - Static layout is rebuilt only when data/theme/period/filter  |
//|     change; the 1-second tick refreshes ~6 live labels only.     |
//|   - Canvases (donuts, equity curve) are redrawn only on rebuild. |
//+------------------------------------------------------------------+
#ifndef YANSTD_STATSDASHBOARD_MQH
#define YANSTD_STATSDASHBOARD_MQH

#include <Canvas\Canvas.mqh>
#include "..\Modules\Defines.mqh"
#include "ControlPanel.mqh"   // button-name constants, shared with OnChartEvent

//--- object-name prefix (OnDeinit deletes YANSTD_UI_ + leftover YANSTD_BTN_)
#define SD_PFX            OKX_UI_PREFIX
#define SD_MAX_SYMBOLS    8
#define SD_REFRESH_SEC    60
#define SD_MAIN_W         600
#define SD_F_BRAND        "Arial"
#define SD_F_NUM          "Arial"
#define SD_F_HEAD         "Arial"
#define SD_F_BOLD         "Arial"
#define SD_F_REG          "Arial"
// Vertical layout (relative to m_y)
#define SD_Y_TITLE_H      44
#define SD_Y_CARDS        54
#define SD_CARD_H         92
#define SD_Y_MID          154
#define SD_MID_H          217
#define SD_Y_SIG          379
#define SD_SIG_H          104
#define SD_Y_CTL          491
#define SD_CTL_H          102
#define SD_PANEL_H        601

enum ENUM_SD_PERIOD
  {
   SD_PERIOD_ALL = 0,
   SD_PERIOD_YEAR,
   SD_PERIOD_MONTH,
   SD_PERIOD_WEEK,
   SD_PERIOD_TODAY,
   SD_PERIOD_30D,
   SD_PERIOD_90D,
   SD_PERIOD_COUNT
  };

//--- one completed trade (aggregated per position id)
struct SDashTrade
  {
   long     posId;
   string   symbol;
   int      type;          // POSITION_TYPE_BUY / SELL
   datetime openTime;
   datetime closeTime;
   double   volume;        // sum of entry volume
   double   profit;        // raw profit (no fees)
   double   commission;
   double   swap;
   double   net;           // profit + commission + swap
   double   pips;          // signed, volume-weighted avg open vs avg close
   double   openPxVol, openVol, exitPxVol, exitVol;
   bool     hasExit;
  };

//--- balance ledger entry (EVERY deal, any magic, incl. deposits/withdrawals)
struct SDashLedger
  {
   datetime time;
   double   delta;
  };

//--- aggregate metrics for a filtered set
struct SDashMetrics
  {
   int      trades, wins;
   double   net, grossProfit, grossLoss;
   double   commission, swap, lots, pips;
   double   maxDDMoney, maxDDPct;      // balance-curve drawdown inside the set
   double   balanceStart, balanceEnd;
   long     durationSec;                // summed, for average
  };

struct SDashTheme
  {
   color bg, panel, card, cardAlt, accent, accentDark, accentText;
   color text, dim, pos, neg, border, btn, btnText, grid, chartLine, shadow, hilite;
  };

//+------------------------------------------------------------------+
class CStatsDashboard
  {
private:
   //--- geometry / state
   int               m_x, m_y, m_w, m_h, m_corner;
   bool              m_minimized;
   bool              m_dark;
   bool              m_showLayers;
   bool              m_dirty;          // full rebuild needed
   bool              m_dataDirty;      // history re-read requested
   bool              m_built;
   ulong             m_magic;
   string            m_eaTitle;
   ENUM_SD_PERIOD    m_period;
   bool              m_showEquityDD;   // DD card toggle
   ENUM_SETUP_MODE   m_setupMode;
   SDashTheme        m_t;

   //--- data
   SDashTrade        m_trades[];
   SDashLedger       m_ledger[];
   double            m_ledgerSuffix[]; // suffix sums of delta
   int               m_lastDeals;
   datetime          m_lastRefresh;
   string            m_symbols[SD_MAX_SYMBOLS];
   bool              m_symOn[SD_MAX_SYMBOLS];
   int               m_symCount;
   SDashMetrics      m_m;              // current filtered metrics
   double            m_curveX[];       // filtered cumulative curve (net)
   datetime          m_curveT[];

   //--- live tracking
   double            m_peakEquity, m_maxEquityDDPct, m_curEquityDDPct;

   //--- popups
   bool              m_calOpen, m_dayOpen;
   int               m_calYear, m_calMonth;
   datetime          m_dayStart;
   int               m_calX, m_calY, m_dayX, m_dayY;

   //--- canvases
   CCanvas           m_cvWin, m_cvDD, m_cvEq, m_cvDay;
   CCanvas           m_cvBg, m_cvCalBg, m_cvDayBg;      // rounded backgrounds (GUI v3.2)
   bool              m_cvMainReady, m_cvDayReady;
   bool              m_cvBgReady, m_cvCalBgReady, m_cvDayBgReady;
   string            m_toast; datetime m_toastUntil;

public:
                     CStatsDashboard();
   void              Init(int corner, int x, int y, bool darkTheme, ulong magic, string eaTitle);
   void              Render(double floatingPnL, int openCount, int pendingCount,
                            double lotDisplay, double riskPct, bool tp1Enabled,
                            ENUM_AUTO_MODE autoMode, int maxActivePos,
                            bool hasFreshZone, ENUM_NEWS_STATUS newsStatus,
                            const SSignal &sig, const SMTFResult &mtf, string newsLabel,
                            string sessionLabel);
   bool              HandleClick(string name);   // true = consumed
   void              MarkDataDirty()   { m_dataDirty = true; }
   void              SetSetupModeDisplay(const ENUM_SETUP_MODE mode)
     {
      if(m_setupMode == mode) return;
      m_setupMode = mode;
      m_dirty = true;
     }
   ENUM_SETUP_MODE   SetupModeDisplay() const { return m_setupMode; }
   bool              LayersVisible() const { return m_showLayers; }
   void              Destroy();

private:
   //--- theme
   void              ApplyTheme();
   uint              ToARGB(color c, uchar a = 255) { return ColorToARGB(c, a); }
   color             Mix(color a, color b, double t);

   //--- primitives
   void              Rect(string n, int x, int y, int w, int h, color bg, color border, int z = 1);
   void              Lbl(string n, int x, int y, string text, color clr, int size,
                         string font = SD_F_REG, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER, int z = 3);
   void              Btn(string n, int x, int y, int w, int h, string text, color bg, color fg,
                         int size = 8, string font = SD_F_BOLD);
   void              DeleteByPrefix(string prefix);
   void              SetText(string n, string text, color clr);

   //--- formatting
   string            CurSym();
   string            Money(double v, bool withSign = false);
   string            Thousands(double v, int digits);
   string            Pct(double v, bool withSign = false);
   string            Duration(long sec);
   string            PeriodLabel();
   string            MonthName(int m);
   string            AccountModeLabel();

   //--- data
   void              RefreshHistory(bool force);
   void              AddSymbol(string s);
   int               FindTradeIndex(long posId, int &insertPos);
   void              ResetTrade(SDashTrade &t);
   void              SortTradesByClose();
   void              BuildLedger();
   double            BalanceAt(datetime t);
   datetime          PeriodStart();
   bool              PassesFilter(const SDashTrade &tr, datetime from, datetime to);
   void              Compute(datetime from, datetime to, SDashMetrics &m, bool buildCurve);
   void              TrackEquity();

   //--- rendering
   void              RebuildAll(double floatingPnL, int openCount, int pendingCount,
                                double lotDisplay, double riskPct, bool tp1Enabled,
                                ENUM_AUTO_MODE autoMode, int maxActivePos,
                                bool hasFreshZone, bool newsBlocked);
   void              DrawSignalCard(const SSignal &sig, ENUM_NEWS_STATUS news, string newsLabel, string sessionLabel);
   void              DrawTrendCard(const SMTFResult &mtf);
   void              TrendRow(string id, int x, int y, string tf, const SMTFData &d);
   void              CardFrame(string id, int x, int y, int w, int h, color stripe);
   void              CvRRect(CCanvas &cv, int x, int y, int w, int h, int r, color cTop, color cBot);
   void              CvRRectBorder(CCanvas &cv, int x, int y, int w, int h, int r, color border, color cTop, color cBot);
   void              CvShadow(CCanvas &cv, int x, int y, int w, int h, int r);
   void              CvCard(CCanvas &cv, int x, int y, int w, int h, color stripe);
   void              CvPanel(CCanvas &cv, int w, int h, int titleH);
   void              CreateBgCanvas(CCanvas &cv, bool &ready, string name, int x, int y, int w, int h, int z);
public:
   void              Notify(string msg) { m_toast = msg; m_toastUntil = TimeCurrent() + 6; }
private:
   void              RenderLive(double floatingPnL, int openCount, int pendingCount);
   void              DrawTitleBar(double floatingPnL, int openCount, int pendingCount);
   void              DrawTiles();
   void              DrawEquityCanvas();
   void              DrawRail();
   void              RailRow(string id, int x, int y, int w, string label, string value, color vc, int vsize);
   void              DrawControls(double lotDisplay, double riskPct, bool tp1Enabled,
                                  ENUM_AUTO_MODE autoMode, int openCount, int maxActivePos,
                                  bool hasPending, bool hasFreshZone, bool newsBlocked);
   void              EnsureMainCanvases();
   void              DestroyMainCanvases();
   void              DrawDonutCard(CCanvas &cv, int w, int h, string title, double frac,
                                   string centerText, color ringOn, string subTitle);
   void              DrawRing(CCanvas &cv, int cx, int cy, int rOut, int rIn, double frac,
                              color on, color off, color bg);

   //--- calendar popup
   void              OpenCalendar();
   void              CloseCalendar();
   void              DrawCalendar();
   void              CalendarStep(int dir);

   //--- daily summary popup
   void              OpenDay(datetime dayStart);
   void              CloseDay();
   void              DrawDay();
   void              DayStep(int dir);
   datetime          DayFloor(datetime t);
  };

//+------------------------------------------------------------------+
CStatsDashboard::CStatsDashboard() : m_x(10), m_y(25), m_w(SD_MAIN_W), m_h(SD_PANEL_H),
                                     m_corner(CORNER_LEFT_UPPER), m_minimized(false),
                                     m_dark(true), m_showLayers(true), m_dirty(true), m_dataDirty(true),
                                     m_built(false), m_magic(0), m_eaTitle("YANSTD"),
                                     m_period(SD_PERIOD_ALL), m_showEquityDD(false),
                                     m_setupMode(SETUP_SMC_PRIMARY),
                                     m_lastDeals(-1), m_lastRefresh(0), m_symCount(0),
                                     m_peakEquity(0.0), m_maxEquityDDPct(0.0), m_curEquityDDPct(0.0),
                                     m_calOpen(false), m_dayOpen(false), m_calYear(0), m_calMonth(0),
                                     m_dayStart(0), m_calX(0), m_calY(0), m_dayX(0), m_dayY(0),
                                     m_cvMainReady(false), m_cvDayReady(false),
                                     m_cvBgReady(false), m_cvCalBgReady(false), m_cvDayBgReady(false),
                                     m_toast(""), m_toastUntil(0)
  {
   for(int i = 0; i < SD_MAX_SYMBOLS; i++) { m_symbols[i] = ""; m_symOn[i] = true; }
   ZeroMemory(m_m);
  }

//+------------------------------------------------------------------+
void CStatsDashboard::Init(int corner, int x, int y, bool darkTheme, ulong magic, string eaTitle)
  {
   m_corner  = corner;
   m_x       = x;
   m_y       = y;
   m_dark    = darkTheme;
   m_magic   = magic;
   m_eaTitle = eaTitle;
   ApplyTheme();
   m_dirty = true;
   m_dataDirty = true;
   m_built = false;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   m_calYear = dt.year; m_calMonth = dt.mon;
  }

//+------------------------------------------------------------------+
void CStatsDashboard::ApplyTheme()
  {
   if(m_dark)
     {
      m_t.bg         = OKX_D_BG;
      m_t.panel      = OKX_D_BG;
      m_t.card       = OKX_D_CARD;
      m_t.cardAlt    = OKX_D_HOVER;
      m_t.accent     = OKX_D_ACCENT;
      m_t.accentDark = C'140,180,30';
      m_t.accentText = C'10,10,12';
      m_t.text       = OKX_D_TEXT;
      m_t.dim        = OKX_D_MUTED;
      m_t.pos        = OKX_D_BUY;
      m_t.neg        = OKX_D_SELL;
      m_t.border     = OKX_D_BORDER;
      m_t.btn        = OKX_D_HOVER;
      m_t.btnText    = OKX_D_TEXT;
      m_t.grid       = OKX_D_BORDER;
      m_t.chartLine  = OKX_D_ACCENT;
      m_t.shadow     = C'0,0,0';
      m_t.hilite     = OKX_D_HOVER;
     }
   else
     {
      m_t.bg         = OKX_L_BG;
      m_t.panel      = OKX_L_BG;
      m_t.card       = OKX_L_CARD;
      m_t.cardAlt    = OKX_L_HOVER;
      m_t.accent     = OKX_L_ACCENT;
      m_t.accentDark = C'40,40,46';
      m_t.accentText = C'255,255,255';
      m_t.text       = OKX_L_TEXT;
      m_t.dim        = OKX_L_MUTED;
      m_t.pos        = OKX_L_BUY;
      m_t.neg        = OKX_L_SELL;
      m_t.border     = OKX_L_BORDER;
      m_t.btn        = OKX_L_HOVER;
      m_t.btnText    = OKX_L_TEXT;
      m_t.grid       = OKX_L_BORDER;
      m_t.chartLine  = OKX_L_BUY;
      m_t.shadow     = C'210,214,220';
      m_t.hilite     = OKX_L_CARD;
     }
  }

color CStatsDashboard::Mix(color a, color b, double t)
  {
   if(t < 0.0) t = 0.0; if(t > 1.0) t = 1.0;
   int ar = (a & 0xFF), ag = ((a >> 8) & 0xFF), ab = ((a >> 16) & 0xFF);
   int br = (b & 0xFF), bg = ((b >> 8) & 0xFF), bb = ((b >> 16) & 0xFF);
   int r = (int)MathRound(ar + (br - ar) * t);
   int g = (int)MathRound(ag + (bg - ag) * t);
   int bl = (int)MathRound(ab + (bb - ab) * t);
   return (color)(r | (g << 8) | (bl << 16));
  }

//+------------------------------------------------------------------+
//| Primitives                                                        |
//+------------------------------------------------------------------+
void CStatsDashboard::Rect(string n, int x, int y, int w, int h, color bg, color border, int z)
  {
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       m_corner);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, n, OBJPROP_BACK,         false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,       true);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       z);
   ObjectSetInteger(0, n, OBJPROP_TIMEFRAMES,   OBJ_ALL_PERIODS);
  }

void CStatsDashboard::Lbl(string n, int x, int y, string text, color clr, int size,
                          string font, ENUM_ANCHOR_POINT anchor, int z)
  {
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,     m_corner);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,     anchor);
   ObjectSetString(0,  n, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetString(0,  n, OBJPROP_FONT,       font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   size);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     z);
   ObjectSetInteger(0, n, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  }

void CStatsDashboard::Btn(string n, int x, int y, int w, int h, string text, color bg, color fg,
                          int size, string font)
  {
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       m_corner);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   ObjectSetString(0,  n, OBJPROP_TEXT,         text);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        fg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, m_t.border);
   ObjectSetString(0,  n, OBJPROP_FONT,         font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     size);
   ObjectSetInteger(0, n, OBJPROP_STATE,        false);
   ObjectSetInteger(0, n, OBJPROP_BACK,         false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,       true);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       50); // buttons must out-rank popup backgrounds (z 20-23) for CLICK priority
   ObjectSetInteger(0, n, OBJPROP_TIMEFRAMES,   OBJ_ALL_PERIODS);
  }

void CStatsDashboard::SetText(string n, string text, color clr)
  {
   if(ObjectFind(0, n) < 0) return;
   ObjectSetString(0,  n, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
  }

void CStatsDashboard::DeleteByPrefix(string prefix)
  {
   ObjectsDeleteAll(0, prefix);
  }

//+------------------------------------------------------------------+
//| Formatting                                                        |
//+------------------------------------------------------------------+
string CStatsDashboard::CurSym()
  {
   string c = AccountInfoString(ACCOUNT_CURRENCY);
   if(c == "USD") return "$";
   if(c == "EUR") return "€";
   if(c == "GBP") return "£";
   if(c == "JPY") return "¥";
   return c + " ";
  }

string CStatsDashboard::Thousands(double v, int digits)
  {
   bool negative = (v < 0.0);
   v = MathAbs(v);
   string s = DoubleToString(v, digits);
   int dot = StringFind(s, ".");
   string intPart = (dot >= 0) ? StringSubstr(s, 0, dot) : s;
   string frac    = (dot >= 0) ? StringSubstr(s, dot) : "";
   string out = "";
   int len = StringLen(intPart);
   for(int i = 0; i < len; i++)
     {
      out += StringSubstr(intPart, i, 1);
      int remaining = len - i - 1;
      if(remaining > 0 && remaining % 3 == 0) out += ",";
     }
   return (negative ? "-" : "") + out + frac;
  }

string CStatsDashboard::Money(double v, bool withSign)
  {
   string body = CurSym() + Thousands(MathAbs(v), 2);
   if(v < 0.0) return "-" + body;
   return (withSign ? "+" : "") + body;
  }

string CStatsDashboard::Pct(double v, bool withSign)
  {
   string s = DoubleToString(MathAbs(v), 2) + "%";
   if(v < 0.0) return "-" + s;
   return (withSign ? "+" : "") + s;
  }

string CStatsDashboard::Duration(long sec)
  {
   if(sec <= 0) return "0s";
   long d = sec / 86400; sec %= 86400;
   long h = sec / 3600;  sec %= 3600;
   long m = sec / 60;    sec %= 60;
   if(d > 0) return StringFormat("%dd %dh %dm", (int)d, (int)h, (int)m);
   return StringFormat("%dh %dm %ds", (int)h, (int)m, (int)sec);
  }

string CStatsDashboard::PeriodLabel()
  {
   switch(m_period)
     {
      case SD_PERIOD_YEAR:  return "This Year";
      case SD_PERIOD_MONTH: return "This Month";
      case SD_PERIOD_WEEK:  return "This Week";
      case SD_PERIOD_TODAY: return "Today";
      case SD_PERIOD_30D:   return "Last 30 Days";
      case SD_PERIOD_90D:   return "Last 90 Days";
      default:              return "All History";
     }
  }

string CStatsDashboard::MonthName(int m)
  {
   string names[12] = {"January","February","March","April","May","June",
                       "July","August","September","October","November","December"};
   if(m < 1 || m > 12) return "";
   return names[m - 1];
  }

string CStatsDashboard::AccountModeLabel()
  {
   if(MQLInfoInteger(MQL_TESTER)) return "TESTER";
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode == ACCOUNT_TRADE_MODE_REAL) return "LIVE";
   if(mode == ACCOUNT_TRADE_MODE_CONTEST) return "CONTEST";
   return "DEMO";
  }

//+------------------------------------------------------------------+
//| Data engine                                                       |
//+------------------------------------------------------------------+
void CStatsDashboard::AddSymbol(string s)
  {
   for(int i = 0; i < m_symCount; i++) if(m_symbols[i] == s) return;
   if(m_symCount >= SD_MAX_SYMBOLS) return;
   m_symbols[m_symCount] = s;
   m_symOn[m_symCount]   = true;
   m_symCount++;
  }

void CStatsDashboard::ResetTrade(SDashTrade &t)
  {
   t.posId = 0; t.symbol = ""; t.type = -1; t.openTime = 0; t.closeTime = 0;
   t.volume = 0.0; t.profit = 0.0; t.commission = 0.0; t.swap = 0.0; t.net = 0.0; t.pips = 0.0;
   t.openPxVol = 0.0; t.openVol = 0.0; t.exitPxVol = 0.0; t.exitVol = 0.0; t.hasExit = false;
  }

// Binary search on m_trades (kept sorted by posId during the build phase).
int CStatsDashboard::FindTradeIndex(long posId, int &insertPos)
  {
   int lo = 0, hi = ArraySize(m_trades) - 1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if(m_trades[mid].posId == posId) { insertPos = mid; return mid; }
      if(m_trades[mid].posId < posId) lo = mid + 1; else hi = mid - 1;
     }
   insertPos = lo;
   return -1;
  }

void CStatsDashboard::SortTradesByClose()
  {
   int n = ArraySize(m_trades);
   // shell sort by closeTime (n is at most a few thousand)
   for(int gap = n / 2; gap > 0; gap /= 2)
      for(int i = gap; i < n; i++)
        {
         SDashTrade tmp = m_trades[i];
         int j = i;
         while(j >= gap && m_trades[j - gap].closeTime > tmp.closeTime)
           {
            m_trades[j] = m_trades[j - gap];
            j -= gap;
           }
         m_trades[j] = tmp;
        }
  }

void CStatsDashboard::BuildLedger()
  {
   int n = ArraySize(m_ledger);
   // shell sort by time
   for(int gap = n / 2; gap > 0; gap /= 2)
      for(int i = gap; i < n; i++)
        {
         SDashLedger tmp = m_ledger[i];
         int j = i;
         while(j >= gap && m_ledger[j - gap].time > tmp.time)
           {
            m_ledger[j] = m_ledger[j - gap];
            j -= gap;
           }
         m_ledger[j] = tmp;
        }
   ArrayResize(m_ledgerSuffix, n + 1);
   m_ledgerSuffix[n] = 0.0;
   for(int i = n - 1; i >= 0; i--) m_ledgerSuffix[i] = m_ledgerSuffix[i + 1] + m_ledger[i].delta;
  }

// Balance right BEFORE time t = current balance minus everything booked at/after t.
double CStatsDashboard::BalanceAt(datetime t)
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   int n = ArraySize(m_ledger);
   if(n == 0) return bal;
   int lo = 0, hi = n; // first index with time >= t
   while(lo < hi)
     {
      int mid = (lo + hi) / 2;
      if(m_ledger[mid].time < t) lo = mid + 1; else hi = mid;
     }
   double balAt = bal - m_ledgerSuffix[lo];
   // float residue: bal - suffix(full ledger) can be ±1e-12 instead of exact 0;
   // reading that as a real balance made Compute() divide profit% by ~1e-13
   // (giant "6333186975998762%" PROFIT tile). Snap sub-cent residue to zero.
   if(MathAbs(balAt) < 0.005) return 0.0;
   return balAt;
  }

void CStatsDashboard::RefreshHistory(bool force)
  {
   datetime now = TimeCurrent();
   if(!force && !m_dataDirty && (now - m_lastRefresh) < SD_REFRESH_SEC) return;
   if(!HistorySelect(0, now + 86400)) return;
   int total = HistoryDealsTotal();
   // AUDIT NOTE (#13, opsional -- sengaja TIDAK diubah ke dirty-flag-only):
   // HistoryDealsTotal() memang dihitung dari SEMUA deal di akun (EA lain,
   // manual, symbol lain) sebelum filter magic/symbol di bawah diterapkan,
   // jadi bisa memicu rebuild penuh walau tidak ada deal YANSTD yang
   // relevan berubah -- murni pemborosan CPU, bukan bug hasil (stats tetap
   // benar setelah filter). Namun m_ledger[] (di bawah) SENGAJA mencatat
   // SEMUA deal termasuk deposit/withdrawal/koreksi dan trade EA lain di
   // akun yang sama, karena kurva ekuitas dashboard harus merefleksikan
   // saldo akun yang sebenarnya -- deal semacam itu TIDAK memicu
   // MarkDataDirty() (yang hanya dipanggil dari transaksi ber-magic
   // YANSTD). Mengganti pemicu ini jadi m_dataDirty-only akan membuat
   // ledger/equity curve basi setiap kali ada deposit atau trade EA lain
   // sampai transaksi YANSTD berikutnya. Perbaikan yang benar (append
   // incremental per-deal baru, bukan rebuild penuh O(total) setiap kali
   // total berubah) di luar cakupan pass audit ini; didokumentasikan di
   // sini + CHANGELOG.md supaya tidak disangka terlewat.
   if(!force && !m_dataDirty && total == m_lastDeals) { m_lastRefresh = now; return; }

   ArrayResize(m_trades, 0);
   ArrayResize(m_ledger, 0);
   int oldSymCount = m_symCount;
   string oldSyms[SD_MAX_SYMBOLS]; bool oldOn[SD_MAX_SYMBOLS];
   for(int i = 0; i < SD_MAX_SYMBOLS; i++) { oldSyms[i] = m_symbols[i]; oldOn[i] = m_symOn[i]; }
   m_symCount = 0;

   for(int i = 0; i < total; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0) continue;
      datetime dtime = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      double   profit = HistoryDealGetDouble(tk, DEAL_PROFIT);
      double   comm   = HistoryDealGetDouble(tk, DEAL_COMMISSION);
      double   swap   = HistoryDealGetDouble(tk, DEAL_SWAP);

      // ledger: every deal moves the balance (trades, deposits, withdrawals, corrections)
      int ln = ArraySize(m_ledger);
      ArrayResize(m_ledger, ln + 1, 256);
      m_ledger[ln].time  = dtime;
      m_ledger[ln].delta = profit + comm + swap;

      long dtype = HistoryDealGetInteger(tk, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;
      if(m_magic != 0 && (ulong)HistoryDealGetInteger(tk, DEAL_MAGIC) != m_magic) continue;

      long   posId  = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      string sym    = HistoryDealGetString(tk, DEAL_SYMBOL);
      long   entry  = HistoryDealGetInteger(tk, DEAL_ENTRY);
      double price  = HistoryDealGetDouble(tk, DEAL_PRICE);
      double vol    = HistoryDealGetDouble(tk, DEAL_VOLUME);

      int ins = 0;
      int idx = FindTradeIndex(posId, ins);
      if(idx < 0)
        {
         int n = ArraySize(m_trades);
         ArrayResize(m_trades, n + 1, 256);
         for(int k = n; k > ins; k--) m_trades[k] = m_trades[k - 1];
         ResetTrade(m_trades[ins]);
         m_trades[ins].posId    = posId;
         m_trades[ins].symbol   = sym;
         m_trades[ins].type     = -1;
         m_trades[ins].openTime = dtime;
         m_trades[ins].closeTime= dtime;
         idx = ins;
        }
      m_trades[idx].commission += comm;
      m_trades[idx].swap       += swap;
      if(entry == DEAL_ENTRY_IN)
        {
         if(m_trades[idx].type < 0) m_trades[idx].type = (dtype == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         if(dtime < m_trades[idx].openTime) m_trades[idx].openTime = dtime;
         m_trades[idx].volume    += vol;
         m_trades[idx].openPxVol += price * vol;
         m_trades[idx].openVol   += vol;
        }
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
        {
         m_trades[idx].hasExit    = true;
         m_trades[idx].profit    += profit;
         m_trades[idx].exitPxVol += price * vol;
         m_trades[idx].exitVol   += vol;
         if(dtime > m_trades[idx].closeTime) m_trades[idx].closeTime = dtime;
        }
     }

   // finalise: drop still-open positions, compute net/pips, collect symbols
   int w = 0;
   for(int i = 0; i < ArraySize(m_trades); i++)
     {
      if(!m_trades[i].hasExit) continue;
      bool stillOpen = false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
        {
         ulong pt = PositionGetTicket(p);
         if(pt > 0 && PositionGetInteger(POSITION_IDENTIFIER) == m_trades[i].posId) { stillOpen = true; break; }
        }
      if(stillOpen) continue;
      m_trades[i].net = m_trades[i].profit + m_trades[i].commission + m_trades[i].swap;
      double point = SymbolInfoDouble(m_trades[i].symbol, SYMBOL_POINT);
      double pipSz = point * GetPipFactor(m_trades[i].symbol);
      if(pipSz > 0.0 && m_trades[i].openVol > 0.0 && m_trades[i].exitVol > 0.0)
        {
         double ao = m_trades[i].openPxVol / m_trades[i].openVol;
         double ae = m_trades[i].exitPxVol / m_trades[i].exitVol;
         m_trades[i].pips = (m_trades[i].type == POSITION_TYPE_BUY) ? (ae - ao) / pipSz : (ao - ae) / pipSz;
        }
      AddSymbol(m_trades[i].symbol);
      if(w != i) m_trades[w] = m_trades[i];
      w++;
     }
   ArrayResize(m_trades, w);
   SortTradesByClose();
   BuildLedger();

   // preserve user's symbol toggles across refreshes
   for(int i = 0; i < m_symCount; i++)
      for(int j = 0; j < oldSymCount; j++)
         if(oldSyms[j] == m_symbols[i]) { m_symOn[i] = oldOn[j]; break; }

   m_lastDeals   = total;
   m_lastRefresh = now;
   m_dataDirty   = false;
   m_dirty       = true;
  }

datetime CStatsDashboard::PeriodStart()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   switch(m_period)
     {
      case SD_PERIOD_TODAY: return today;
      case SD_PERIOD_WEEK:  { int back = (dt.day_of_week + 6) % 7; return today - back * 86400; }
      case SD_PERIOD_MONTH: { dt.day = 1; return StructToTime(dt); }
      case SD_PERIOD_YEAR:  { dt.day = 1; dt.mon = 1; return StructToTime(dt); }
      case SD_PERIOD_30D:   return today - 29 * 86400;
      case SD_PERIOD_90D:   return today - 89 * 86400;
      default:              return 0;
     }
  }

bool CStatsDashboard::PassesFilter(const SDashTrade &tr, datetime from, datetime to)
  {
   if(tr.closeTime < from || tr.closeTime >= to) return false;
   for(int i = 0; i < m_symCount; i++)
      if(m_symbols[i] == tr.symbol) return m_symOn[i];
   return true;
  }

void CStatsDashboard::Compute(datetime from, datetime to, SDashMetrics &m, bool buildCurve)
  {
   ZeroMemory(m);
   if(buildCurve) { ArrayResize(m_curveX, 0); ArrayResize(m_curveT, 0); }
   m.balanceStart = BalanceAt(from == 0 ? (datetime)1 : from);
   int n = ArraySize(m_trades);
   // "All history" (from==0) starts BEFORE the initial deposit, i.e. balance 0 ->
   // percent would be meaningless. Anchor the start balance to the moment just
   // before the FIRST trade in the filtered set closes (deposit already counted).
   if(m.balanceStart <= 0.0)
     {
      datetime firstClose = 0;
      for(int i = 0; i < n; i++)
         if(PassesFilter(m_trades[i], from, to) && (firstClose == 0 || m_trades[i].closeTime < firstClose))
            firstClose = m_trades[i].closeTime;
      if(firstClose > 0) m.balanceStart = BalanceAt(firstClose);
     }
   double cum = 0.0, peak = 0.0, maxDD = 0.0, maxDDPct = 0.0;
   double base = m.balanceStart;
   if(base <= 0.0) base = MathMax(1.0, AccountInfoDouble(ACCOUNT_BALANCE));
   for(int i = 0; i < n; i++)
     {
      if(!PassesFilter(m_trades[i], from, to)) continue;
      double net = m_trades[i].net;
      m.trades++;
      if(net > 0.0) { m.wins++; m.grossProfit += net; } else m.grossLoss += -net;
      m.net        += net;
      m.commission += m_trades[i].commission;
      m.swap       += m_trades[i].swap;
      m.lots       += m_trades[i].volume;
      m.pips       += m_trades[i].pips;
      m.durationSec += (long)(m_trades[i].closeTime - m_trades[i].openTime);
      cum += net;
      if(cum > peak) peak = cum;
      double dd = peak - cum;
      if(dd > maxDD) { maxDD = dd; double peakBal = base + peak; maxDDPct = (peakBal > 0.0) ? dd / peakBal * 100.0 : 0.0; }
      if(buildCurve)
        {
         int c = ArraySize(m_curveX);
         ArrayResize(m_curveX, c + 1, 256); ArrayResize(m_curveT, c + 1, 256);
         m_curveX[c] = cum; m_curveT[c] = m_trades[i].closeTime;
        }
     }
   m.maxDDMoney = maxDD;
   m.maxDDPct   = maxDDPct;
   m.balanceEnd = (to >= TimeCurrent()) ? AccountInfoDouble(ACCOUNT_BALANCE) : BalanceAt(to);
  }

void CStatsDashboard::TrackEquity()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > m_peakEquity) m_peakEquity = eq;
   m_curEquityDDPct = (m_peakEquity > 0.0) ? (m_peakEquity - eq) / m_peakEquity * 100.0 : 0.0;
   if(m_curEquityDDPct > m_maxEquityDDPct) m_maxEquityDDPct = m_curEquityDDPct;
  }

//+------------------------------------------------------------------+
//| Public render entry                                               |
//+------------------------------------------------------------------+
void CStatsDashboard::Render(double floatingPnL, int openCount, int pendingCount,
                             double lotDisplay, double riskPct, bool tp1Enabled,
                             ENUM_AUTO_MODE autoMode, int maxActivePos,
                             bool hasFreshZone, ENUM_NEWS_STATUS newsStatus,
                             const SSignal &sig, const SMTFResult &mtf, string newsLabel,
                             string sessionLabel)
  {
   bool newsBlocked = (newsStatus != NEWS_CLEAR);
   TrackEquity();
   RefreshHistory(false);
   if(m_dirty || !m_built)
      RebuildAll(floatingPnL, openCount, pendingCount, lotDisplay, riskPct, tp1Enabled,
                 autoMode, maxActivePos, hasFreshZone, newsBlocked);
   else
     {
      RenderLive(floatingPnL, openCount, pendingCount);
      if(!m_minimized)
         DrawControls(lotDisplay, riskPct, tp1Enabled, autoMode, openCount, maxActivePos,
                      pendingCount > 0, hasFreshZone, newsBlocked);
     }
   // live strategy cards (objects already exist after a rebuild -> property updates only)
   if(!m_minimized)
     {
      DrawSignalCard(sig, newsStatus, newsLabel, sessionLabel);
      DrawTrendCard(mtf);
     }
  }

void CStatsDashboard::RebuildAll(double floatingPnL, int openCount, int pendingCount,
                                 double lotDisplay, double riskPct, bool tp1Enabled,
                                 ENUM_AUTO_MODE autoMode, int maxActivePos,
                                 bool hasFreshZone, bool newsBlocked)
  {
   // wipe main-panel objects (popups have their own prefixes and are redrawn separately)
   DeleteByPrefix(SD_PFX + "M_");
   DeleteByPrefix("YANSTD_BTN_");
   ObjectDelete(0, LBL_LOT_DISPLAY);
   DestroyMainCanvases();

   datetime from = PeriodStart();
   Compute(from, TimeCurrent() + 86400, m_m, true);

   m_h = m_minimized ? SD_Y_TITLE_H : SD_PANEL_H;
   // rounded background canvas — created FIRST so every chart object paints above it
   CreateBgCanvas(m_cvBg, m_cvBgReady, SD_PFX + "M_CV_BG", m_x, m_y, m_w, m_h, 1);
   CvPanel(m_cvBg, m_w, m_h, SD_Y_TITLE_H);
   DrawTitleBar(floatingPnL, openCount, pendingCount);
   if(!m_minimized)
     {
      DrawRail();
      DrawTiles();
      DrawEquityCanvas();
      // strategy cards: create frames now (labels are filled by Render every second)
      CardFrame(SD_PFX + "M_SG_", m_x + 8, m_y + SD_Y_SIG, 372, SD_SIG_H, m_t.accent);
      CardFrame(SD_PFX + "M_TM_", m_x + 388, m_y + SD_Y_SIG, 204, SD_SIG_H, m_t.accent);
      CardFrame(SD_PFX + "M_CTL_", m_x + 8, m_y + SD_Y_CTL, m_w - 16, SD_CTL_H, m_t.accentDark);
      DrawControls(lotDisplay, riskPct, tp1Enabled, autoMode, openCount, maxActivePos,
                   pendingCount > 0, hasFreshZone, newsBlocked);
     }
   if(m_cvBgReady) m_cvBg.Update(false);
   if(m_calOpen) DrawCalendar();
   if(m_dayOpen) DrawDay();
   m_dirty = false;
   m_built = true;
  }

//+------------------------------------------------------------------+
//| Title bar                                                          |
//+------------------------------------------------------------------+
void CStatsDashboard::DrawTitleBar(double floatingPnL, int openCount, int pendingCount)
  {
   int x = m_x, y = m_y;
   ObjectDelete(0, SD_PFX + "M_T_ALGO");

   Lbl(SD_PFX + "M_T_BRAND", x + 16, y + 5, "YANSTD", m_t.accent, 13, SD_F_BRAND);
   string sub = (m_setupMode == SETUP_PURE_SMC) ? "YANSTD · PURE SMC (no MSNR)"
                                               : "YANSTD · SMC + soft MSNR";
   Lbl(SD_PFX + "M_T_SUB",   x + 16, y + 26, sub, m_t.dim, 7, SD_F_REG);

   string acc = StringFormat("%s  %I64d", AccountModeLabel(), AccountInfoInteger(ACCOUNT_LOGIN));
   Lbl(SD_PFX + "M_T_ACC", x + 128, y + 5, acc,
       (AccountModeLabel() == "LIVE") ? m_t.pos : m_t.text, 9, SD_F_BOLD);
   Lbl(SD_PFX + "M_T_STATUS", x + 128, y + 26, "ACTIVE", m_t.pos, 8, SD_F_BOLD);
   Lbl(SD_PFX + "M_T_LIVE", x + 200, y + 26, "", m_t.text, 8, SD_F_REG);
   RenderLive(floatingPnL, openCount, pendingCount);

   int bx = x + m_w - 8, by = y + 10, bh = 24;
   Btn(SD_PFX + "M_B_MIN",    bx - 22, by, 22, bh, m_minimized ? "▢" : "—", m_t.btn, m_t.btnText, 9); bx -= 25;
   Btn(SD_PFX + "M_B_THEME",  bx - 22, by, 22, bh, m_dark ? "☀" : "☾", m_t.accent, m_t.accentText, 10); bx -= 25;
   Btn(SD_PFX + "M_B_LAYERS", bx - 22, by, 22, bh, m_showLayers ? "◉" : "○",
       m_showLayers ? m_t.accent : m_t.btn, m_showLayers ? m_t.accentText : m_t.btnText, 10); bx -= 25;
   Btn(SD_PFX + "M_B_CAL",    bx - 22, by, 22, bh, "▦", m_calOpen ? m_t.accent : m_t.btn,
       m_calOpen ? m_t.accentText : m_t.btnText, 10); bx -= 25;
   Btn(SD_PFX + "M_B_DD",     bx - 22, by, 22, bh, "◔", m_showEquityDD ? m_t.accent : m_t.btn,
       m_showEquityDD ? m_t.accentText : m_t.btnText, 10); bx -= 25;
   Btn(BTN_CLEAR_WR,     bx - 30, by, 30, bh, "RST", m_t.btn, m_t.btnText, 7); bx -= 33;
   Btn(SD_PFX + "M_B_PERIOD", bx - 88, by, 88, bh, PeriodLabel(), m_t.btn, m_t.btnText, 7);
  }

void CStatsDashboard::RenderLive(double floatingPnL, int openCount, int pendingCount)
  {
   ObjectDelete(0, SD_PFX + "M_T_ALGO");
   bool algoOn = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 && MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   SetText(SD_PFX + "M_T_STATUS", algoOn ? "ACTIVE" : "PAUSE", algoOn ? m_t.pos : m_t.neg);
   ObjectSetInteger(0, SD_PFX + "M_T_STATUS", OBJPROP_XDISTANCE, m_x + 128);
   ObjectSetInteger(0, SD_PFX + "M_T_LIVE", OBJPROP_XDISTANCE, m_x + 200);
   ObjectSetInteger(0, SD_PFX + "M_T_LIVE", OBJPROP_YDISTANCE, m_y + 26);
   string live = StringFormat("%s  ·  %d pos", Money(floatingPnL, true), openCount);
   SetText(SD_PFX + "M_T_LIVE", live, floatingPnL >= 0.0 ? m_t.text : m_t.neg);
   if(m_minimized) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   SetText(SD_PFX + "M_R_BALNOW_V", Money(bal), m_t.accentText);
   SetText(SD_PFX + "M_R_EQ_V", Money(eq), m_t.accentText);
   if(m_showEquityDD)
     {
      // equity donut is live: redraw only its small canvas
      if(m_cvMainReady)
        {
         DrawDonutCard(m_cvDD, 102, SD_CARD_H, "EQUITY DD", MathMin(1.0, m_maxEquityDDPct / 100.0),
                       DoubleToString(m_maxEquityDDPct, 0) + "%", m_t.neg,
                       "now " + DoubleToString(m_curEquityDDPct, 1) + "%");
         m_cvDD.Update(false);
        }
     }
  }

//+------------------------------------------------------------------+
//| Stat cards                                                         |
//+------------------------------------------------------------------+
// Card frame is now painted into the panel background canvas (rounded, shadowed).
// `id` is kept for call-site compatibility; nothing is created as a chart object.
void CStatsDashboard::CardFrame(string id, int x, int y, int w, int h, color stripe)
  {
   if(!m_cvBgReady) return;
   CvCard(m_cvBg, x - m_x, y - m_y, w, h, stripe);
  }

void CStatsDashboard::DrawTiles()
  {
   int y = m_y + SD_Y_CARDS, h = SD_CARD_H, w = 102, gap = 8;
   int x = m_x + 166;

   // Trades
   CardFrame(SD_PFX + "M_C2_", x, y, w, h, m_t.accent);
   Lbl(SD_PFX + "M_C2_T",  x + w / 2, y + 10, "TRADES", m_t.dim, 7, SD_F_HEAD, ANCHOR_CENTER);
   Lbl(SD_PFX + "M_C2_V1", x + w / 2, y + 36, Thousands(m_m.trades, 0), m_t.text, 15, SD_F_NUM, ANCHOR_CENTER);
   Lbl(SD_PFX + "M_C2_L2", x + w / 2, y + 60, "Wins", m_t.dim, 7, SD_F_REG, ANCHOR_CENTER);
   Lbl(SD_PFX + "M_C2_V2", x + w / 2, y + 76, Thousands(m_m.wins, 0), m_t.pos, 9, SD_F_NUM, ANCHOR_CENTER);

   // Profit factor / recovery
   x += w + gap;
   double pf = (m_m.grossLoss > 0.0) ? m_m.grossProfit / m_m.grossLoss : (m_m.grossProfit > 0.0 ? 99.0 : 0.0);
   double rf = (m_m.maxDDMoney > 0.0) ? m_m.net / m_m.maxDDMoney : (m_m.net > 0.0 ? 99.0 : 0.0);
   CardFrame(SD_PFX + "M_C3_", x, y, w, h, m_t.accent);
   Lbl(SD_PFX + "M_C3_T",  x + w / 2, y + 10, "PROFIT FACTOR", m_t.dim, 7, SD_F_HEAD, ANCHOR_CENTER);
   Lbl(SD_PFX + "M_C3_V1", x + w / 2, y + 36, DoubleToString(pf, 2), (pf >= 1.0 || m_m.trades == 0) ? m_t.text : m_t.neg, 15, SD_F_NUM, ANCHOR_CENTER);
   Lbl(SD_PFX + "M_C3_L2", x + w / 2, y + 60, "Recovery", m_t.dim, 7, SD_F_REG, ANCHOR_CENTER);
   Lbl(SD_PFX + "M_C3_V2", x + w / 2, y + 76, DoubleToString(rf, 2), m_t.text, 9, SD_F_NUM, ANCHOR_CENTER);

   // donut canvases
   EnsureMainCanvases();
   x += w + gap;
   if(m_cvBgReady) { CvShadow(m_cvBg, x - m_x, y - m_y, w, h, 8); CvShadow(m_cvBg, x - m_x + w + gap, y - m_y, w, h, 8); }
   double wr = (m_m.trades > 0) ? (double)m_m.wins / m_m.trades : 0.0;
   ObjectSetInteger(0, SD_PFX + "M_CV_WIN", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, SD_PFX + "M_CV_WIN", OBJPROP_YDISTANCE, y);
   DrawDonutCard(m_cvWin, w, h, "WIN RATE", wr, DoubleToString(wr * 100.0, 0) + "%", m_t.accent,
                 StringFormat("%d / %d", m_m.wins, m_m.trades));
   m_cvWin.Update(false);

   x += w + gap;
   ObjectSetInteger(0, SD_PFX + "M_CV_DD", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, SD_PFX + "M_CV_DD", OBJPROP_YDISTANCE, y);
   if(m_showEquityDD)
      DrawDonutCard(m_cvDD, w, h, "EQUITY DD", MathMin(1.0, m_maxEquityDDPct / 100.0),
                    DoubleToString(m_maxEquityDDPct, 0) + "%", m_t.neg,
                    "now " + DoubleToString(m_curEquityDDPct, 1) + "%");
   else
      DrawDonutCard(m_cvDD, w, h, "BALANCE DD", MathMin(1.0, m_m.maxDDPct / 100.0),
                    DoubleToString(m_m.maxDDPct, 0) + "%", m_t.accent,
                    Money(-m_m.maxDDMoney));
   m_cvDD.Update(false);
  }

void CStatsDashboard::EnsureMainCanvases()
  {
   if(m_cvMainReady) return;
   // drop shadows live in the background canvas (painted by DrawTiles / DrawEquityCanvas)
   m_cvWin.CreateBitmapLabel(0, 0, SD_PFX + "M_CV_WIN", 0, 0, 102, SD_CARD_H, COLOR_FORMAT_ARGB_NORMALIZE);
   m_cvDD.CreateBitmapLabel (0, 0, SD_PFX + "M_CV_DD",  0, 0, 102, SD_CARD_H, COLOR_FORMAT_ARGB_NORMALIZE);
   m_cvEq.CreateBitmapLabel (0, 0, SD_PFX + "M_CV_EQ",  0, 0, 434, SD_MID_H, COLOR_FORMAT_ARGB_NORMALIZE);
   string names[3];
   names[0] = SD_PFX + "M_CV_WIN"; names[1] = SD_PFX + "M_CV_DD"; names[2] = SD_PFX + "M_CV_EQ";
   for(int i = 0; i < 3; i++)
     {
      ObjectSetInteger(0, names[i], OBJPROP_CORNER,     m_corner);
      ObjectSetInteger(0, names[i], OBJPROP_BACK,       false);
      ObjectSetInteger(0, names[i], OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, names[i], OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, names[i], OBJPROP_ZORDER,     2);
      ObjectSetInteger(0, names[i], OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
     }
   m_cvMainReady = true;
  }

void CStatsDashboard::DestroyMainCanvases()
  {
   if(m_cvBgReady) { m_cvBg.Destroy(); m_cvBgReady = false; }
   if(!m_cvMainReady) return;
   m_cvWin.Destroy(); m_cvDD.Destroy(); m_cvEq.Destroy();
   m_cvMainReady = false;
  }

// ---- Rounded canvas primitives -------------------------------------------
// Gradient-filled rounded rectangle (canvas-local coords). Row-by-row so the
// gradient and the corner clipping come from one loop.
void CStatsDashboard::CvRRect(CCanvas &cv, int x, int y, int w, int h, int r, color cTop, color cBot)
  {
   if(w <= 0 || h <= 0) return;
   r = MathMin(r, MathMin(w, h) / 2);
   for(int yy = 0; yy < h; yy++)
     {
      int dx = 0;
      if(yy < r)              { double d = r - yy - 0.5;       dx = r - (int)MathFloor(MathSqrt(MathMax(0.0, r * r - d * d))); }
      else if(yy >= h - r)    { double d = yy - (h - r) + 0.5; dx = r - (int)MathFloor(MathSqrt(MathMax(0.0, r * r - d * d))); }
      color c = Mix(cTop, cBot, (h > 1) ? (double)yy / (h - 1) : 0.0);
      cv.LineHorizontal(x + dx, x + w - 1 - dx, y + yy, ToARGB(c));
     }
  }
void CStatsDashboard::CvRRectBorder(CCanvas &cv, int x, int y, int w, int h, int r, color border, color cTop, color cBot)
  {
   CvRRect(cv, x, y, w, h, r, border, border);
   CvRRect(cv, x + 1, y + 1, w - 2, h - 2, MathMax(0, r - 1), cTop, cBot);
  }
void CStatsDashboard::CvShadow(CCanvas &cv, int x, int y, int w, int h, int r)
  {
   // two soft layers = fake blur
   color s2 = Mix(m_t.shadow, Mix(m_t.panel, m_t.bg, 0.6), 0.55);
   CvRRect(cv, x + 4, y + 6, w, h, r + 2, s2, s2);
   CvRRect(cv, x + 3, y + 4, w, h, r, m_t.shadow, m_t.shadow);
  }
// Card: shadow -> stripe-coloured rounded slab -> body (gradient) 3 px lower so
// the stripe shows as a rounded top edge; 1 px highlight under the stripe.
void CStatsDashboard::CvCard(CCanvas &cv, int x, int y, int w, int h, color stripe)
  {
   CvShadow(cv, x, y, w, h, 8);
   CvRRect(cv, x, y, w, h, 8, stripe, stripe);
   CvRRectBorder(cv, x, y + 3, w, h - 3, 8, m_t.border, m_t.cardAlt, m_t.card);
   cv.LineHorizontal(x + 6, x + w - 7, y + 4, ToARGB(m_t.hilite));
  }
// Whole panel background: rounded shell, title band, two-tone body, gold spine + hairline.
void CStatsDashboard::CvPanel(CCanvas &cv, int w, int h, int titleH)
  {
   cv.Erase(0);                                                  // transparent corners
   CvRRectBorder(cv, 0, 0, w, h, 12, m_t.accentDark, m_t.bg, m_t.bg);   // shell + gold-ish border
   if(h > titleH + 4)
     {
      color body = Mix(m_t.panel, m_t.bg, 0.6);
      CvRRect(cv, 1, titleH, w - 2, h - titleH - 1, 11, body, body);
      cv.FillRectangle(1, titleH, w - 2, titleH + 12, ToARGB(body));   // square the top of the body
     }
   CvRRect(cv, 6, 8, 5, titleH - 16, 2, m_t.accent, m_t.accent);       // spine
   cv.LineHorizontal(12, w - 13, titleH - 1, ToARGB(m_t.accent));      // hairline
  }
void CStatsDashboard::CreateBgCanvas(CCanvas &cv, bool &ready, string name, int x, int y, int w, int h, int z)
  {
   if(ready) { cv.Destroy(); ready = false; }
   cv.CreateBitmapLabel(0, 0, name, x, y, w, h, COLOR_FORMAT_ARGB_NORMALIZE);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     m_corner);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     z);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ready = true;
  }

// Anti-aliased ring, clockwise from 12 o'clock, `frac` of the circle in `on`.
void CStatsDashboard::DrawRing(CCanvas &cv, int cx, int cy, int rOut, int rIn, double frac,
                               color on, color off, color bg)
  {
   if(frac < 0.0) frac = 0.0; if(frac > 1.0) frac = 1.0;
   double limit = frac * 2.0 * M_PI;
   for(int py = cy - rOut - 1; py <= cy + rOut + 1; py++)
      for(int px = cx - rOut - 1; px <= cx + rOut + 1; px++)
        {
         double dx = px - cx + 0.5, dy = py - cy + 0.5;
         double d  = MathSqrt(dx * dx + dy * dy);
         if(d < rIn - 1.0 || d > rOut + 1.0) continue;
         double cov = MathMin(1.0, MathMax(0.0, rOut + 0.5 - d)) * MathMin(1.0, MathMax(0.0, d - (rIn - 0.5)));
         if(cov <= 0.0) continue;
         double ang = MathArctan2(dx, -dy); // 0 at top, clockwise positive
         if(ang < 0.0) ang += 2.0 * M_PI;
         color c = (ang <= limit) ? on : off;
         cv.PixelSet(px, py, ToARGB(Mix(bg, c, cov)));
        }
  }

void CStatsDashboard::DrawDonutCard(CCanvas &cv, int w, int h, string title, double frac,
                                    string centerText, color ringOn, string subTitle)
  {
   // rounded card body: transparent corners, stripe slab, gradient body, highlight
   cv.Erase(0);
   CvRRect(cv, 0, 0, w, h, 8, m_t.accent, m_t.accent);
   CvRRectBorder(cv, 0, 3, w, h - 3, 8, m_t.border, m_t.cardAlt, m_t.card);
   cv.LineHorizontal(6, w - 7, 4, ToARGB(m_t.hilite));
   cv.FontSet(SD_F_HEAD, -90);
   cv.TextOut(w / 2, 9, title, ToARGB(m_t.dim), TA_CENTER | TA_TOP);
   int cx = w / 2, cy = 53, rOut = 28, rIn = 21;
   color bgMid = Mix(m_t.cardAlt, m_t.card, (double)cy / h);
   // soft outer glow
   DrawRing(cv, cx, cy, rOut + 4, rOut + 1, 1.0, Mix(bgMid, ringOn, 0.10), Mix(bgMid, ringOn, 0.10), bgMid);
   DrawRing(cv, cx, cy, rOut, rIn, frac, ringOn, Mix(bgMid, m_t.dim, 0.28), bgMid);
   cv.FontSet(SD_F_NUM, -130);
   cv.TextOut(cx, cy, centerText, ToARGB(m_t.text), TA_CENTER | TA_VCENTER);
   cv.FontSet(SD_F_REG, -80);
   cv.TextOut(w - 5, h - 4, subTitle, ToARGB(m_t.dim), TA_RIGHT | TA_BOTTOM);
  }

//+------------------------------------------------------------------+
//| Equity curve                                                       |
//+------------------------------------------------------------------+
void CStatsDashboard::DrawEquityCanvas()
  {
   int x = m_x + 166, y = m_y + SD_Y_MID, w = 434, h = SD_MID_H;
   if(m_cvBgReady) CvShadow(m_cvBg, x - m_x, y - m_y, w, h, 8);
   ObjectSetInteger(0, SD_PFX + "M_CV_EQ", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, SD_PFX + "M_CV_EQ", OBJPROP_YDISTANCE, y);
   CCanvas *cv = GetPointer(m_cvEq);
   cv.Erase(0);
   CvRRect(cv, 0, 0, w, h, 8, m_t.accent, m_t.accent);
   CvRRectBorder(cv, 0, 3, w, h - 3, 8, m_t.border, Mix(m_t.cardAlt, m_t.card, 0.0), m_t.card);
   cv.LineHorizontal(6, w - 7, 4, ToARGB(m_t.hilite));

   // header
   cv.FontSet(SD_F_NUM, -110);
   cv.TextOut(12, 9, m_eaTitle, ToARGB(m_t.text), TA_LEFT | TA_TOP);
   cv.FontSet(SD_F_REG, -80);
   cv.TextOut(12, 26, StringFormat("%I64d", AccountInfoInteger(ACCOUNT_LOGIN)), ToARGB(m_t.dim), TA_LEFT | TA_TOP);
   string mode = AccountModeLabel();
   cv.FontSet(SD_F_HEAD, -85);
   cv.TextOut(12, 39, mode, ToARGB(mode == "LIVE" ? m_t.pos : m_t.accent), TA_LEFT | TA_TOP);
   cv.FontSet(SD_F_REG, -80);
   cv.TextOut(w - 10, 9, "EQUITY CURVE · " + PeriodLabel(), ToARGB(m_t.dim), TA_RIGHT | TA_TOP);

   // plot area
   int left = 58, right = w - 14, top = 64, bottom = h - 28;
   int n = ArraySize(m_curveX);
   double minV = 0.0, maxV = 0.0;
   for(int i = 0; i < n; i++) { if(m_curveX[i] < minV) minV = m_curveX[i]; if(m_curveX[i] > maxV) maxV = m_curveX[i]; }
   if(maxV - minV < 1e-9) { maxV = minV + 1.0; }
   double pad = (maxV - minV) * 0.08; minV -= pad; maxV += pad;

   // grid + y labels
   cv.FontSet(SD_F_REG, -75);
   for(int g = 0; g <= 4; g++)
     {
      int gy = top + (bottom - top) * g / 4;
      cv.LineHorizontal(left, right, gy, ToARGB(m_t.grid));
      double v = maxV - (maxV - minV) * g / 4.0;
      cv.TextOut(left - 6, gy, Thousands(v, 0), ToARGB(m_t.dim), TA_RIGHT | TA_VCENTER);
     }
   // zero line
   if(minV < 0.0 && maxV > 0.0)
     {
      int zy = top + (int)MathRound((maxV - 0.0) / (maxV - minV) * (bottom - top));
      cv.LineHorizontal(left, right, zy, ToARGB(Mix(m_t.grid, m_t.dim, 0.5)));
     }

   if(n == 0)
     {
      cv.FontSet(SD_F_BOLD, -100);
      cv.TextOut((left + right) / 2, (top + bottom) / 2, "No closed trades in this period",
                 ToARGB(m_t.dim), TA_CENTER | TA_VCENTER);
      cv.Update(false);
      return;
     }

   // build pixel path (start at 0 on the left edge)
   int px[], py[];
   ArrayResize(px, n + 1); ArrayResize(py, n + 1);
   px[0] = left;
   py[0] = top + (int)MathRound((maxV - 0.0) / (maxV - minV) * (bottom - top));
   for(int i = 0; i < n; i++)
     {
      px[i + 1] = left + (int)MathRound((double)(i + 1) / n * (right - left));
      py[i + 1] = top + (int)MathRound((maxV - m_curveX[i]) / (maxV - minV) * (bottom - top));
     }
   // area fill (vertical gradient, solid pre-blended colours)
   int baseY = MathMin(bottom, MathMax(top, py[0]));
   for(int i = 0; i < n; i++)
     {
      int xa = px[i], xb = px[i + 1];
      for(int xx = xa; xx <= xb; xx++)
        {
         double t  = (xb == xa) ? 0.0 : (double)(xx - xa) / (xb - xa);
         int    yy = (int)MathRound(py[i] + (py[i + 1] - py[i]) * t);
         int y1 = MathMin(yy, baseY), y2 = MathMax(yy, baseY);
         bool positive = (yy <= baseY);
         color tint = positive ? m_t.chartLine : m_t.neg;
         for(int k = y1; k <= y2; k++)
           {
            double depth = (y2 == y1) ? 0.0 : (double)(k - y1) / (y2 - y1);
            double a = positive ? (0.30 - 0.26 * depth) : (0.04 + 0.26 * depth);
            cv.PixelSet(xx, k, ToARGB(Mix(m_t.card, tint, a)));
           }
        }
     }
   // line
   for(int i = 0; i < n; i++)
      cv.LineAA(px[i], py[i], px[i + 1], py[i + 1], ToARGB(m_t.chartLine));
   // end marker
   cv.FillCircle(px[n], py[n], 3, ToARGB(m_t.chartLine));
   cv.FillCircle(px[n], py[n], 1, ToARGB(m_t.card));

   // x labels (dates)
   cv.FontSet(SD_F_REG, -75);
   int labels = MathMin(5, n);
   string prevLabel = "";
   for(int l = 0; l < labels; l++)
     {
      int idx = (labels == 1) ? n - 1 : (int)MathRound((double)l * (n - 1) / (labels - 1));
      int lx  = px[idx + 1];
      uint align = (l == 0) ? (TA_LEFT | TA_TOP) : ((l == labels - 1) ? (TA_RIGHT | TA_TOP) : (TA_CENTER | TA_TOP));
      // same calendar day as the previous label -> show the time instead (no duplicate dates)
      string lab = TimeToString(m_curveT[idx], TIME_DATE);
      if(lab == prevLabel) lab = TimeToString(m_curveT[idx], TIME_MINUTES);
      else prevLabel = lab;
      cv.TextOut(lx, bottom + 7, lab, ToARGB(m_t.dim), align);
     }
   cv.Update(false);
  }

void CStatsDashboard::RailRow(string id, int x, int y, int w, string label, string value, color vc, int vsize)
  {
   Lbl(id + "L", x, y + 1, label, m_t.dim, 7, SD_F_REG);
   Lbl(id + "V", x + w, y, value, vc, vsize, SD_F_NUM, ANCHOR_RIGHT_UPPER);
  }

void CStatsDashboard::DrawRail()
  {
   int x = m_x + 8, y = m_y + SD_Y_CARDS, w = 150, h = (SD_Y_MID + SD_MID_H) - SD_Y_CARDS;
   string p = SD_PFX + "M_RL_";
   CardFrame(p, x, y, w, h, m_t.accent);
   int ix = x + 12, iw = w - 24;

   // Headline: profit %
   double pct = (m_m.balanceStart > 0.0) ? m_m.net / m_m.balanceStart * 100.0 : 0.0;
   color pc = (m_m.net > 0.0) ? m_t.pos : (m_m.net < 0.0 ? m_t.neg : m_t.text);
   Lbl(p + "T",  ix, y + 8, "PROFIT", m_t.accent, 6, SD_F_HEAD);
   Lbl(p + "PCT", ix, y + 22, Pct(pct, true), pc, 16, SD_F_NUM);
   Lbl(p + "NET", ix, y + 46, Money(m_m.net, true), pc, 9, SD_F_NUM);
   if(m_cvBgReady) m_cvBg.LineHorizontal(ix - m_x, ix - m_x + iw, y + 64 - m_y, ToARGB(m_t.border));

   if(m_cvBgReady) CvRRectBorder(m_cvBg, x + 6 - m_x, y + 70 - m_y, w - 12, 48, 6,
                                m_t.accentDark, Mix(m_t.accent, m_t.hilite, 0.12), m_t.accent);
   Lbl(SD_PFX + "M_R_BALNOW_T", ix, y + 76, "BAL", m_t.accentText, 7, SD_F_BOLD);
   Lbl(SD_PFX + "M_R_BALNOW_V", ix + iw, y + 74, Money(AccountInfoDouble(ACCOUNT_BALANCE)),
       m_t.accentText, 8, SD_F_NUM, ANCHOR_RIGHT_UPPER);
   Lbl(SD_PFX + "M_R_EQ_T", ix, y + 94, "EQ", m_t.accentText, 7, SD_F_BOLD);
   Lbl(SD_PFX + "M_R_EQ_V", ix + iw, y + 92, Money(AccountInfoDouble(ACCOUNT_EQUITY)),
       m_t.accentText, 8, SD_F_NUM, ANCHOR_RIGHT_UPPER);
   RailRow(p + "BS_", ix, y + 126, iw, "Start", Money(m_m.balanceStart), m_t.text, 7);
   if(m_cvBgReady) m_cvBg.LineHorizontal(ix - m_x, ix - m_x + iw, y + 144 - m_y, ToARGB(m_t.border));

   long avgDur = (m_m.trades > 0) ? m_m.durationSec / m_m.trades : 0;
   RailRow(p + "CM_", ix, y + 152, iw, "Comm",  Money(m_m.commission), m_t.text, 7);
   RailRow(p + "SW_", ix, y + 168, iw, "Swap",  Money(m_m.swap),       m_t.text, 7);
   RailRow(p + "LT_", ix, y + 184, iw, "Lots",  DoubleToString(m_m.lots, 2), m_t.text, 7);
   RailRow(p + "DU_", ix, y + 200, iw, "Avg",   Duration(avgDur),     m_t.text, 7);
   if(m_cvBgReady) m_cvBg.LineHorizontal(ix - m_x, ix - m_x + iw, y + 232 - m_y, ToARGB(m_t.border));

   // Symbols filter (title line carries the ALL / NONE controls)
   bool allOn = true;
   for(int i = 0; i < m_symCount; i++) if(!m_symOn[i]) allOn = false;
   Lbl(SD_PFX + "M_SYM_T", ix, y + 240, StringFormat("◆  SYMBOLS (%d)", m_symCount), m_t.accent, 7, SD_F_HEAD);
   Btn(SD_PFX + "M_SYM_ALL_CB", ix + iw - 32, y + 239, 14, 14, allOn ? "✓" : "", allOn ? m_t.accent : m_t.btn, m_t.accentText, 8);
   Btn(SD_PFX + "M_SYM_UNSEL",  ix + iw - 14, y + 239, 14, 14, "×", m_t.btn, m_t.btnText, 8);
   color dots[SD_MAX_SYMBOLS] = {C'250,96,110', C'255,170,60', C'82,200,140', C'170,120,255',
                                 C'70,200,230', C'255,110,190', C'190,210,80', C'120,140,170'};
   int shown = MathMin(m_symCount, 3);
   int ry = y + 258;
   for(int i = 0; i < shown; i++)
     {
      string sfx = StringFormat("%d", i);
      Btn(SD_PFX + "M_SYM_CB_" + sfx, ix, ry, 14, 14, m_symOn[i] ? "✓" : "", m_symOn[i] ? m_t.accent : m_t.btn, m_t.accentText, 8);
      string nm = m_symbols[i]; if(StringLen(nm) > 10) nm = StringSubstr(nm, 0, 10);
      Lbl(SD_PFX + "M_SYM_L_" + sfx, ix + 19, ry - 2, nm, m_symOn[i] ? m_t.text : m_t.dim, 8, SD_F_REG);
      Lbl(SD_PFX + "M_SYM_D_" + sfx, ix + iw, ry - 3, "●", dots[i], 9, SD_F_REG, ANCHOR_RIGHT_UPPER);
      ry += 16;
     }
   if(m_symCount == 0) Lbl(SD_PFX + "M_SYM_NONE", ix, ry - 2, "no closed trades yet", m_t.dim, 7, SD_F_REG);
   if(m_symCount > 3)  Lbl(SD_PFX + "M_SYM_MORE", ix, ry - 2, StringFormat("+%d more (use ALL)", m_symCount - 3), m_t.dim, 7, SD_F_REG);
  }

//+------------------------------------------------------------------+
//| Strategy cards: Signal Status + MTF Trend Meter (live, per second)  |
//+------------------------------------------------------------------+
void CStatsDashboard::DrawSignalCard(const SSignal &sig, ENUM_NEWS_STATUS news, string newsLabel, string sessionLabel)
  {
   int x = m_x + 8, y = m_y + SD_Y_SIG, w = 372;
   string p = SD_PFX + "M_SG_";
   Lbl(p + "T", x + 12, y + 9, "◆  SIGNAL STATUS", m_t.accent, 7, SD_F_HEAD);

   string dirText = "SCANNING   M15 > M5 > M3";
   color  dirClr  = m_t.dim;
   if(sig.isValid && sig.direction == SIGNAL_BUY)       { dirText = "▲  BUY SETUP CONFIRMED (M3 CHoCH)";  dirClr = m_t.pos; }
   else if(sig.isValid && sig.direction == SIGNAL_SELL) { dirText = "▼  SELL SETUP CONFIRMED (M3 CHoCH)"; dirClr = m_t.neg; }
   if(StringLen(dirText) > 42) dirText = StringSubstr(dirText, 0, 42) + "…";
   Lbl(p + "DIR", x + 12, y + 26, dirText, dirClr, 8, SD_F_BOLD);

   double aiConf = (sig.aiConfidence > 0.0) ? sig.aiConfidence : 50.0;
   string l2 = sig.isValid
               ? StringFormat("Entry %s   SL %.1fp   TP1 %.1fp   TP2 %.1fp   Lot %.2f",
                              DoubleToString(sig.entryPrice, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)),
                              sig.slPips, sig.tp1Pips, sig.tp2Pips, sig.lotSize)
               : (sig.invalidReason != "" ? sig.invalidReason : "Monitoring MSNR zones & SMC POIs…");
   if(StringLen(l2) > 46) l2 = StringSubstr(l2, 0, 46) + "…";
   bool toastOn = (m_toast != "" && TimeCurrent() <= m_toastUntil);
   if(toastOn) { l2 = "⚠ " + m_toast; if(StringLen(l2) > 46) l2 = StringSubstr(l2, 0, 46) + "…"; }
   Lbl(p + "L2", x + 12, y + 46, l2, toastOn ? C'255,165,0' : m_t.text, 7, toastOn ? SD_F_BOLD : SD_F_REG);

   // AUDIT FIX (#4): this used to be a 3rd, independent session
   // implementation based on raw TimeGMT() (day-only, not DST-aware, and not
   // routed through GetSimulatedUTC()) — wrong in backtest/visual mode and
   // out of sync with the session boundaries actually used for sizing
   // (SessionManager::GetSessionSizeMultiplier()) and stats attribution.
   // sessionLabel is now supplied by the caller from
   // SessionManager::GetCurrentSession().
   int spreadPts = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   string market = StringFormat("Spread %d | %s | Brain %.0f%%",
                                spreadPts, sessionLabel, aiConf);
   Lbl(p + "MK", x + 12, y + 64, market, m_t.text, 8, SD_F_REG);
   string nl = (news == NEWS_CLEAR) ? "News: CLEAR" :
               (news == NEWS_LIVE ? "News: LIVE — trading blocked" :
               (news == NEWS_WARNING ? "News: pre-event window" : "News: cooling down"));
   if(newsLabel != "")
     {
      int cut = StringFind(newsLabel, " In:");
      nl += " | " + ((cut > 0) ? StringSubstr(newsLabel, 0, cut) : newsLabel);
     }
   if(StringLen(nl) > 42) nl = StringSubstr(nl, 0, 42) + "…";
   Lbl(p + "NW", x + 12, y + 82, nl, (news == NEWS_CLEAR) ? m_t.text : C'255,165,0', 8, SD_F_REG);
  }

void CStatsDashboard::TrendRow(string id, int x, int y, string tf, const SMTFData &d)
  {
   int filled = (int)MathRound(d.bullPct / 20.0);
   string bar = "";
   for(int i = 0; i < 5; i++) bar += (i < filled) ? "■" : "□";
   color c = (d.bullPct >= 55.0) ? m_t.pos : (d.bullPct <= 45.0) ? m_t.neg : m_t.dim;
   Lbl(id + "TF", x, y, tf, m_t.dim, 7, SD_F_BOLD);
   Lbl(id + "BR", x + 26, y - 1, bar, c, 8, "Consolas");
   Lbl(id + "PC", x + 70, y, StringFormat("%.0f", d.bullPct), c, 7, SD_F_NUM);
  }

void CStatsDashboard::DrawTrendCard(const SMTFResult &mtf)
  {
   int x = m_x + 388, y = m_y + SD_Y_SIG, w = 204;
   string p = SD_PFX + "M_TM_";
   Lbl(p + "T", x + 12, y + 9, "◆  MTF TREND METER", m_t.accent, 7, SD_F_HEAD);
   TrendRow(p + "R0_", x + 12,  y + 27, "M3",  mtf.m3);
   TrendRow(p + "R1_", x + 108, y + 27, "M30", mtf.m30);
   TrendRow(p + "R2_", x + 12,  y + 42, "M5",  mtf.m5);
   TrendRow(p + "R3_", x + 108, y + 42, "H1",  mtf.h1);
   TrendRow(p + "R4_", x + 12,  y + 57, "M15", mtf.m15);
   TrendRow(p + "R5_", x + 108, y + 57, "H4",  mtf.h4);

   double c = mtf.confluence;
   color cClr = (c >= 56.0) ? m_t.pos : (c <= 45.0) ? m_t.neg : m_t.dim;
   int stars = (int)MathRound(MathMin(5.0, MathMax(0.0, c / 20.0)));
   string starStr = "";
   for(int i = 0; i < 5; i++) starStr += (i < stars) ? "★" : "☆";
   Lbl(p + "CF", x + 12, y + 76, StringFormat("Confluence %.0f%%", c), cClr, 8, SD_F_NUM);
   Lbl(p + "ST", x + w - 12, y + 75, starStr, m_t.accent, 9, SD_F_REG, ANCHOR_RIGHT_UPPER);
   string bias = mtf.biasLabel;
   if(StringLen(bias) > 26) bias = StringSubstr(bias, 0, 26);
   Lbl(p + "BI", x + 12, y + 90, bias, cClr, 7, SD_F_REG);
  }

//+------------------------------------------------------------------+
//| Compact control strip (button names shared with OnChartEvent)      |
//+------------------------------------------------------------------+
void CStatsDashboard::DrawControls(double lotDisplay, double riskPct, bool tp1Enabled,
                                   ENUM_AUTO_MODE autoMode, int openCount, int maxActivePos,
                                   bool hasPending, bool hasFreshZone, bool newsBlocked)
  {
   int x = m_x + 8, y = m_y + SD_Y_CTL, w = m_w - 16, h = SD_CTL_H;
   bool full = (openCount >= maxActivePos);

   int bh = 24;
   int rx = x + 6;
   int r0 = y + 6;
   Lbl(SD_PFX + "M_CTL_MODE_L", rx, r0 + 5, "MODE", m_t.dim, 7, SD_F_HEAD);
   rx += 48;
   int mw = 84;
   bool smc  = (m_setupMode == SETUP_SMC_PRIMARY);
   bool pure = (m_setupMode == SETUP_PURE_SMC);
   Btn(BTN_MODE_SMC, rx, r0, mw, bh, "2  SMC",
       smc ? m_t.accent : m_t.btn, smc ? m_t.accentText : m_t.btnText, 7); rx += mw + 4;
   Btn(BTN_MODE_PURE, rx, r0, mw, bh, "3  PURE",
       pure ? m_t.accent : m_t.btn, pure ? m_t.accentText : m_t.btnText, 7);

   // row 1: risk presets | lot -/value/+ | TP1 | Limit | Cut 50% | Hapus
   int r1 = r0 + bh + 6;
   rx = x + 6;  // AUDIT FIX: removed redundant `int rx` redeclaration that caused compile error
   double presets[4] = {0.5, 1.0, 1.5, 2.0};
   string pnames[4]  = {BTN_RISK_05, BTN_RISK_10, BTN_RISK_15, BTN_RISK_20};
   for(int i = 0; i < 4; i++)
     {
      bool on = MathAbs(riskPct - presets[i]) < 0.01;
      Btn(pnames[i], rx, r1, 42, bh, DoubleToString(presets[i], 1) + "%",
          on ? m_t.accent : m_t.btn, on ? m_t.accentText : m_t.btnText, 7);
      rx += 45;
     }
   rx += 8;
   Btn(BTN_LOT_MINUS, rx, r1, 28, bh, "−", m_t.btn, m_t.btnText, 11); rx += 30;
   Btn(LBL_LOT_DISPLAY, rx, r1, 78, bh, StringFormat("%.2f lot", lotDisplay),
       m_t.cardAlt, m_t.text, 8, SD_F_NUM); rx += 82;
   Btn(BTN_LOT_PLUS, rx, r1, 28, bh, "+", m_t.btn, m_t.btnText, 11); rx += 36;

   int tail = w - (rx - x) - 6;
   int slot = tail / 4;
   if(slot < 52) slot = 52;
   // AUDIT NOTE (#14): tp1Enabled ? "TP1" : "TP1" is not a bug -- re-checked
   // against the other toggle buttons on this row (CUT50, HAPUS), which use
   // the same pattern: label text stays constant, only color indicates
   // on/off state. Left as-is intentionally; simplifying to a plain string
   // literal would be a pure code-smell cleanup with no behavior change.
   Btn(BTN_TP1_TOGGLE, rx, r1, slot - 4, bh, tp1Enabled ? "TP1" : "TP1",
       tp1Enabled ? Mix(m_t.card, m_t.pos, 0.40) : m_t.btn,
       tp1Enabled ? m_t.pos : m_t.dim, 8); rx += slot;
   bool limitOff = (!hasFreshZone || full || newsBlocked);
   Btn(BTN_PASANG_LIMIT, rx, r1, slot - 4, bh, "LMT",
       limitOff ? m_t.btn : Mix(m_t.card, m_t.accent, 0.35),
       limitOff ? m_t.dim : m_t.text, 8); rx += slot;
   Btn(BTN_CUT50, rx, r1, slot - 4, bh, "CUT",
       (openCount <= 0) ? m_t.btn : Mix(m_t.card, C'255,165,0', 0.35),
       (openCount <= 0) ? m_t.dim : C'255,165,0', 8); rx += slot;
   Btn(BTN_HAPUS_ORDER, rx, r1, w - (rx - x) - 6, bh, "DEL",
       hasPending ? Mix(m_t.card, m_t.neg, 0.35) : m_t.btn,
       hasPending ? m_t.neg : m_t.dim, 8);

   // row 2: BUY | SELL | AUTO | CLOSE ALL
   int r2 = r1 + bh + 6;
   rx = x + 6;
   bool tradeOff = newsBlocked || full;
   Btn(BTN_BUY_MARKET, rx, r2, 130, bh, "BUY", tradeOff ? m_t.btn : m_t.pos,
       tradeOff ? m_t.dim : m_t.accentText, 8, SD_F_HEAD); rx += 134;
   Btn(BTN_SELL_MARKET, rx, r2, 130, bh, "SELL", tradeOff ? m_t.btn : m_t.neg,
       tradeOff ? m_t.dim : C'255,255,255', 8, SD_F_HEAD); rx += 138;
   bool autoOn = (autoMode == AUTO_ON);
   Btn(BTN_AUTO_TOGGLE, rx, r2, 160, bh, autoOn ? "AUTO  ·  ON" : "AUTO  ·  PAUSE",
       autoOn ? Mix(m_t.card, m_t.pos, 0.35) : m_t.btn, autoOn ? m_t.pos : m_t.btnText, 7); rx += 164;
   Btn(BTN_CLOSE_ALL, rx, r2, w - (rx - x) - 6, bh, "CLOSE ALL", m_t.neg, C'255,255,255', 7, SD_F_HEAD);
  }

//+------------------------------------------------------------------+
//| Calendar popup                                                     |
//+------------------------------------------------------------------+
void CStatsDashboard::OpenCalendar()
  {
   m_calOpen = true;
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   m_calX = m_x + 40; m_calY = m_y + 40;
   if(m_calX + 520 > chartW - 4) m_calX = MathMax(0, chartW - 524);
   DrawCalendar();
  }

void CStatsDashboard::CloseCalendar()
  {
   m_calOpen = false;
   DeleteByPrefix(SD_PFX + "CAL_");
   if(m_cvCalBgReady) { m_cvCalBg.Destroy(); m_cvCalBgReady = false; }
   CloseDay();
  }

void CStatsDashboard::CalendarStep(int dir)
  {
   m_calMonth += dir;
   if(m_calMonth > 12) { m_calMonth = 1; m_calYear++; }
   if(m_calMonth < 1)  { m_calMonth = 12; m_calYear--; }
   DrawCalendar();
  }

void CStatsDashboard::DrawCalendar()
  {
   DeleteByPrefix(SD_PFX + "CAL_");
   int x = m_calX, y = m_calY, w = 520, h = 372;
   CreateBgCanvas(m_cvCalBg, m_cvCalBgReady, SD_PFX + "CAL_CVBG", x, y, w, h, 20);
   CvPanel(m_cvCalBg, w, h, 26);
   Lbl(SD_PFX + "CAL_TITLE", x + 10, y + 6, "▦  Calendar", m_t.text, 8, SD_F_BOLD, ANCHOR_LEFT_UPPER, 23);
   Btn(SD_PFX + "CAL_CLOSE", x + w - 26, y + 3, 22, 20, "✕", m_t.btn, m_t.btnText, 8);

   // month header
   MqlDateTime d0; ZeroMemory(d0);
   d0.year = m_calYear; d0.mon = m_calMonth; d0.day = 1;
   datetime monthStart = StructToTime(d0);
   int nextM = m_calMonth + 1, nextY = m_calYear; if(nextM > 12) { nextM = 1; nextY++; }
   MqlDateTime d1; ZeroMemory(d1); d1.year = nextY; d1.mon = nextM; d1.day = 1;
   datetime monthEnd = StructToTime(d1);
   int daysInMonth = (int)((monthEnd - monthStart) / 86400);
   MqlDateTime dchk; TimeToStruct(monthStart, dchk);
   int firstCol = (dchk.day_of_week + 6) % 7; // Monday = 0

   Lbl(SD_PFX + "CAL_MONTH", x + 14, y + 38, MonthName(m_calMonth) + " " + IntegerToString(m_calYear),
       m_t.text, 11, SD_F_NUM, ANCHOR_LEFT_UPPER, 23);
   Btn(SD_PFX + "CAL_PREV", x + 150, y + 38, 22, 20, "‹", m_t.btn, m_t.btnText, 10);
   Btn(SD_PFX + "CAL_NEXT", x + 176, y + 38, 22, 20, "›", m_t.btn, m_t.btnText, 10);

   SDashMetrics mm; Compute(monthStart, monthEnd, mm, false);
   double mPct = (mm.balanceStart > 0.0) ? mm.net / mm.balanceStart * 100.0 : 0.0;
   int sx = x + 212, sw = w - 212 - 10;
   CvRRectBorder(m_cvCalBg, sx - x, 32, sw, 34, 8, m_t.accentDark, Mix(m_t.accent, m_t.hilite, 0.15), m_t.accent);
   m_cvCalBg.Update(false);
   string sl[4] = {"Trades", "Wins", "Profit", "Percent"};
   string sv[4];
   sv[0] = Thousands(mm.trades, 0); sv[1] = Thousands(mm.wins, 0); sv[2] = Money(mm.net); sv[3] = Pct(mPct);
   for(int i = 0; i < 4; i++)
     {
      int cx = sx + sw * (2 * i + 1) / 8;
      Lbl(SD_PFX + "CAL_SUM_L" + IntegerToString(i), cx, y + 39, sl[i], Mix(m_t.accentText, m_t.accent, 0.3), 7, SD_F_REG, ANCHOR_CENTER, 23);
      Lbl(SD_PFX + "CAL_SUM_V" + IntegerToString(i), cx, y + 55, sv[i], m_t.accentText, 8, SD_F_NUM, ANCHOR_CENTER, 23);
     }

   // weekday header
   string wd[8] = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Totals"};
   int gx = x + 10, gy = y + 76, cw = 58, ch = 42, gap = 4;
   for(int c = 0; c < 8; c++)
      Lbl(SD_PFX + "CAL_WD" + IntegerToString(c), gx + c * (cw + gap) + cw / 2, gy, wd[c], m_t.dim, 6,
          SD_F_BOLD, ANCHOR_CENTER, 23);
   gy += 12;

   // day cells: 6 rows x 7 + totals
   datetime today0 = DayFloor(TimeCurrent());
   int rows = (firstCol + daysInMonth + 6) / 7; if(rows < 5) rows = 5; if(rows > 6) rows = 6;
   for(int r = 0; r < rows; r++)
     {
      double weekNet = 0.0; datetime weekStart = 0; bool weekHas = false;
      for(int c = 0; c < 7; c++)
        {
         int cell = r * 7 + c;
         int dayNum = cell - firstCol + 1;             // may be <=0 or >daysInMonth
         datetime dStart = monthStart + (dayNum - 1) * 86400;
         if(c == 0) weekStart = dStart;
         bool inMonth = (dayNum >= 1 && dayNum <= daysInMonth);
         int cx = gx + c * (cw + gap), cy = gy + r * (ch + gap);
         string base = SD_PFX + "CAL_D" + IntegerToString(cell) + "_";
         SDashMetrics dm; Compute(dStart, dStart + 86400, dm, false);
         bool isToday = (dStart == today0);
         color cellBg = inMonth ? (isToday ? Mix(m_t.card, m_t.accent, 0.25) : m_t.card) : Mix(m_t.panel, m_t.card, 0.4);
         Rect(base + "BG", cx, cy, cw, ch, cellBg, isToday ? m_t.accent : m_t.border, 21);
         MqlDateTime dd; TimeToStruct(dStart, dd);
         Lbl(base + "N", cx + 4, cy + 3, IntegerToString(dd.day), inMonth ? m_t.dim : Mix(m_t.dim, m_t.panel, 0.5), 7, SD_F_BOLD, ANCHOR_LEFT_UPPER, 23);
         if(dm.trades > 0)
           {
            double dp = (dm.balanceStart > 0.0) ? dm.net / dm.balanceStart * 100.0 : 0.0;
            color vc = (dm.net >= 0.0) ? m_t.pos : m_t.neg;
            if(!inMonth) vc = Mix(vc, m_t.panel, 0.5);
            Lbl(base + "P", cx + cw / 2, cy + 20, Money(dm.net), vc, 8, SD_F_BOLD, ANCHOR_CENTER, 23);
            Lbl(base + "C", cx + cw / 2, cy + 33, Pct(dp), vc, 7, SD_F_REG, ANCHOR_CENTER, 23);
            weekNet += dm.net; weekHas = true;
           }
        }
      // weekly totals
      int tx = gx + 7 * (cw + gap), ty = gy + r * (ch + gap);
      Rect(SD_PFX + "CAL_W" + IntegerToString(r) + "_BG", tx, ty, cw, ch, m_t.cardAlt, m_t.border, 21);
      if(weekHas)
        {
         double wb = BalanceAt(weekStart);
         double wp = (wb > 0.0) ? weekNet / wb * 100.0 : 0.0;
         color wc = (weekNet >= 0.0) ? m_t.pos : m_t.neg;
         Lbl(SD_PFX + "CAL_W" + IntegerToString(r) + "_P", tx + cw / 2, ty + 15, Money(weekNet), wc, 8, SD_F_NUM, ANCHOR_CENTER, 23);
         Lbl(SD_PFX + "CAL_W" + IntegerToString(r) + "_C", tx + cw / 2, ty + 30, Pct(wp), wc, 7, SD_F_REG, ANCHOR_CENTER, 23);
        }
     }
  }

//+------------------------------------------------------------------+
//| Daily summary popup                                                |
//+------------------------------------------------------------------+
datetime CStatsDashboard::DayFloor(datetime t)
  {
   MqlDateTime dt; TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
  }

void CStatsDashboard::OpenDay(datetime dayStart)
  {
   m_dayOpen  = true;
   m_dayStart = DayFloor(dayStart);
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   m_dayX = m_calX + 520 + 8; m_dayY = m_calY;
   if(m_dayX + 230 > chartW - 4) m_dayX = MathMax(0, m_calX - 238);
   DrawDay();
  }

void CStatsDashboard::CloseDay()
  {
   if(m_cvDayReady)   { m_cvDay.Destroy();   m_cvDayReady = false; }
   if(m_cvDayBgReady) { m_cvDayBg.Destroy(); m_cvDayBgReady = false; }
   m_dayOpen = false;
   DeleteByPrefix(SD_PFX + "DAY_");
  }

void CStatsDashboard::DayStep(int dir)
  {
   m_dayStart += dir * 86400;
   DrawDay();
  }

void CStatsDashboard::DrawDay()
  {
   DeleteByPrefix(SD_PFX + "DAY_");
   if(m_cvDayReady) { m_cvDay.Destroy(); m_cvDayReady = false; }
   int x = m_dayX, y = m_dayY, w = 230, h = 330;
   CreateBgCanvas(m_cvDayBg, m_cvDayBgReady, SD_PFX + "DAY_CVBG", x, y, w, h, 20);
   CvPanel(m_cvDayBg, w, h, 26);
   Lbl(SD_PFX + "DAY_TITLE", x + 10, y + 6, "▤  Daily Summary", m_t.text, 8, SD_F_BOLD, ANCHOR_LEFT_UPPER, 23);
   Btn(SD_PFX + "DAY_CLOSE", x + w - 26, y + 3, 22, 20, "✕", m_t.btn, m_t.btnText, 8);

   Lbl(SD_PFX + "DAY_DATE", x + 12, y + 36, TimeToString(m_dayStart, TIME_DATE), m_t.text, 9, SD_F_NUM, ANCHOR_LEFT_UPPER, 23);
   Btn(SD_PFX + "DAY_PREV", x + w - 56, y + 34, 22, 20, "‹", m_t.btn, m_t.btnText, 10);
   Btn(SD_PFX + "DAY_NEXT", x + w - 32, y + 34, 22, 20, "›", m_t.btn, m_t.btnText, 10);

   SDashMetrics dm; Compute(m_dayStart, m_dayStart + 86400, dm, false);
   double dp = (dm.balanceStart > 0.0) ? dm.net / dm.balanceStart * 100.0 : 0.0;

   // accent card
   int cy = y + 62;
   CvRRectBorder(m_cvDayBg, 10, cy - y, w - 20, 48, 8, m_t.accentDark, Mix(m_t.accent, m_t.hilite, 0.15), m_t.accent);
   m_cvDayBg.Update(false);
   Lbl(SD_PFX + "DAY_C1_L1", x + 10 + (w - 20) / 4, cy + 8,  "Percent",   Mix(m_t.accentText, m_t.accent, 0.3), 7, SD_F_REG, ANCHOR_CENTER, 23);
   Lbl(SD_PFX + "DAY_C1_V1", x + 10 + (w - 20) / 4, cy + 30, Pct(dp),     m_t.accentText, 10, SD_F_NUM, ANCHOR_CENTER, 23);
   Lbl(SD_PFX + "DAY_C1_L2", x + 10 + (w - 20) * 3 / 4, cy + 8,  "Total Net", Mix(m_t.accentText, m_t.accent, 0.3), 7, SD_F_REG, ANCHOR_CENTER, 23);
   Lbl(SD_PFX + "DAY_C1_V2", x + 10 + (w - 20) * 3 / 4, cy + 30, Money(dm.net), m_t.accentText, 10, SD_F_NUM, ANCHOR_CENTER, 23);

   // donuts canvas (drawdown + win rate)
   int dy = cy + 56, dw = w - 20, dh = 96;
   m_cvDay.CreateBitmapLabel(0, 0, SD_PFX + "DAY_CV", x + 10, dy, dw, dh, COLOR_FORMAT_ARGB_NORMALIZE);
   ObjectSetInteger(0, SD_PFX + "DAY_CV", OBJPROP_CORNER,     m_corner);
   ObjectSetInteger(0, SD_PFX + "DAY_CV", OBJPROP_BACK,       false);
   ObjectSetInteger(0, SD_PFX + "DAY_CV", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, SD_PFX + "DAY_CV", OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, SD_PFX + "DAY_CV", OBJPROP_ZORDER,     22);
   ObjectSetInteger(0, SD_PFX + "DAY_CV", OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   m_cvDayReady = true;
   m_cvDay.Erase(ToARGB(m_t.panel));
   double wr = (dm.trades > 0) ? (double)dm.wins / dm.trades : 0.0;
   // left: drawdown
   m_cvDay.FontSet(SD_F_BOLD, -85);
   m_cvDay.TextOut(dw / 4, 2, "Drawdown", ToARGB(m_t.dim), TA_CENTER | TA_TOP);
   DrawRing(m_cvDay, dw / 4, 56, 30, 22, MathMin(1.0, dm.maxDDPct / 100.0), m_t.neg, Mix(m_t.panel, m_t.dim, 0.35), m_t.panel);
   m_cvDay.FontSet(SD_F_NUM, -110);
   m_cvDay.TextOut(dw / 4, 56, DoubleToString(dm.maxDDPct, 0) + "%", ToARGB(m_t.text), TA_CENTER | TA_VCENTER);
   // right: win rate
   m_cvDay.FontSet(SD_F_BOLD, -85);
   m_cvDay.TextOut(dw * 3 / 4, 2, "Win Rate", ToARGB(m_t.dim), TA_CENTER | TA_TOP);
   DrawRing(m_cvDay, dw * 3 / 4, 56, 30, 22, wr, m_t.accent, Mix(m_t.panel, m_t.dim, 0.35), m_t.panel);
   m_cvDay.FontSet(SD_F_NUM, -110);
   m_cvDay.TextOut(dw * 3 / 4, 56, DoubleToString(wr * 100.0, 0) + "%", ToARGB(m_t.text), TA_CENTER | TA_VCENTER);
   m_cvDay.Update(false);

   // stats grid 2 x 3
   string gl[6] = {"Balance Start", "Total Trades", "Balance Now", "Total Pips", "Total Lots", "Wins"};
   string gv[6];
   gv[0] = Money(dm.balanceStart); gv[1] = Thousands(dm.trades, 0); gv[2] = Money(dm.balanceEnd);
   gv[3] = Thousands(dm.pips, 1);  gv[4] = DoubleToString(dm.lots, 2); gv[5] = Thousands(dm.wins, 0);
   int gy = dy + dh + 6, gw = (w - 20 - 6) / 2, gh = 32;
   for(int i = 0; i < 6; i++)
     {
      int c = i % 2, r = i / 2;
      int bx = x + 10 + c * (gw + 6), by = gy + r * (gh + 5);
      string base = SD_PFX + "DAY_G" + IntegerToString(i);
      Rect(base + "_BG", bx, by, gw, gh, m_t.card, m_t.border, 21);
      Lbl(base + "_L", bx + gw / 2, by + 5,  gl[i], m_t.dim, 6, SD_F_REG, ANCHOR_CENTER, 23);
      Lbl(base + "_V", bx + gw / 2, by + 20, gv[i], m_t.text, 8, SD_F_BOLD, ANCHOR_CENTER, 23);
     }
  }

//+------------------------------------------------------------------+
//| Click routing — returns true when the click belonged to the GUI     |
//+------------------------------------------------------------------+
bool CStatsDashboard::HandleClick(string name)
  {
   if(StringFind(name, SD_PFX) != 0) return false;
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   string tail = StringSubstr(name, StringLen(SD_PFX));

   //--- title bar buttons
   if(tail == "M_B_MIN")    { m_minimized = !m_minimized; m_dirty = true; return true; }
   if(tail == "M_B_THEME")  { m_dark = !m_dark; ApplyTheme(); m_dirty = true; return true; }
   if(tail == "M_B_LAYERS") { m_showLayers = !m_showLayers; m_dirty = true; return true; }
   if(tail == "M_B_CAL")    { if(m_calOpen) CloseCalendar(); else OpenCalendar(); m_dirty = true; return true; }
   if(tail == "M_B_PERIOD") { m_period = (ENUM_SD_PERIOD)((m_period + 1) % SD_PERIOD_COUNT); m_dirty = true; return true; }

   //--- DD toggle: title-bar button OR click on the donut canvas
   if(tail == "M_B_DD" || tail == "M_CV_DD") { m_showEquityDD = !m_showEquityDD; m_dirty = true; return true; }

   //--- symbol filter
   if(tail == "M_SYM_ALL_CB" || tail == "M_SYM_ALL_L" || tail == "M_SYM_SELALL")
     { for(int i = 0; i < m_symCount; i++) m_symOn[i] = true; m_dirty = true; return true; }
   if(tail == "M_SYM_UNSEL")
     { for(int i = 0; i < m_symCount; i++) m_symOn[i] = false; m_dirty = true; return true; }
   if(StringFind(tail, "M_SYM_CB_") == 0 || StringFind(tail, "M_SYM_L_") == 0)
     {
      int us = StringLen(tail) - 1;
      while(us > 0 && StringSubstr(tail, us, 1) != "_") us--;
      int idx = (int)StringToInteger(StringSubstr(tail, us + 1));
      if(idx >= 0 && idx < m_symCount) { m_symOn[idx] = !m_symOn[idx]; m_dirty = true; }
      return true;
     }

   //--- calendar
   if(tail == "CAL_CLOSE") { CloseCalendar(); m_dirty = true; return true; }
   if(tail == "CAL_PREV")  { CalendarStep(-1); return true; }
   if(tail == "CAL_NEXT")  { CalendarStep(+1); return true; }
   if(StringFind(tail, "CAL_D") == 0)
     {
      // CAL_D{cell}_{BG|N|P|C}
      int p1 = StringFind(tail, "_", 5);
      if(p1 > 5)
        {
         int cell = (int)StringToInteger(StringSubstr(tail, 5, p1 - 5));
         MqlDateTime d0; ZeroMemory(d0);
         d0.year = m_calYear; d0.mon = m_calMonth; d0.day = 1;
         datetime monthStart = StructToTime(d0);
         MqlDateTime dchk; TimeToStruct(monthStart, dchk);
         int firstCol = (dchk.day_of_week + 6) % 7;
         datetime dStart = monthStart + (cell - firstCol) * 86400;
         OpenDay(dStart);
        }
      return true;
     }
   if(StringFind(tail, "CAL_") == 0) return true; // any other calendar object: swallow

   //--- daily summary
   if(tail == "DAY_CLOSE") { CloseDay(); return true; }
   if(tail == "DAY_PREV")  { DayStep(-1); return true; }
   if(tail == "DAY_NEXT")  { DayStep(+1); return true; }
   if(StringFind(tail, "DAY_") == 0) return true;

   return true; // clicks on static panel parts are swallowed so the chart does not react
  }

//+------------------------------------------------------------------+
void CStatsDashboard::Destroy()
  {
   DestroyMainCanvases();
   if(m_cvDayReady)   { m_cvDay.Destroy();   m_cvDayReady = false; }
   if(m_cvDayBgReady) { m_cvDayBg.Destroy(); m_cvDayBgReady = false; }
   if(m_cvCalBgReady) { m_cvCalBg.Destroy(); m_cvCalBgReady = false; }
   DeleteByPrefix(SD_PFX);
   DeleteByPrefix("YANSTD_BTN_");
   ObjectDelete(0, LBL_LOT_DISPLAY);
   m_built = false;
  }

#endif // YANSTD_STATSDASHBOARD_MQH
