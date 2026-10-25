//+------------------------------------------------------------------+
//|                                                ControlPanel.mqh  |
//|          YANSTD EA — UI constants + OKX theme tokens             |
//+------------------------------------------------------------------+
#ifndef YANSTD_CONTROLPANEL_MQH
#define YANSTD_CONTROLPANEL_MQH
#include "..\Modules\Defines.mqh"

#define OKX_UI_PREFIX        "YANSTD_UI_"

// Trading-button names stay stable so OnChartEvent handlers do not change.
#define BTN_BUY_MARKET   "YANSTD_BTN_BUY"
#define BTN_SELL_MARKET  "YANSTD_BTN_SELL"
#define BTN_PASANG_LIMIT "YANSTD_BTN_LIMIT"
#define BTN_TP1_TOGGLE   "YANSTD_BTN_TP1"
#define BTN_CUT50        "YANSTD_BTN_CUT50"
#define BTN_HAPUS_ORDER  "YANSTD_BTN_HAPUS"
#define BTN_AUTO_TOGGLE  "YANSTD_BTN_AUTO"
#define BTN_CLOSE_ALL    "YANSTD_BTN_CLOSEALL"
#define BTN_LOT_MINUS    "YANSTD_BTN_LOTMINUS"
#define BTN_LOT_PLUS     "YANSTD_BTN_LOTPLUS"
#define BTN_RISK_05      "YANSTD_BTN_RISK05"
#define BTN_RISK_10      "YANSTD_BTN_RISK10"
#define BTN_RISK_15      "YANSTD_BTN_RISK15"
#define BTN_RISK_20      "YANSTD_BTN_RISK20"
#define BTN_CLEAR_WR     "YANSTD_BTN_CLEARWR"
#define BTN_MODE_SMC     "YANSTD_BTN_MODE2"
#define BTN_MODE_PURE    "YANSTD_BTN_MODE3"
#define LBL_LOT_DISPLAY  "YANSTD_LBL_LOT"

// Dark — OKX pitch black
#define OKX_D_BG         C'10,10,12'
#define OKX_D_CARD       C'18,18,22'
#define OKX_D_HOVER      C'26,26,32'
#define OKX_D_ACCENT     C'197,248,42'
#define OKX_D_SELL       C'241,54,112'
#define OKX_D_BUY        C'197,248,42'
#define OKX_D_TEXT       C'255,255,255'
#define OKX_D_MUTED      C'132,142,156'
#define OKX_D_BORDER     C'38,38,46'

// Light — OKX clean
#define OKX_L_BG         C'248,249,250'
#define OKX_L_CARD       C'255,255,255'
#define OKX_L_HOVER      C'240,242,245'
#define OKX_L_ACCENT     C'16,16,18'
#define OKX_L_SELL       C'224,43,96'
#define OKX_L_BUY        C'16,186,104'
#define OKX_L_TEXT       C'18,18,22'
#define OKX_L_MUTED      C'112,122,138'
#define OKX_L_BORDER     C'224,224,224'

#endif // YANSTD_CONTROLPANEL_MQH
