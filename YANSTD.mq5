//+------------------------------------------------------------------+
//|                                                      YANSTD.mq5  |
//|          SMC Algorithmic Trading Engine (optional MSNR overlay)   |
//|             (M15 Primary -> optional M5 -> M3 Sweep/CHoCH)       |
//|                     Version 4.52.0         |  2026-09-18          |
//|                    Single-pair | Semi-Auto & Full-Auto            |
//+------------------------------------------------------------------+
#property copyright   "YANSTD EA v4.52.0"
#property version     "4.52"
#property description "SMC execution + optional MSNR map: M5 refine -> M3 Sweep/CHoCH"
#property strict

//--- Include all modules
#include "Modules\Defines.mqh"
#include "Modules\FVGValidator.mqh"
#include "Modules\ZigZagEngine.mqh"
#include "Modules\SessionManager.mqh"
#include "Modules\NewsFilter.mqh"
#include "Modules\RiskCalculator.mqh"
#include "Modules\SpreadMonitor.mqh"
#include "Modules\OrderManager.mqh"
#include "Modules\PartialClose.mqh"
#include "Modules\TrailingStop.mqh"
#include "Modules\MTFTrendMeter.mqh"
#include "Modules\SmartBrain.mqh"
#include "Modules\SignalDiagnostics.mqh"
#include "Modules\MSNREngine.mqh"
#include "Modules\SignalEngine.mqh"
#include "GUI\StatsDashboard.mqh"

//+------------------------------------------------------------------+
//|  INPUT PARAMETERS                                                |
//+------------------------------------------------------------------+

//--- MSNR Primary Structure Layer
input group "=== MSNR Primary Structure Layer ==="
input int             InpMSNRScanBars         = 300;             // M15 Lookback Bars for MSNR Zones
input double          InpMSNROTEFibMin        = 0.618;           // OTE Fibo Min Threshold
input double          InpMSNROTEFibMax        = 0.786;           // OTE Fibo max / deep-entry threshold (classic 0.786)
input bool            InpRequireZoneOTE       = true;            // Strict OTE: formation and primary gate require 0.618-0.786 location
input ENUM_SETUP_MODE InpSetupMode            = SETUP_SMC_PRIMARY; // 2=SMC_PRIMARY (MSNR soft overlay); 3=PURE_SMC (no MSNR)

input group "=== King SNR (Layer 1: HTF -> M15 Mapping) ==="
input ENUM_TIMEFRAMES InpKingSNR_PrimaryTF    = PERIOD_H4;       // King SNR primary TF (priority / dominant bias)
input ENUM_TIMEFRAMES InpKingSNR_SecondaryTF  = PERIOD_H1;       // King SNR secondary/fallback TF (used only if primary has no active zone)
input int             InpKingSNR_LookbackBars = 150;             // King SNR HTF Candle Lookback
input bool            InpUseLayer2M15Gate     = true;            // Require Layer1 MSNR map x Layer2 SMC OB/FVG M15 overlap

//--- System & Execution
input group "=== System & Execution ==="
input ulong           InpMagicNumber          = 888999;          // Magic Number
input int             InpSlippage             = 30;              // Max Slippage (Points)
input bool            InpAutoTrading          = true;            // Auto Trading Mode (ON/OFF)
input int             InpTradeRetryAttempts   = 2;                // Fix backlog#3: Extra retry attempts on transient trade errors (0 = disabled)
input int             InpTradeRetryDelayMs    = 250;               // Fix backlog#3: Delay between retry attempts (ms)
input bool            InpEnablePushAlerts     = false;             // Push critical live alerts (configure terminal Notifications first)

//--- SMC Timeframe & Indicators
input group "=== SMC Timeframe & Indicators ==="
input ENUM_TIMEFRAMES inp_htf_period          = PERIOD_M15;      // HTF Bias Timeframe
input ENUM_TIMEFRAMES inp_mtf_period          = PERIOD_M5;       // MTF POI Zone Timeframe
input ENUM_TIMEFRAMES inp_ltf_period          = PERIOD_M3;       // LTF Trigger Timeframe
input bool            InpUseM5Refinement      = true;            // Refine M15 MSNR/SMC zones on M5 before M3 confirmation
input bool            InpRequireM5ContainedInM15 = true;         // Strict contain for V/A/OCL/SBR/RBS only; QML always overlap+ATR tolerance
input int             inp_m15_depth           = 12;              // ZigZag M15 Depth
input int             inp_m15_dev             = 5;               // ZigZag M15 Deviation
input int             inp_m15_back            = 3;               // ZigZag M15 Backstep
input int             inp_m5_depth            = 8;               // ZigZag M5 Depth
input int             inp_m5_dev              = 3;               // ZigZag M5 Deviation
input int             inp_m5_back             = 3;               // ZigZag M5 Backstep
input int             inp_m3_depth            = 5;               // ZigZag M3 Depth
input int             inp_m3_dev              = 2;               // ZigZag M3 Deviation
input int             inp_m3_back             = 2;               // ZigZag M3 Backstep
input int             InpStructureSwingWing   = 2;               // QML + King SNR fractal wing (not ZigZag halfD)
input int             InpFVGSwingWingLTF      = 3;               // FVG structure wing on native TF and H1
input int             InpFVGSwingWingHTF      = 2;               // FVG structure wing on H4

input int             InpCHoCHTransitionMaxBars = 12;           // M15 bars allowed for CHoCH -> confirming BOS

//--- Execution Mode
input group "=== Execution Mode ==="
input int                 InpLimitExpirationBars  = 30;                // Limit lifetime in execution bars (0 = GTC; not recommended for scalping)
input ENUM_TESTER_EXECUTION_MODE InpTesterExecutionMode = TESTER_MATRIX_OFF; // Tester: single best variant by default; use COLLECTION only for explicit variant research
input bool                InpStrictValidationLearning = false;          // Strict tester validation is read-only by default (prevents in-sample leakage)

//--- SMC Rules & Precision
input group "=== SMC Rules & Precision ==="
input double          inp_fvg_min_multiplier  = 1.5;             // FVG Gap (multiplier * Spread)
input double          InpFibMatchTolerance    = 0.030;           // Max ratio distance from 0.618/0.705/0.786
input string          InpEntryVariants        = "ALL";           // CSV/| whitelist: OB_15,OB_45,FVG_50,FIB_618,FIB_705,FIB_790
input double          InpVariantClusterMinATR = 0.50;            // H2: minimum sibling distance within one signal, in ATR units
input int             inp_zone_max_bars       = 96;              // M6: M5 POI age limit (0 = disable age expiry; 96 = 8 hours)
input int             InpPOIScanBars          = 1200;            // M5 bars scanned for historical OB/FVG candidates
input string          InpMinTradeGrade        = "D";             // Reject setups below this grade (S+,S,A+,A,B+,B,C+,C,D)
input double          inp_sl_buffer_pips      = 1.5;             // Buffer Stop Loss (Pips)
input int             inp_max_spread          = 800;             // Manual Hard-Cap Spread in Points (15 - 800 pts / 1.5 - 80.0 pips)
input double          InpMaxEntryDistanceATR  = 1.50;            // M5: do not park a limit farther than this x ATR(M5) from current price; 0 = disabled
input double          InpMinSLPips            = 0.0;             // Last-resort pip floor (0 = off; ATR bounds preferred)
input bool            InpUseATRStopBounds     = true;            // Bound SL with ATR instead of pip-only 25-70
input bool            InpRejectOutOfBoundsSL  = false;           // Gen-6A: reject instead of fabricating an in-bound stop
input double          InpSLMinATRMult         = 0.35;            // Widen SL if tighter than this x ATR
input double          InpSLMaxATRMult         = 2.50;            // Cap SL if wider than this x ATR
input double          InpMaxSLPips            = 0.0;             // Last-resort pip ceiling (0 = off; ATR bounds preferred)
input int             InpPOIInvalidationCloses = 2;              // Consecutive LTF closes required to invalidate a POI
input double          InpPOIInvalidationBufferPips = 8.0;        // Close buffer beyond POI before invalidation

//--- Dynamic Spread Auto-Detection
input group "=== Dynamic Spread Auto-Detection ==="
input bool            InpUseDynamicSpread     = true;            // Auto-detect broker spread baseline (adaptive threshold)
input int             InpDynamicSpreadSamples = 200;             // Rolling Tick Sample Size for Broker Spread Baseline
input double          InpDynamicSpreadStdDevMult = 3.0;          // Threshold = Mean + N x StdDev of Recent Spread
input int             InpDynamicSpreadFloor   = 15;              // Minimum Adaptive Threshold (Points), never tighter than this
                                                                   // Adaptive threshold is always clamped <= inp_max_spread (hard cap)

//--- Risk Management & Dynamic Scaling
input group "=== Risk Management & Scaling ==="
input bool            InpMultiLayerEntry      = false;           // Sequential multi-layer entries (off = one thesis per setup)
input double          InpRiskPercent          = 1.5;             // Base Risk Per Trade (%) (when Multi-Layer disabled)
input bool            InpUseDynamicRisk       = true;            // Enable 0.50x Brain risk reduction for sufficiently evidenced negative buckets; never blocks entry
input double          InpFixedLot             = 0.0;             // Fixed Lot (0 = use Risk %)
input double          InpMaxLot               = 0.0;             // Absolute max lot per order (0 = disabled; enforced BEFORE broker max)
input bool            InpAllowSingleExitFallback = true;         // Trade as one exit when lot is too small for the 50/25/25 split
input bool            InpScanAllPOIsWhenNoTrigger = true;        // Direct-zone mode: scan valid POIs without an M3 trigger; M3 sweep/CHoCH remains a quality bonus
input int             InpMaxActivePositions   = 1;               // Max concurrent positions (1 = single thesis)
input double          InpMultiPosMinDistPips  = 40.0;            // Min Distance for Independent Signals (Pips)
input double          InpMaxAggregateRiskPct  = 5.0;             // Combined open+pending risk cap (0=off). Grade multiplier now tops out at 2.0x
input bool            InpRejectBelowMinLot    = false;           // true = reject entry instead of clamping below broker min lot

//--- SmartBrain AI Memory
input group "=== SmartBrain AI Memory ==="
input bool            InpUseSmartBrain        = true;            // Enable SmartBrain learning and lot weighting (never entry gating)
input double          InpMinAIConfidence      = 42.0;            // Proven weak bucket below this caps lot at 0.50x
input bool            InpAILearning           = true;            // Continuous Reinforcement Learning
input ENUM_BRAIN_TEST_SOURCE InpTesterBrainSource = BRAIN_TEST_REALTICK; // Select the actual tester tick model
input string          InpBrainInstrumentKey   = "XAUUSD";        // Portable normalized database key across broker symbol suffixes
input bool            InpBrokerSpecificLiveBrain = true;         // Separate LIVE calibration per broker; RT/OHLC baseline stays portable
input bool            InpDataCollectionMode   = false;           // Historical tester exploration only; ignored for real demo/live orders
input int             InpCollectionMaxPositions = 8;             // Hedging-only concurrent positions while collecting samples
input int             InpCollectionMaxPending = 8;               // Maximum independent pending POIs while collecting samples
input double          InpCollectionRiskPct    = 0.10;            // Small risk per exploration position
input bool            InpCollectionAllSessions= true;            // Collect session buckets outside normal trade hours
input double          InpBrainDecayHalfLifeDays = 1095.0;        // Bucket confidence half-life (days); 1095 = 3 years
input double          InpQAlpha                = 0.15;            // Tabular Q-learning rate alpha (0-1)
input double          InpQGamma                = 0.90;            // Q-learning discount gamma (terminal trades bootstrap to zero)
input int             InpQMinUpdates           = 8;               // Min weighted Q observations before SKIP may reduce lot
input double          InpQRewardClip           = 2.0;             // Clamp reward in R units to prevent outlier domination
input double          InpBrainMinRewardRisk    = 1.00;            // AUDIT (#9): diagnostic-only floor -- logged via bucket avgMFER, NOT enforced anywhere; does not cap sizing or block entries
input double          InpBrainLiveWeight       = 1.00;            // LIVE evidence weight in forward/live fusion
input double          InpBrainRealTickWeight   = 0.70;            // Real-tick baseline weight in forward/live fusion
input double          InpBrainOHLCWeight       = 0.30;            // OHLC baseline weight in forward/live fusion
input bool            InpBrainEventJournal     = true;            // Append every TAKE/SKIP result to segmented raw-event storage
input bool            InpBrainEventJournalInTester = false;       // Allow event journal in non-visual tester (off keeps protocol runs light)
input int             InpBrainJournalSegmentMB = 64;              // Maximum event segment size before automatic rotation
input int             InpDiagnosticIntervalMinutes = 60;           // Live rejection-funnel summary interval (0=deinit only)
input ENUM_LOG_LEVEL  InpLogLevel                = LOG_LEVEL_INFO; // L5: ERROR/WARN/INFO/DEBUG
input datetime        InpOOSStart               = 0;               // L3: UTC/server timestamp boundary for OOS attribution (0 = no split)

//--- Protection & Safety Filters
input group "=== Protection & Safety Filters ==="
input bool            InpFridayCloseEnabled   = true;            // Close All on Friday Night
input int             InpFridayCloseHour      = 20;              // Friday Auto-Close Hour (UTC)
input double          InpMaxDailyLossPct      = 10.0;            // Daily Max Loss Limit % (0 = Disabled; blocks new entries until UTC day rollover)
input double          InpMaxEquityDDPct        = 0.0;             // L2: peak-equity drawdown circuit breaker (0 = Disabled for research)
input double          InpMarginSafetyBufferPct = 20.0;            // Fix R1: Required free-margin cushion above OrderCalcMargin (%)
input double          InpMinMarginLevelPct    = 200.0;            // Fix R1: Block NEW entries below this Margin Level % (0 = Disabled)
input bool            InpUseNewsFilter        = true;            // Enable News Auto-Pause
input int             InpNewsPreMinutes       = 30;              // Block Minutes Before News
input int             InpNewsPostMinutes      = 30;              // Block Minutes After News
input bool            InpNewsHighOnly         = true;            // Only High-Impact Events
input bool            InpNewsTesterSimulate   = true;            // M4: build a synthetic NFP/CPI/FOMC calendar in the tester (false = old always-CLEAR bypass)
input string          InpFomcDatesOverride    = "";              // Optional exact UTC dates: YYYY-MM-DD,YYYY-MM-DD
input ENUM_NEWS_POSITION_ACTION InpNewsLivePositionAction = NEWS_POSITION_PARTIAL_CLOSE; // M4: reduce open exposure during NEWS_LIVE
input double          InpNewsLivePartialPct   = 50.0;             // Position volume closed when action=PARTIAL_CLOSE

//--- Session & Time Filtering
input group "=== Session & Time Filtering ==="
input bool            InpUseTimeFilter        = true;            // Enable Session Time Filter
input bool            InpRequireKillzone      = true;            // Require ICT Killzone (London 07-10 UTC / NY 12-14 UTC) for entry
input bool            InpBlockOverlapSession  = false;           // Block entries during London+NY Overlap (13-17 UTC)
input ENUM_TIME_FILTER_MODE InpTimeFilterMode = TIME_FILTER_ROLLOVER_HOLE; // default all 3 modes: block 20-23 UTC
input int             InpStartHourUTC         = 7;               // WINDOW: trade start hour UTC
input int             InpEndHourUTC           = 19;              // WINDOW: trade end hour UTC
input int             InpRolloverBlockStartUTC= 20;              // HOLE: block from this UTC hour (03:00 WIB)
input int             InpRolloverBlockEndUTC  = 23;              // HOLE: block until this UTC hour (06:00 WIB)
input int             InpFridayCutoffHour     = 15;              // Friday No New Entries After Hour (UTC)
input int             InpPauseBarsAfterUnexpectedGap = 4;        // M3 bars with no new entry after unexpected gap (0=off)
input bool            InpBlockSundayOpen      = true;            // M2: block new entries during the Sunday re-open gap
input int             InpSundayOpenBlockHours = 2;               // M2: UTC hours after Sunday open with no new entries
input int             InpTesterUTCOffsetWinter= 0;               // Tester Broker UTC Offset (Winter)
input bool            InpTesterUseEuropeanDST = false;           // Tester Broker Uses EU DST (+1 Summer)

//--- Loss Reduction / Market Quality
input group "=== Loss Reduction & Market Quality ==="
input bool            InpUseADXGuard           = true;            // Use M15 ADX as a soft quality feature (never a standalone veto)
input bool            InpADXHardGateOnMode0    = false;           // deprecated: was HYBRID-only (mode 0 removed); inert, kept for preset schema
input int             InpADXPeriod             = 14;              // M15 ADX period
input double          InpMinADX                = 20.0;            // Minimum M15 ADX
input double          InpADXSoftPenalty        = 10.0;            // Maximum soft-score penalty below Min ADX
input bool            InpUseATRSpreadGate      = true;            // Spread must be <= configured fraction of M5 ATR
input int             InpATRSpreadPeriod       = 14;              // M5 ATR period used by spread gate
input bool            InpUseMinimumRRRGate     = true;           // SMC+MSNR+SMC decides entry; also enforce minimum structural RR if ON
input double          InpMinimumStructuralRRR  = 1.10;            // Kept for legacy STAGED/FIXED_RR only; ignored when gate is off
input bool            InpUseTimeInvalidation   = true;            // Close stagnant positions after configured M5 bars
input int             InpTimeInvalidationBarsM5 = 16;             // Maximum M5 bars without meaningful displacement
input double          InpTimeInvalidationMinRR = 0.7;             // Do not invalidate after position has reached this R
input double          InpDisplacementATRFrac   = 0.35;            // Meaningful favorable displacement = fraction of M5 ATR
input bool            InpUseM3StructureTrailAt1R = false;         // RR structure-trail; off when using structural POI exits
input double          InpStructureTrailStartRR = 1.2;             // R2d: structure trail starts after TP1 (1.5->1.2 to match lowered TP1RR); 1R only protects BE+spread
input double          InpStructureTrailBufferATR = 0.75;          // R3a: breathing room below M3 pivot = ATR(TrailSwingTF,14) * this (0 = old glued-to-pivot behavior; higher = runner survives deeper pullbacks toward its 1.69R avg MFE)
input bool            InpUseSecondaryBOSScaleIn = true;           // Position #2+ requires protected Position #1 and fresh M3 BOS

//--- Take Profit & Trailing Stop
input group "=== Take Profit & Trailing Stop ==="
input ENUM_EXIT_MODE  InpExitMode             = EXIT_STRUCTURAL_POI; // STRUCTURAL=TP at M15 opposing POI; optional 50% at +80 pips
input double          InpFixedRR              = 2.0;             // Full-position TP in R when InpExitMode=FIXED_RR (unused in STRUCTURAL)
input bool            InpUseEarlyBEP          = false;           // Stage 1: Enable early BEP protection
input double          InpEarlyBEPPips         = 50.0;            // Stage 1: Early BEP trigger distance
input int             InpEarlyBEPBuffer       = 5;               // Stage 1: Early BEP buffer
input bool            InpUseTP1               = true;            // STRUCTURAL: at +80 pips close down to 0.01 runner
input double          InpTP1RR                = 0.9;             // Legacy STAGED only
input double          InpTP1ClosePct          = 50.0;            // Legacy STAGED only; STRUCTURAL leaves 0.01 runner
input double          InpTP2RR                = 1.6;             // Legacy STAGED only
input double          InpTP2ClosePct          = 25.0;            // Legacy STAGED only
input double          InpEmergencyServerTPRR  = 0.0;             // Disabled in STRUCTURAL (broker TP = POI target)
input double          InpPoiPartialPips       = 80.0;            // At this distance close all but 0.01; runner keeps target or stays open
input double          InpMinRunnerInitialLot  = 0.04;            // Below this / 0.01 lot: no partial, full TP to POI target
input int             InpTP1ProfitLockPips    = 0;               // After 80-pip partial: SL to break-even (0 = exact BE)
input bool            InpAutoRoundLot         = true;            // Round staged volumes to broker step
input bool            InpUseTrailing          = false;           // Off in STRUCTURAL â€” remainder runs to POI target
input ENUM_TIMEFRAMES InpTrailSwingTF         = PERIOD_M5;       // Runner swing timeframe
input int             InpTrailSwingLeftBars   = 2;               // Closed candles left of pivot
input int             InpTrailSwingRightBars  = 2;               // Closed candles right of pivot
input double          InpTrailSwingBufferPips = 10.0;            // XAU: 10 pips = 1.0 price buffer

//--- Advanced Institutional Optimizations (Points 1, 2, 3, 4)
input group "=== Advanced Institutional Optimizations ==="
input bool            InpUseDynamicSLBuffer   = true;            // Point 1: Volatility-Adaptive Stop Loss Buffer (ATR)
input double          InpSLATRMult            = 0.50;            // SL buffer beyond structural swing = ATR(14) * this (ATR Engine)
input bool            InpUseMilestoneLock     = false;           // RR milestone lock; off when using structural POI exits
input double          InpMilestoneTriggerR    = 1.50;            // H6: trigger milestone by initial-risk multiple, not fixed pips
input double          InpMilestoneLockR       = 0.50;            // H6: lock this many R beyond entry
input double          InpMilestoneTriggerPips = 120.0;           // Legacy fallback only when InpMilestoneTriggerR <= 0
input int             InpMilestoneLockPips    = 60;              // Legacy fallback only when InpMilestoneLockR <= 0
input bool            InpUseOpposingPOIExit   = false;           // Point 3: Exit / Partial Early on Opposing Order Block
input double          InpOpposingMinProfitPips= 20.0;            // Point 3: Opposing Exit Min Profit Threshold (Pips)


input group "=== ATR Dynamic Engine ==="
input int             InpATRPeriod            = 14;              // ATR period for all dynamic distance calculations
input double          InpMinFVG_ATR_Mult      = 0.30;            // FVG min gap = ATR(TF,14) * this (mechanical gate)
input int             InpMaxFVGBarAge         = 36;              // FVG older than this many bars on its TF is invalid
input int             InpMaxOBBarAge          = 0;               // Layer-2 OB age cap in M15 bars; 0 = unlimited (classic SMC)
input bool            InpOBRequireOppositeColor = false;         // true = OB base candle must be opposite the displacement color
input double          InpFVGImpulseBodyRatio  = 0.70;            // Candle-2 body / range minimum (impulse filter)
input bool            InpRequireFVGStructureOverlap = true;      // Entry FVG must overlap swing / SBR-RBS / HTF or psych level
input double          InpProximityATRMult     = 0.25;            // MSNR zone touch/mitigation tolerance = ATR(14) * this
input double          InpTrailBEATRMult       = 1.00;            // Break-even trigger: activate when profit >= ATR(14) * this
input double          InpTrailDistATRMult     = 1.50;            // Runner trailing distance behind price/swing = ATR(14) * this
input double          InpMaxSpreadATRMult     = 0.25;            // Max spread = ATR(M5,14) * this, clamped [floor, hard cap] (0 = disable)
input double          InpSpreadCapFloorPips   = 3.5;             // Spread cap never tighter than this (pips; XAU 3.5 pip = $0.35) â€” broker's normal spread must fit

//--- Institutional High-Winrate SMC Filters
input group "=== Institutional High-Winrate SMC Filters ==="
input bool            InpUseLiquiditySweep    = true;            // Enable confirmed liquidity-sweep confidence boost
input bool            InpRequireM3Sweep       = true;            // Tahap 4: M3 sweep AND CHoCH are a joint gate (false = CHoCH-only, sweep is score boost)
input bool            InpUseOTEFilter         = true;            // Enable expanded OTE (61.8% - 86.6%) zone boost

input double          InpMinimumSoftScore     = 45.0;             // Minimum combined score for normal-bias scalp
input bool            InpAllowCounterBias     = true;             // Evaluate opposite side after M15 structure stagnates
input int             InpCounterBiasStagnationBars = 16;          // M15 bars unchanged before counter-bias evaluation
input double          InpCounterBiasMinScore  = 75.0;             // Stricter score required for opposite-bias scalp

//--- Zone Visualization & GUI
input group "=== Visualization & GUI ==="
input bool            InpShowZoneBoxes        = true;            // Draw Order Block (OB) Boxes on Chart
input bool            InpShowFVGBoxes         = true;            // Draw Fair Value Gap (FVG) Boxes on Chart
input bool            InpShowStructureLines   = true;            // Draw HH/HL/LH/LL + BOS/CHoCH + Equilibrium
input bool            InpShowMSNRMap          = true;            // Draw MSNR HTF map (King/A/V/OCL/QML/SBR/RBS)
input bool            InpShowFibLevels        = true;            // Draw formation Fib 0.618 / 0.705 / 0.786
input bool            InpShowM3Refine         = true;            // Draw last accepted M3 OB/FVG refinement

input color           InpDemandColor          = clrLime;         // Fresh Demand Zone Color
input color           InpSupplyColor          = clrRed;          // Fresh Supply Zone Color
input color           InpFVGBullColor         = clrAqua;         // Bullish FVG Color
input color           InpFVGBearColor         = clrOrange;       // Bearish FVG Color
input color           InpBOSColor             = clrGold;         // BOS / CHoCH Structure Line Color
input color           InpEQColor              = clrDarkGray;     // 50% Equilibrium Line Color
input bool            InpShowDashboard        = true;            // Show Stats Dashboard
input int             InpDashboardX           = 10;              // Dashboard X Position
input int             InpDashboardY           = 25;              // Dashboard Y Position
input bool            InpDashboardDark        = true;            // Dashboard Theme: Dark (false = Light)

//+------------------------------------------------------------------+
//|  GLOBAL OBJECTS & STATE                                          |
//+------------------------------------------------------------------+

//--- Module instances
CSessionManager  g_session;
CNewsFilter      g_news;
CRiskCalculator  g_risk;
CSpreadMonitor   g_spreadMonitor;
COrderManager    g_orders;
CPartialClose    g_partial;
CTrailingStop    g_trail;

CSmartBrain      g_brain;
CMSNREngine      g_msnr;
CSignalEngine    g_signal;
CMTFTrendMeter   g_mtf;             // MTF confluence engine
CSignalDiagnostics g_diagnostics;
CEntryVariantWhitelist g_entryVariants;
CStatsDashboard  g_dashboard;      // GUI v3: performance stats only (no pipeline state)
ENUM_TIMEFRAMES  g_effectiveRefinementTF = PERIOD_CURRENT; // set in OnInit()
ENUM_AUTO_MODE   g_autoMode     = AUTO_ON;
bool             g_tp1Enabled   = true;
double           g_lotDisplay   = 0.01;
bool             g_lotManual    = false;   // +/- lot stepper; OnTimer must not overwrite
double           g_riskDisplay  = 1.5;
SStats           g_stats;
// H9: raised by OnTradeTransaction when a deal belonging to THIS EA (magic +
// symbol) lands, and consumed by UpdateStatsFromHistory. This replaces the old
// "did HistoryDealsTotal() change?" trigger, which could only be answered AFTER
// paying for HistorySelect(0, now) -- the very call the guard was supposed to
// avoid. Starts true so the first call always builds a baseline. Declared here
// (rather than next to UpdateStatsFromHistory further down) so it is visible
// to OnChartEvent()'s BTN_CLEAR_WR handler, which also needs to set it.
bool             g_statsHistoryDirty = true;

// M4: persistent per-position accumulators for UpdateStatsFromHistory(). These
// used to be local arrays rebuilt from a full HistorySelect(0, now) scan on
// almost every deal, which made total work O(N^2) over a long backtest's
// deal history. They now live for the lifetime of the EA/test run and are
// updated one deal at a time by ApplyStatsDeal(), so each new deal costs O(1)
// (amortized) instead of O(total deals so far). RebuildStatsHistoryFull() is
// the only place that still walks the full deal history, and it is reserved
// for startup, recovery, and manual stats reset -- never the per-deal path.
bool             g_statsHistoryBuilt = false;
ulong            g_statsPosIds[];
double           g_statsPosProfit[];
datetime         g_statsPosCloseTime[];
bool             g_statsPosHasExit[];
bool             g_statsPosCounted[];       // already folded into g_stats totals?
int              g_statsPosType[];          // POSITION_TYPE_BUY / SELL from first entry deal
double           g_statsPosOpenPxVolSum[];  // Sum(openPrice * volume) across entry deals
double           g_statsPosOpenVol[];
double           g_statsPosExitPxVolSum[];  // Sum(exitPrice * volume) across exit deals
double           g_statsPosExitVol[];
int              g_statsPosCount    = 0;
bool             g_statsPosIdsSorted = true;
// Bounded (per-day) list of trades already folded into today's totals, kept
// so a session change with NO new deal can re-tally sessionWins/sessionLosses
// against today's trades only -- instead of rescanning the whole deal history.
int              g_statsTodaySess[];
bool             g_statsTodayWin[];
int              g_statsTodayCount  = 0;
// Cursor of the most recently processed deal; maintained for drift
// verification, not required for correctness of the incremental path itself.
datetime         g_statsLastDealTime   = 0;
ulong            g_statsLastDealTicket = 0;
datetime         g_statsRollLastDayUTC = 0;
int              g_statsRollLastSessKey = -1;
SSignal          g_lastSignal;     // display-only snapshot for the dashboard Signal card
SSignal          g_matrixTriggerContext;
bool             g_hasMatrixTriggerContext = false;

SPositionInfo    g_posInfo;
bool             g_hasPosition  = false;

//--- Dynamic Spread Auto-Detection: live effective threshold (points), updated every tick
int              g_effectiveMaxSpreadPts = 800;
int              g_adxM15Handle = INVALID_HANDLE;
int              g_atrM5Handle  = INVALID_HANDLE;
datetime         g_lastConsumedScaleBOS = 0;

//--- Bar Tracking for High-Performance Optimization
datetime         g_lastHTFBarTime = 0;
datetime         g_lastMTFBarTime = 0;
datetime         g_lastLTFBarTime = 0;
int              g_gapPauseBarsLeft = 0;
datetime         g_lastNewsPoll   = 0;
datetime         g_lastEntryTime  = 0;
// M1: same-direction re-entry cooldown. Set when an entry is placed; a new
// same-direction entry is blocked for the next N LTF bars. Opposite-direction
// entries are unaffected (that is a reversal, not churn).
datetime         g_lastEntryBarTime    = 0;
int              g_lastEntryDirection  = -1;   // +1 buy, -1 sell
#define SAME_DIRECTION_REENTRY_COOLDOWN_BARS 12
// M0: bounded score bonus for an M3-confirmed context (soft, never a gate).
#define M3_CONFIRMED_SOFT_BONUS 8.0
datetime         g_lastGenerateSignalTime = 0;
datetime         g_lastGenerateSignalBar  = 0;
long             g_lastPoiRevision        = -1;
int              g_lastPendingCount       = -1;
ENUM_TARGET_SOURCE g_lastPlanTargetSource = TARGET_NONE;

// H10: how often the callers ASK CNewsFilter to refresh, which is NOT how often a
// refresh actually happens. CNewsFilter owns the real throttle: 1 hour after a
// successful read, but on a FAILED CalendarValueHistory() it rewinds its own timer
// (m_lastRefresh = now - 3300) specifically to allow a retry 5 minutes later.
// The callers used their own 3600 s gate, so RefreshEvents() was never called again
// inside that hour and the 5-minute retry was unreachable dead code. Consequence on
// a live account whose terminal/broker cannot serve the calendar: GetStatus()
// returns NEWS_ERROR, and the news block deletes every pending order and refuses
// new entries -- for a full hour after a single transient failure, repeating
// forever. Polling at the RETRY granularity lets the filter's own logic decide.
#define YANSTD_NEWS_POLL_SECONDS 300

//--- Kill-switch confirmation state
bool             g_closeAllPending = false;
ulong            g_closeAllTick    = 0;
bool             g_multiLayerAllowed = true;
int              g_effectiveMaxPositions = 1;
bool             g_effectiveCollectionMode = false; // Historical tester only; never real demo/live orders

// Matrix orders fill after their sibling-placement loop. Keep the exact
// successful sibling count by setup event until the fill copies it into the
// persistent position track. ponytail: 256 slots exceed the maximum number of
// live/pending scalp clusters; use a dynamic map only if GTC matrix orders are introduced.
#define MATRIX_WEIGHT_EVENT_SLOTS 256
ulong            g_matrixWeightEventIds[MATRIX_WEIGHT_EVENT_SLOTS];
int              g_matrixWeightSiblingCounts[MATRIX_WEIGHT_EVENT_SLOTS];
int              g_matrixWeightNext = 0;

// Forward declarations
void UpdateStatsFromHistory();
void RebuildStatsHistoryFull();  // M4: full-history fallback -- startup/recovery/manual reset only
void OnStatsDealArrived(ulong dealTicket); // M4: O(1) per-deal stats hot path
void OnNewHTFBar();
void OnNewMTFBar();
void OnNewLTFBar();
void TryAutoEntry();
void TryAutoLimitFallback();
// Gen-6C M1: blocks a same-direction re-entry inside the cooldown window.
// Opposite direction is always allowed (that is a reversal, not churn).
bool SameDirectionReentryBlocked(const ENUM_ORDER_TYPE orderType)
  {
   if(SAME_DIRECTION_REENTRY_COOLDOWN_BARS <= 0 || g_lastEntryBarTime <= 0) return false;
   const int dir = (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT) ? 1 : -1;
   if(dir != g_lastEntryDirection) return false;
   const int barsSince = iBarShift(Symbol(), inp_ltf_period, g_lastEntryBarTime, false);
   return (barsSince >= 0 && barsSince < SAME_DIRECTION_REENTRY_COOLDOWN_BARS);
  }
void NoteEntryDirection(const ENUM_ORDER_TYPE orderType)
  {
   g_lastEntryBarTime   = iTime(Symbol(), inp_ltf_period, 0);
   g_lastEntryDirection = (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT) ? 1 : -1;
  }

bool ManageAutoLimitOrders(int requestedVariant = -1, int requiredPoiIndex = -1, string entryPath = "DIRECT");
void ReconcilePOIPendingFlags();
bool HasEquivalentPendingOrder(ENUM_ORDER_TYPE orderType, ENUM_SMC_ENTRY_TYPE setupType, double orderPrice);
bool HasCorrelatedPendingOrder(ENUM_ORDER_TYPE orderType, double orderPrice, double minDistance);
void ExecuteBuy(const SSignal &sig);
void ExecuteSell(const SSignal &sig);
double ResizeLotForMarketFill(const SSignal &sig, ENUM_ORDER_TYPE type, double &fillRef);
void UpdatePositionState();
void UpdatePositionExcursion(SPositionInfo &pos);
void LogUTCOffsetSelfCheck();
string SessionLabel(ENUM_SESSION_TYPE sess);
void UpdateLotFromRisk();
bool CanAddAggregateRisk(ENUM_ORDER_TYPE orderType, double lots, double entryPrice,
                         double slPrice, double &projectedRiskPct);
void ManageNewsLivePositions(ENUM_NEWS_STATUS status);
int  GetCandleSecondsLeft(ENUM_TIMEFRAMES tf);
bool ValidateInputs();
bool IsHistoricalMatrixTest();
bool IsVariantAllowed(ENUM_SMC_ENTRY_TYPE variant, long diagKey);
ulong BuildSetupEventId(const SSignal &sig);
void RegisterMatrixSiblingCount(ulong eventId, int siblingCount);
int GetMatrixSiblingCount(ulong eventId);
double ReadIndicatorValue(int handle, int buffer = 0, int shift = 1);
double GetStructuralTarget(double entryPrice, ENUM_ZONE_TYPE side);
double GetStructuralTarget(double entryPrice, ENUM_ZONE_TYPE side, ENUM_TARGET_SOURCE &source);
bool PlanStructuralTP(const double entryPrice, const bool isBuy, const ENUM_ZONE_TYPE side,
                      const double pip, const int digits,
                      double &serverTP, double &tp1, double &tp2,
                      double &tp1Pct, double &tp2Pct, const double slDistance = 0.0);
void RecoverOpenPositionTargets();
void RecoverStructuralTargets();
void RecoverFixedRRTargets();
void RecoverStagedTargets();
bool ShouldRunGenerateSignal();
void MarkGenerateSignalRan();
void NoteLotStatus(const ENUM_LOT_SIZE_STATUS status);
bool PassEntryMarketQuality(long diagKey);
bool ApplyTimeInvalidation(SPositionInfo &pos);
void ApplyM3StructureProtection(SPositionInfo &pos);
bool CanSecondaryScaleIn(ENUM_ZONE_TYPE side, datetime &bosTime);

bool IsHistoricalMatrixTest()
  {
   return (bool)MQLInfoInteger(MQL_TESTER) &&
          !(bool)MQLInfoInteger(MQL_FORWARD) &&
          InpTesterExecutionMode == TESTER_MATRIX_COLLECTION;
  }

bool IsVariantAllowed(ENUM_SMC_ENTRY_TYPE variant, long diagKey)
  {
   if(g_entryVariants.IsAllowed(variant)) return true;
   g_diagnostics.Record(REJECT_VARIANT_NOT_ALLOWED, diagKey);
   return false;
  }

ulong BuildSetupEventId(const SSignal &sig)
  {
   SMC_Zone poi;
   datetime zoneTime = 0;
   if(sig.zoneIndex >= 0 && g_signal.GetPOI(sig.zoneIndex, poi)) zoneTime = poi.createTime;
   // A setup is born on the last CLOSED LTF confirmation candle.  Do not use
   // sig.signalTime here: it changes on every evaluation tick and previously
   // allowed one structural setup to be registered as many shadow samples.
   datetime triggerBarTime = iTime(Symbol(), inp_ltf_period, 1);
   if(triggerBarTime <= 0)
     {
      int periodSeconds = PeriodSeconds(inp_ltf_period);
      triggerBarTime = (periodSeconds > 0)
                       ? (datetime)(((long)sig.signalTime / periodSeconds) * periodSeconds)
                       : sig.signalTime;
     }
   double tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   ulong priceKey = (tick > 0.0) ? (ulong)MathRound(sig.entryPrice / tick) : 0;
   ulong key = (ulong)triggerBarTime;
   key ^= ((ulong)zoneTime << 7);
   key ^= (priceKey << 17);
   key ^= ((ulong)(sig.zoneIndex + 1) << 3);
   key ^= ((ulong)((int)sig.direction + 2) << 29);
   key ^= (key >> 23);
   key *= (ulong)2654435761;
   key ^= (key >> 17);
   key = (key & (ulong)0x7FFFFFFF) + 1;
   return key;
  }

void RegisterMatrixSiblingCount(ulong eventId, int siblingCount)
  {
   if(eventId == 0 || siblingCount <= 0) return;
   for(int i = 0; i < MATRIX_WEIGHT_EVENT_SLOTS; i++)
     {
      if(g_matrixWeightEventIds[i] != eventId) continue;
      g_matrixWeightSiblingCounts[i] = MathMin(MATRIX_MAX_CANDIDATE_COUNT,
                                                g_matrixWeightSiblingCounts[i] + siblingCount);
      return;
     }
   g_matrixWeightEventIds[g_matrixWeightNext] = eventId;
   g_matrixWeightSiblingCounts[g_matrixWeightNext] = siblingCount;
   g_matrixWeightNext = (g_matrixWeightNext + 1) % MATRIX_WEIGHT_EVENT_SLOTS;
  }

int GetMatrixSiblingCount(ulong eventId)
  {
   if(eventId == 0) return 0;
   for(int i = 0; i < MATRIX_WEIGHT_EVENT_SLOTS; i++)
      if(g_matrixWeightEventIds[i] == eventId)
         return g_matrixWeightSiblingCounts[i];
   return 0;
  }

double ReadIndicatorValue(int handle, int buffer = 0, int shift = 1)
  {
   bool ok = false;
   double value = ReadIndicatorValueSafe(handle, buffer, shift, ok);
   return ok ? value : 0.0;
  }

double GetStructuralTarget(double entryPrice, ENUM_ZONE_TYPE side)
  {
   ENUM_TARGET_SOURCE ignored = TARGET_NONE;
   return GetStructuralTarget(entryPrice, side, ignored);
  }

double GetStructuralTarget(double entryPrice, ENUM_ZONE_TYPE side, ENUM_TARGET_SOURCE &source)
  {
   source = TARGET_NONE;
   double target = g_msnr.GetNearestOpposingTarget(entryPrice, side);
   const bool isBuy = (side == ZONE_DEMAND);
   if(TargetPriceValid(entryPrice, isBuy, target))
     {
      source = TARGET_RECALCULATED_MSNR;
      return target;
     }
   if(isBuy)
     {
      double high = g_signal.GetM15SwingHigh();
      if(TargetPriceValid(entryPrice, true, high))
        {
         source = TARGET_M15_SWING;
         return high;
        }
      source = TARGET_NONE;
      return 0.0;
     }
   double low = g_signal.GetM15SwingLow();
   if(TargetPriceValid(entryPrice, false, low))
     {
      source = TARGET_M15_SWING;
      return low;
     }
   source = TARGET_NONE;
   return 0.0;
  }

void NoteLotStatus(const ENUM_LOT_SIZE_STATUS status)
  {
   if(status == LOT_STATUS_CLAMP)
      g_diagnostics.RecordLotClamp();
   else if(status == LOT_STATUS_FALLBACK)
      g_diagnostics.RecordLotFallback();
  }

bool ShouldRunGenerateSignal()
  {
   datetime m3Bar = iTime(Symbol(), inp_ltf_period, 0);
   long poiRev = g_signal.GetPoiRevision();
   int pending = g_orders.CountPendingOrders();
   bool barChanged = (m3Bar > 0 && m3Bar != g_lastGenerateSignalBar);
   bool poiChanged = (poiRev != g_lastPoiRevision);
   bool pendingDropped = (g_lastPendingCount >= 0 && pending < g_lastPendingCount);
   if(barChanged || poiChanged || pendingDropped)
      return true;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return false;
   return (TimeCurrent() - g_lastGenerateSignalTime >= 1);
  }

void MarkGenerateSignalRan()
  {
   g_lastGenerateSignalTime = TimeCurrent();
   datetime m3Bar = iTime(Symbol(), inp_ltf_period, 0);
   if(m3Bar > 0) g_lastGenerateSignalBar = m3Bar;
   g_lastPoiRevision = g_signal.GetPoiRevision();
   g_lastPendingCount = g_orders.CountPendingOrders();
  }

// H4 FIX: restart-recovery of open-position targets must branch explicitly on
// InpExitMode. STAGED and FIXED_RR positions carry no broker-side TP (their
// full/partial exits are driven purely by the locally tracked tp1Level/
// tp2Level), so if those fields come back from RegisterNewTrack()'s restart-
// reconstruction path as 0.0, the position is effectively unmanaged until it
// is closed by something else (trailing stop / manual). Each branch below
// only recomputes a target when the existing one is missing/invalid; it never
// overwrites a valid target already stored on the server or in the track.
void RecoverOpenPositionTargets()
  {
   if(InpExitMode == EXIT_STRUCTURAL_POI)
      RecoverStructuralTargets();
   else if(InpExitMode == EXIT_FIXED_RR)
      RecoverFixedRRTargets();
   else if(InpExitMode == EXIT_STAGED)
      RecoverStagedTargets();
  }

// STRUCTURAL: unchanged order â€” persisted TP, then opposing MSNR, then M15
// swing, then the emergency RR fallback.
void RecoverStructuralTargets()
  {
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double pip = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
   for(int i = 0; i < g_orders.TrackCount(); i++)
     {
      ulong ticket = 0;
      if(!g_orders.GetTrackTicket(i, ticket) || ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double persistedTP = PositionGetDouble(POSITION_TP);
      if(persistedTP <= 0.0)
         persistedTP = g_orders.GetTrackServerTP(ticket);
      int posType = (int)PositionGetInteger(POSITION_TYPE);
      bool isBuy = (posType == POSITION_TYPE_BUY);
      ENUM_ZONE_TYPE side = isBuy ? ZONE_DEMAND : ZONE_SUPPLY;
      ENUM_TARGET_SOURCE source = TARGET_NONE;
      double target = 0.0;
      // List order: persisted broker/track TP, then MSNR, then M15 swing, then 4R.
      if(TargetPriceValid(openPrice, isBuy, persistedTP))
        {
         target = persistedTP;
         source = TARGET_PERSISTED;
        }
      else
        {
         target = GetStructuralTarget(openPrice, side, source);
         if(!TargetPriceValid(openPrice, isBuy, target))
           {
            double risk = MathAbs(openPrice - sl);
            target = EmergencyStructuralTarget(openPrice, isBuy, risk);
            source = TARGET_EMERGENCY_RR;
           }
        }
      target = NormalizeDouble(target, digits);
      double serverTP = 0.0, tp1 = 0.0, tp2 = 0.0, tp1Pct = 0.0, tp2Pct = 0.0;
      if(source == TARGET_PERSISTED || source == TARGET_EMERGENCY_RR)
        {
         serverTP = target;
         double targetDistancePips = MathAbs(target - openPrice) / pip;
         if(InpUseTP1 && InpPoiPartialPips > 0.0 && targetDistancePips > InpPoiPartialPips)
           {
            tp1 = NormalizeDouble(isBuy ? (openPrice + InpPoiPartialPips * pip)
                                        : (openPrice - InpPoiPartialPips * pip), digits);
            tp1Pct = InpTP1ClosePct;
           }
         g_diagnostics.RecordTargetSource(source);
        }
      else
         PlanStructuralTP(openPrice, isBuy, side, pip, digits, serverTP, tp1, tp2, tp1Pct, tp2Pct,
                          MathAbs(openPrice - sl));
      g_lastPlanTargetSource = source;
      if(serverTP > 0.0 && MathAbs(serverTP - persistedTP) > pip * 0.1)
         g_orders.ApplyServerTP(ticket, serverTP);
      g_orders.UpdateTrackTarget(ticket, serverTP, tp1, source);
      Print("[YANSTD TARGET] Ticket=", ticket,
            " | TARGET_SOURCE=", TargetSourceLabel(source),
            " | TP=", DoubleToString(serverTP, digits));
     }
  }

// FIXED_RR: single full-position target. No broker TP is ever placed for this
// mode, so "server TP tidak tersedia" is checked against the locally tracked
// tp2Level (the field CPartialClose::IsTP2Hit() actually tests to close the
// whole position). Only recomputed when that level is missing/invalid.
void RecoverFixedRRTargets()
  {
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   for(int i = 0; i < g_orders.TrackCount(); i++)
     {
      ulong ticket = 0;
      if(!g_orders.GetTrackTicket(i, ticket) || ticket == 0) continue;
      SPositionInfo pos;
      if(!g_orders.GetPositionByTicket(ticket, pos)) continue;
      bool isBuy = (pos.posType == POSITION_TYPE_BUY);
      if(TargetPriceValid(pos.openPrice, isBuy, pos.tp2Level)) continue; // already valid â€” don't touch it
      double initialRisk = pos.initialRiskPrice;
      if(initialRisk <= 0.0)
         initialRisk = MathAbs(pos.openPrice - pos.sl);
      if(initialRisk <= 0.0 || InpFixedRR <= 0.0) continue;
      double target = isBuy ? (pos.openPrice + initialRisk * InpFixedRR)
                             : (pos.openPrice - initialRisk * InpFixedRR);
      target = NormalizeDouble(target, digits);
      pos.tp1Level = target; // FIXED_RR has no partials (g_tp1Enabled is false); keep both in sync.
      pos.tp2Level = target;
      g_orders.UpdateTrackState(pos);
      Print("[YANSTD TARGET] Ticket=", ticket,
            " | TARGET_SOURCE=RECOVERED_FIXED_RR | TP=", DoubleToString(target, digits));
     }
  }

// STAGED: TP1/TP2 recovered independently from the initial risk stored on the
// track (falling back to the current server SL distance), using the same
// InpTP1RR/InpTP2RR/pct configuration a fresh registration would use. Only
// the missing/invalid side is recomputed.
void RecoverStagedTargets()
  {
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   for(int i = 0; i < g_orders.TrackCount(); i++)
     {
      ulong ticket = 0;
      if(!g_orders.GetTrackTicket(i, ticket) || ticket == 0) continue;
      SPositionInfo pos;
      if(!g_orders.GetPositionByTicket(ticket, pos)) continue;
      bool isBuy = (pos.posType == POSITION_TYPE_BUY);
      double initialRisk = pos.initialRiskPrice;
      if(initialRisk <= 0.0)
         initialRisk = MathAbs(pos.openPrice - pos.sl);
      if(initialRisk <= 0.0) continue;
      bool changed = false;
      if(!TargetPriceValid(pos.openPrice, isBuy, pos.tp1Level) && InpTP1RR > 0.0)
        {
         pos.tp1Level = NormalizeDouble(isBuy ? (pos.openPrice + initialRisk * InpTP1RR)
                                              : (pos.openPrice - initialRisk * InpTP1RR), digits);
         changed = true;
        }
      if(!TargetPriceValid(pos.openPrice, isBuy, pos.tp2Level) && InpTP2RR > 0.0)
        {
         pos.tp2Level = NormalizeDouble(isBuy ? (pos.openPrice + initialRisk * InpTP2RR)
                                              : (pos.openPrice - initialRisk * InpTP2RR), digits);
         changed = true;
        }
      if(!changed) continue; // both levels already valid â€” do not overwrite
      g_orders.UpdateTrackState(pos);
      Print("[YANSTD TARGET] Ticket=", ticket,
            " | TARGET_SOURCE=RECOVERED_STAGED | TP1=", DoubleToString(pos.tp1Level, digits),
            " | TP2=", DoubleToString(pos.tp2Level, digits));
     }
  }

bool IsStructuralExitMode()
  {
   return (InpExitMode == EXIT_STRUCTURAL_POI);
  }

bool ApplyBoundSL(const double entryPrice, const bool isBuy, const double pip,
                  const int digits, double &sl, double &slP)
  {
   double minPips = 0.0, maxPips = 0.0;
   ComputeStopBoundPips(Symbol(), inp_htf_period, InpATRPeriod, pip,
                        InpMinSLPips, InpMaxSLPips,
                        InpUseATRStopBounds, InpSLMinATRMult, InpSLMaxATRMult,
                        minPips, maxPips);
   if(InpRejectOutOfBoundsSL)
      return StopWithinBounds(slP, minPips, maxPips);
   if(ClampStopToBounds(isBuy, entryPrice, pip, digits, minPips, maxPips, sl, slP))
      g_diagnostics.RecordClampedSL();
   return true;
  }

bool PlanStructuralTP(const double entryPrice, const bool isBuy, const ENUM_ZONE_TYPE side,
                      const double pip, const int digits,
                      double &serverTP, double &tp1, double &tp2,
                      double &tp1Pct, double &tp2Pct, const double slDistance)
  {
   serverTP = 0.0; tp1 = 0.0; tp2 = 0.0; tp1Pct = 0.0; tp2Pct = 0.0;
   if(pip <= 0.0) return false;
   ENUM_TARGET_SOURCE source = TARGET_NONE;
   double target = GetStructuralTarget(entryPrice, side, source);
   bool haveTarget = TargetPriceValid(entryPrice, isBuy, target);
   if(!haveTarget)
      source = TARGET_EMERGENCY_RR;
   if(haveTarget)
     {
      serverTP = NormalizeDouble(target, digits);
      double distPips = MathAbs(target - entryPrice) / pip;
      if(InpUseTP1 && InpPoiPartialPips > 0.0 && distPips > InpPoiPartialPips)
        {
         tp1 = NormalizeDouble(isBuy ? (entryPrice + InpPoiPartialPips * pip)
                                     : (entryPrice - InpPoiPartialPips * pip), digits);
         tp1Pct = InpTP1ClosePct;
        }
     }
   else
     {
      g_diagnostics.RecordStructuralTargetOpen();
      double slHint = slDistance;
      if(slHint <= 0.0)
         slHint = InpMinSLPips * pip;
      serverTP = NormalizeDouble(EmergencyStructuralTarget(entryPrice, isBuy, slHint), digits);
      source = TARGET_EMERGENCY_RR;
      if(InpUseTP1 && InpPoiPartialPips > 0.0)
        {
         tp1 = NormalizeDouble(isBuy ? (entryPrice + InpPoiPartialPips * pip)
                                     : (entryPrice - InpPoiPartialPips * pip), digits);
         tp1Pct = InpTP1ClosePct;
        }
     }
   if(haveTarget && source != TARGET_NONE)
      g_diagnostics.RecordStructuralRR(MathAbs(target - entryPrice) /
                                       MathMax(slDistance, pip));
   g_lastPlanTargetSource = source;
   g_diagnostics.RecordTargetSource(source);
   return true;
  }

string FormatEntryComment(const int bucket, const int variant, const int grade,
                          const ulong eventId, const bool isMatrix = false)
  {
   string c = StringFormat("SMC_T%dG%d_B%s_E%s",
                           variant, grade,
                           EncodeBase36Signed(bucket),
                           EncodeBase36(eventId));
   if(isMatrix) c += "_M";
   return c;
  }

// Single source of truth for reading back what FormatEntryComment() wrote:
// "SMC_T<variant>G<grade>_B<bucket36>_E<event36>[_M]". Every caller that needs
// variant/grade/bucket/event out of an order or deal comment must go through
// this function â€” do not keep a second, partial ad-hoc parser (e.g. a bare
// "_T" scan) alongside it, or the two can silently disagree on format changes.
// If the comment does not match the current format at all (legacy comment,
// manual order, corrupted string), every out param is left at its "unknown"
// sentinel and callers fall back to their explicit price-only matching path.
void ParseEntryComment(const string comm, int &bucket, int &variant, int &grade, ulong &eventId)
  {
   bucket = -1; variant = -1; grade = -1; eventId = 0;
   int tPos = StringFind(comm, "SMC_T");
   if(tPos < 0)
     {
      LogThrottled("PARSE_ENTRY_COMMENT", 60,
                   StringFormat("Komentar order '%s' tidak berformat SMC_T... â€” variant/grade/bucket/event diabaikan, fallback price-only", comm));
      return;
     }
   int cursor = tPos + 5;
   variant = (int)StringToInteger(StringSubstr(comm, cursor));
   int gPos = StringFind(comm, "G", cursor);
   if(gPos >= 0)
     {
      grade = (int)StringToInteger(StringSubstr(comm, gPos + 1));
      cursor = gPos + 1;
     }
   int bPos = StringFind(comm, "_B", cursor);
   if(bPos >= 0)
      bucket = DecodeBase36Signed(comm, bPos + 2);
   int ePos = StringFind(comm, "_E", cursor);
   if(ePos >= 0)
      eventId = DecodeBase36(comm, ePos + 2);
  }

bool TimeFilterAllowsEntry()
  {
   if(!InpUseTimeFilter) return true;
   if(InpBlockOverlapSession && g_session.GetCurrentSession() == SESSION_OVERLAP) return false;
   return g_session.IsTradeTimeAllowed(InpStartHourUTC, InpEndHourUTC, InpFridayCutoffHour,
                                       InpTimeFilterMode, InpRolloverBlockStartUTC, InpRolloverBlockEndUTC);
  }

bool GapPauseBlocksEntry()
  {
   return (InpPauseBarsAfterUnexpectedGap > 0 && g_gapPauseBarsLeft > 0);
  }

bool PassEntryMarketQuality(long diagKey)
  {
   // Both indicators use closed candles. Their values cannot change between
   // bars, so CopyBuffer on every market tick is pure duplicate work.
   static datetime cachedADXBar = 0, cachedATRBar = 0;
   static double cachedADX = 0.0, cachedPlusDI = 0.0, cachedMinusDI = 0.0, cachedATR = 0.0;
   if(InpUseADXGuard)
     {
      datetime adxBar = iTime(Symbol(), PERIOD_M15, 0);
      if(adxBar != cachedADXBar)
        {
         bool adxOk = false, plusOk = false, minusOk = false;
         double adxVal = ReadIndicatorValueSafe(g_adxM15Handle, 0, 1, adxOk);
         double plusVal = ReadIndicatorValueSafe(g_adxM15Handle, 1, 1, plusOk);
         double minusVal = ReadIndicatorValueSafe(g_adxM15Handle, 2, 1, minusOk);
         if(!adxOk)
           {
            // Do not advance cachedADXBar so the next tick retries CopyBuffer.
            WarnIndicatorReadFailed(Symbol(), PERIOD_M15, InpADXPeriod,
                                    "CopyBuffer ADX gagal â€” guard diperlakukan fail-closed");

           }
         else
           {
            cachedADX = adxVal;
            if(plusOk) cachedPlusDI = plusVal;
            if(minusOk) cachedMinusDI = minusVal;
            cachedADXBar = adxBar;
           }
        }
      double adx = cachedADX;
      if(adx < InpMinADX)
        {
         g_diagnostics.Record(REJECT_ADX_SOFT_PENALTY, diagKey);
        }
      g_signal.SetMarketADX(adx, InpMinADX, InpADXSoftPenalty, true, cachedPlusDI, cachedMinusDI);
     }
   else g_signal.SetMarketADX(0.0, InpMinADX, InpADXSoftPenalty, false);
   if(InpUseATRSpreadGate)
     {
      double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
      double spreadPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
      if(point > 0.0 && g_effectiveMaxSpreadPts > 0 && spreadPrice > g_effectiveMaxSpreadPts * point)
        {
         g_diagnostics.Record(REJECT_SPREAD_ATR, diagKey);
         return false;
        }
     }
   if(InpRequireKillzone && !g_session.IsKillzoneNow())
     {
      g_diagnostics.Record(REJECT_NOT_IN_KILLZONE, diagKey);
      return false;
     }
   return true;
  }

bool ApplyTimeInvalidation(SPositionInfo &pos)
  {
   if(!InpUseTimeInvalidation || pos.initialRiskPrice <= 0.0 || pos.openTime <= 0) return false;
   int barsPassed = iBarShift(pos.symbol, PERIOD_M5, pos.openTime, false);
   if(barsPassed < InpTimeInvalidationBarsM5) return false;
   static datetime cachedATRBar = 0;
   static double cachedATR = 0.0;
   datetime atrBar = iTime(pos.symbol, PERIOD_M5, 0);
   if(atrBar != cachedATRBar)
     {
      cachedATR = ReadIndicatorValue(g_atrM5Handle, 0, 1);
      cachedATRBar = atrBar;
     }
   double atr = cachedATR;
   if(atr <= 0.0) return false;
   bool reachedRequiredR = (pos.maxFavorableR >= InpTimeInvalidationMinRR);
   bool hasDisplacement = (pos.maxFavorableR * pos.initialRiskPrice >= InpDisplacementATRFrac * atr);
   if(reachedRequiredR || hasDisplacement) return false;
   bool requested = g_orders.RequestManagedClose(pos.ticket, "TIME_INVALIDATION");
   static ulong s_lastInvTicket = 0;
   static datetime s_lastInvLog = 0;
   if(pos.ticket != s_lastInvTicket || TimeCurrent() - s_lastInvLog >= 60)
     {
      Print("[YANSTD TIME_INV] ticket=", pos.ticket,
            " | bars=", barsPassed,
            " | maxR=", DoubleToString(pos.maxFavorableR, 2),
            " | atr=", DoubleToString(atr, 5),
            " | requested=", (requested ? "yes" : "pending"));
      s_lastInvTicket = pos.ticket;
      s_lastInvLog = TimeCurrent();
     }
   return true;
  }

void ApplyM3StructureProtection(SPositionInfo &pos)
  {
   if(!InpUseM3StructureTrailAt1R || pos.initialRiskPrice <= 0.0) return;
   double bid = SymbolInfoDouble(pos.symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(pos.symbol, SYMBOL_ASK);
   double currentR = (pos.posType == POSITION_TYPE_BUY)
                     ? (bid - pos.openPrice) / pos.initialRiskPrice
                     : (pos.openPrice - ask) / pos.initialRiskPrice;
   double atrBE      = GetCachedATR(pos.symbol, InpTrailSwingTF, InpATRPeriod);
   double profitDist = (pos.posType == POSITION_TYPE_BUY) ? (bid - pos.openPrice)
                                                          : (pos.openPrice - ask);
   double beTrigger  = (atrBE > 0.0) ? MathMax(InpTrailBEATRMult * atrBE, pos.initialRiskPrice)
                                     : pos.initialRiskPrice;
   if(profitDist < beTrigger) return;

   double spread = MathMax(0.0, ask - bid);
   double candidate = (pos.posType == POSITION_TYPE_BUY)
                      ? pos.openPrice + spread : pos.openPrice - spread;

   // Confirmed M3 pivots cannot change inside the current M3 candle. Cache
   // both sides once per bar instead of copying/scanning 80 candles for every
   // open position on every market tick (up to six times in matrix tests).
   static datetime cachedPivotBar = 0;
   static bool cachedBullStructure = false, cachedBearStructure = false;
   static double cachedBullPivot = 0.0, cachedBearPivot = 0.0;
   bool allowStructureTrail = (pos.tp1Done && currentR >= InpStructureTrailStartRR);
   datetime pivotBar = iTime(pos.symbol, PERIOD_M3, 0);
   if(allowStructureTrail && pivotBar != cachedPivotBar)
     {
      cachedBullStructure = false; cachedBearStructure = false;
      cachedBullPivot = 0.0; cachedBearPivot = 0.0;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(pos.symbol, PERIOD_M3, 0, 80, rates);
      if(copied >= 12)
        {
         double newestLow = 0.0, olderLow = 0.0;
         double newestHigh = 0.0, olderHigh = 0.0;
         int lowsFound = 0, highsFound = 0;
         for(int i = 3; i < copied - 2 && (lowsFound < 2 || highsFound < 2); i++)
           {
            bool pivotLow = true, pivotHigh = true;
            for(int j = 1; j <= 2; j++)
              {
               // AUDIT FIX: allow exact equal lows/highs (double bottoms/tops) as valid pivots
               if(rates[i].low > rates[i-j].low || rates[i].low > rates[i+j].low) pivotLow = false;
               if(rates[i].high < rates[i-j].high || rates[i].high < rates[i+j].high) pivotHigh = false;
              }
            if(pivotLow && lowsFound < 2)
              {
               if(lowsFound == 0) newestLow = rates[i].low; else olderLow = rates[i].low;
               lowsFound++;
              }
            if(pivotHigh && highsFound < 2)
              {
               if(highsFound == 0) newestHigh = rates[i].high; else olderHigh = rates[i].high;
               highsFound++;
              }
           }
         cachedBullStructure = (lowsFound == 2 && newestLow > olderLow);
         cachedBearStructure = (highsFound == 2 && newestHigh < olderHigh);
         if(cachedBullStructure) cachedBullPivot = newestLow;
         if(cachedBearStructure) cachedBearPivot = newestHigh;
        }
      cachedPivotBar = pivotBar;
     }
   // R3a: give the runner room. The M3 pivot trail used to glue SL to
   // (pivot -/+ spread), so ordinary M3 pullbacks stopped the runner out well
   // before it reached its ~1.69R average MFE (255/407 wins died in 1.0-1.5R).
   // Trail a volatility-relative buffer BELOW/ABOVE the confirmed pivot so only
   // a real structure break â€” not noise â€” ends the runner. atrBE==0 (ATR
   // unavailable) -> buffer 0 -> exact legacy behavior (Req robustness).
   double structRoom = (atrBE > 0.0) ? MathMax(0.0, InpStructureTrailBufferATR) * atrBE : 0.0;
   if(allowStructureTrail && pos.posType == POSITION_TYPE_BUY && cachedBullStructure)
      candidate = MathMax(candidate, cachedBullPivot - spread - structRoom);
   else if(allowStructureTrail && pos.posType == POSITION_TYPE_SELL && cachedBearStructure)
      candidate = MathMin(candidate, cachedBearPivot + spread + structRoom);

   // Respect both broker stop and freeze zones.  Add spread plus two ticks as
   // execution margin so a fast tick between validation and OrderSend cannot
   // turn a valid candidate into TRADE_RETCODE_INVALID_STOPS.
   double point = SymbolInfoDouble(pos.symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(pos.symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0) tickSize = point;
   long stopsLevel = SymbolInfoInteger(pos.symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(pos.symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double brokerDistance = (double)MathMax(stopsLevel, freezeLevel) * point + spread + 2.0 * tickSize;
   if(pos.posType == POSITION_TYPE_BUY)
      candidate = MathMin(candidate, bid - brokerDistance);
   else
      candidate = MathMax(candidate, ask + brokerDistance);
   candidate = NormalizeDouble(MathRound(candidate / tickSize) * tickSize,
                               (int)SymbolInfoInteger(pos.symbol, SYMBOL_DIGITS));

   if(!pos.bepDone)
     {
      bool protectsEntry = (pos.posType == POSITION_TYPE_BUY)
                           ? (candidate >= pos.openPrice)
                           : (candidate <= pos.openPrice);
      if(!protectsEntry)
        {
         static datetime lastIllegalBELog = 0;
         if(TimeCurrent() - lastIllegalBELog >= 60)
           {
            Print("[YANSTD BE PROTECTION] Deferred: broker stop/freeze distance keeps SL behind entry | Ticket=",
                  pos.ticket, " | Candidate=", candidate, " | Entry=", pos.openPrice);
            lastIllegalBELog = TimeCurrent();
           }
         return;
        }
     }

   double pipStep = point * GetPipFactor(pos.symbol);
   bool stillUnprotected = (pos.posType == POSITION_TYPE_BUY) ? (pos.sl <= 0.0 || pos.sl < pos.openPrice)
                                                              : (pos.sl <= 0.0 || pos.sl > pos.openPrice);
   double minDelta = stillUnprotected ? 0.0 : pipStep;
   bool improves = (pos.posType == POSITION_TYPE_BUY)
                   ? (candidate < bid && (pos.sl <= 0.0 || candidate > pos.sl + minDelta))
                   : (candidate > ask && (pos.sl <= 0.0 || candidate < pos.sl - minDelta));
   if(!improves) return;
   if(g_orders.ModifySL(pos.ticket, candidate))
     {
      pos.sl = candidate;
      pos.bepDone = true;
      g_orders.UpdateTrackState(pos);
      Print(allowStructureTrail ? "[YANSTD M3 STRUCTURE TRAIL] Ticket="
                                : "[YANSTD BE PROTECTION (max(ATR,1R))] Ticket=", pos.ticket,
            " | CurrentR=", DoubleToString(currentR, 2),
            " | NewSL=", DoubleToString(candidate, (int)SymbolInfoInteger(pos.symbol, SYMBOL_DIGITS)));
     }
  }

bool CanSecondaryScaleIn(ENUM_ZONE_TYPE side, datetime &bosTime)
  {
   bosTime = 0;
   int count = g_orders.CountOpenPositions();
   if(count <= 0 || !InpUseSecondaryBOSScaleIn) return true;
   int requiredType = (side == ZONE_DEMAND) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   bool protectedPrimary = false;
   for(int i = 0; i < count; i++)
     {
      SPositionInfo p;
      if(!g_orders.GetPosition(i, p) || p.posType != requiredType || p.initialRiskPrice <= 0.0) continue;
      double px = (requiredType == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID)
                                                      : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      double rr = (requiredType == POSITION_TYPE_BUY) ? (px - p.openPrice) / p.initialRiskPrice
                                                      : (p.openPrice - px) / p.initialRiskPrice;
      bool atBE = (requiredType == POSITION_TYPE_BUY) ? (p.sl >= p.openPrice && p.sl > 0.0)
                                                      : (p.sl <= p.openPrice && p.sl > 0.0);
      if(rr > 1.0 && atBE) { protectedPrimary = true; break; }
     }
   if(!protectedPrimary) return false;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(Symbol(), PERIOD_M3, 0, 12, r) < 10) return false;
   double breakLevel = (requiredType == POSITION_TYPE_BUY) ? -DBL_MAX : DBL_MAX;
   for(int i = 3; i <= 9; i++)
      if(requiredType == POSITION_TYPE_BUY) breakLevel = MathMax(breakLevel, r[i].high);
      else                                  breakLevel = MathMin(breakLevel, r[i].low);
   bool bos = (requiredType == POSITION_TYPE_BUY) ? (r[1].close > breakLevel)
                                                  : (r[1].close < breakLevel);
   if(!bos || r[1].time == g_lastConsumedScaleBOS) return false;
   bosTime = r[1].time;
   return true;
  }

bool ValidateInputs()
  {
   string reason = "";
   if((int)InpSetupMode != (int)SETUP_SMC_PRIMARY && (int)InpSetupMode != (int)SETUP_PURE_SMC)
      reason = "InpSetupMode must be 2 (SMC_PRIMARY) or 3 (PURE_SMC) -- modes 0/1 were removed";
   else if(InpMagicNumber == 0) reason = "Magic Number must be greater than zero";
   else if(InpSlippage < 0) reason = "Slippage cannot be negative";
   else if(InpTradeRetryAttempts < 0 || InpTradeRetryAttempts > 10)
      reason = "Trade Retry Attempts must be between 0 and 10";
   else if(InpTradeRetryDelayMs < 0 || InpTradeRetryDelayMs > 5000)
      reason = "Trade Retry Delay must be between 0 and 5000 ms";
   else if(InpMSNRScanBars < 50 || InpMSNRScanBars > 5000 ||
           InpMSNROTEFibMin < 0.50 || InpMSNROTEFibMax > 0.95 ||
           InpMSNROTEFibMin >= InpMSNROTEFibMax)
      reason = "MSNR scan/OTE inputs are invalid";
   else if(InpKingSNR_PrimaryTF == InpKingSNR_SecondaryTF ||
           InpKingSNR_LookbackBars < 20 || InpKingSNR_LookbackBars > 2000)
      reason = "King SNR primary/secondary TF must differ, with a 20-2000 bar lookback";
   else if(inp_htf_period != PERIOD_M15 || inp_ltf_period != PERIOD_M3 ||
           (InpUseM5Refinement && inp_mtf_period != PERIOD_M5))
      reason = "SMC architecture requires M15 primary, optional M5 refinement, and M3 execution";
   else if((InpUseM5Refinement &&
            (PeriodSeconds(inp_htf_period) <= PeriodSeconds(inp_mtf_period) ||
             PeriodSeconds(inp_mtf_period) <= PeriodSeconds(inp_ltf_period))) ||
           (!InpUseM5Refinement && PeriodSeconds(inp_htf_period) <= PeriodSeconds(inp_ltf_period)))
       reason = "Timeframes must satisfy M15 > optional M5 > M3 hierarchy";
   else if(inp_m15_depth < 2 || inp_m5_depth < 2 || inp_m3_depth < 2 ||
           inp_m15_depth > 500 || inp_m5_depth > 500 || inp_m3_depth > 500 ||
           inp_m15_dev < 0 || inp_m5_dev < 0 || inp_m3_dev < 0 ||
           inp_m15_back < 1 || inp_m5_back < 1 || inp_m3_back < 1 ||
           inp_m15_back >= inp_m15_depth || inp_m5_back >= inp_m5_depth || inp_m3_back >= inp_m3_depth ||
           InpCHoCHTransitionMaxBars < 1 || InpCHoCHTransitionMaxBars > 96)
      reason = "ZigZag depth/backstep parameters are invalid";
   else if(inp_fvg_min_multiplier <= 0.0 || InpFibMatchTolerance <= 0.0 || InpFibMatchTolerance > 0.10 ||
           inp_zone_max_bars < 0 || InpPOIScanBars < 100 || InpPOIScanBars > 20000 ||
           inp_sl_buffer_pips < 0.0 || inp_max_spread < 1 || InpMaxEntryDistanceATR < 0.0)
      reason = "SMC precision parameters are invalid";
   else if(InpPOIInvalidationCloses < 1 || InpPOIInvalidationCloses > 5 ||
           InpPOIInvalidationBufferPips < 0.0)
      reason = "POI invalidation inputs are invalid";
   else if(InpDynamicSpreadSamples < 20 || InpDynamicSpreadSamples > 5000 ||
           InpDynamicSpreadStdDevMult < 0.0 ||
           InpDynamicSpreadFloor < 1 || InpDynamicSpreadFloor > inp_max_spread)
      reason = "Dynamic Spread Auto-Detection inputs are invalid (floor must be <= manual hard-cap)";
   else if(InpMinSLPips < 0.0 || InpMaxSLPips < 0.0 ||
           (InpMaxSLPips > 0.0 && InpMinSLPips > 0.0 && InpMaxSLPips <= InpMinSLPips) ||
           (InpUseATRStopBounds && (InpSLMinATRMult <= 0.0 || InpSLMaxATRMult <= InpSLMinATRMult)) ||
           InpVariantClusterMinATR < 0.0)
      reason = "SL bounds or cluster ATR are invalid";
   else if(InpFixedRR <= 0.0)
      reason = "Fixed exit RR must be greater than zero";
   else if(InpExitMode == EXIT_STAGED && (InpEmergencyServerTPRR < 0.0 ||
           (InpEmergencyServerTPRR > 0.0 && InpEmergencyServerTPRR <= InpTP2RR)))
      reason = "Emergency server TP must be disabled (0) or greater than TP2 RR";
   else if(InpPoiPartialPips < 0.0)
      reason = "POI partial distance cannot be negative";
   else if(InpFixedLot < 0.0 || InpRiskPercent <= 0.0)
      reason = "Risk and lot parameters must be positive";
   else if(InpMaxLot < 0.0)
      reason = "InpMaxLot must be 0 (disabled) or a positive lot ceiling";
   else if(InpMaxAggregateRiskPct < 0.0 || InpMaxAggregateRiskPct > 10.0 ||
           InpMaxEquityDDPct < 0.0 || InpMaxEquityDDPct > 100.0)
      reason = "Maximum aggregate risk must be 0-10% and maximum equity drawdown must be 0-100%";
   else if(InpMaxActivePositions < 1 || InpMaxActivePositions > 8)
      reason = "Max active positions must be between 1 and 8";
   else if(InpCollectionMaxPositions < 1 || InpCollectionMaxPositions > MAX_POSITIONS ||
           InpCollectionMaxPending < 1 || InpCollectionMaxPending > MAX_POSITIONS ||
           InpCollectionRiskPct <= 0.0 || InpCollectionRiskPct > 1.0)
      reason = "Data Collection limits are invalid (positions/pending 1-10, risk 0-1%)";
   else if((int)InpLogLevel < (int)LOG_LEVEL_ERROR || (int)InpLogLevel > (int)LOG_LEVEL_DEBUG)
      reason = "Log level is invalid";
   else if(InpMinAIConfidence < 0.0 || InpMinAIConfidence > 100.0)
      reason = "AI confidence inputs must be between 0 and 100";
   else if(InpBrainDecayHalfLifeDays < 0.0)
      reason = "Brain decay input is invalid";
   else if(InpQAlpha <= 0.0 || InpQAlpha > 1.0 || InpQGamma < 0.0 || InpQGamma > 1.0 ||
           InpQMinUpdates < 1 || InpQRewardClip <= 0.0 ||
            InpBrainMinRewardRisk < 0.0 || InpBrainMinRewardRisk > 10.0)
       reason = "Tabular Q-learning inputs are invalid";
   else if(InpBrainLiveWeight < 0.0 || InpBrainRealTickWeight < 0.0 || InpBrainOHLCWeight < 0.0 ||
           (InpBrainLiveWeight + InpBrainRealTickWeight + InpBrainOHLCWeight) <= 0.0)
      reason = "Brain fusion weights must be non-negative and not all zero";
   else if(InpBrainJournalSegmentMB < 1 || InpBrainJournalSegmentMB > 2048 ||
           InpDiagnosticIntervalMinutes < 0 || InpDiagnosticIntervalMinutes > 1440)
      reason = "Brain journal must be 1-2048 MB and diagnostic interval 0-1440 minutes";
   else if(InpADXPeriod < 2 || InpMinADX < 0.0 || InpADXSoftPenalty < 0.0 ||
           InpADXSoftPenalty > 100.0 || InpATRSpreadPeriod < 2 ||
           InpMinimumStructuralRRR <= 0.0 || InpTimeInvalidationBarsM5 < 1 ||
           InpTimeInvalidationMinRR <= 0.0 || InpDisplacementATRFrac <= 0.0 ||
           InpStructureTrailStartRR <= 0.0)
      reason = "Loss-reduction/market-quality inputs are invalid";
   else if(InpStartHourUTC < 0 || InpStartHourUTC > 23 || InpEndHourUTC < 0 || InpEndHourUTC > 24 ||
           InpRolloverBlockStartUTC < 0 || InpRolloverBlockStartUTC > 23 ||
           InpRolloverBlockEndUTC < 0 || InpRolloverBlockEndUTC > 24 ||
           InpFridayCutoffHour < 0 || InpFridayCutoffHour > 23 ||
           InpFridayCloseHour < 0 || InpFridayCloseHour > 23 ||
           InpSundayOpenBlockHours < 0 || InpSundayOpenBlockHours > 12 ||
           InpPauseBarsAfterUnexpectedGap < 0 || InpPauseBarsAfterUnexpectedGap > 48 ||
           (InpTimeFilterMode == TIME_FILTER_WINDOW && InpStartHourUTC == InpEndHourUTC))
      reason = "UTC session/weekend hours are invalid";
   else if(InpNewsPreMinutes < 0 || InpNewsPostMinutes < 0)
      reason = "News filter minutes cannot be negative";
   else if(InpNewsLivePartialPct <= 0.0 || InpNewsLivePartialPct >= 100.0)
      reason = "NEWS_LIVE partial-close percentage must be between 0 and 100";
   else if(InpExitMode == EXIT_STAGED && !InpUseEarlyBEP && !InpUseTP1)
      reason = "Unsafe exit configuration: Early BEP and TP1 cannot both be disabled";
   else if(InpExitMode == EXIT_STAGED && (InpTP1RR <= 0.0 || InpTP2RR <= InpTP1RR || InpTP1ClosePct <= 0.0 || InpTP2ClosePct <= 0.0 ||
           InpTP1ClosePct + InpTP2ClosePct >= 100.0))
      reason = "TP values are invalid; TP2 RR must exceed TP1 RR and close percentages must leave a runner";
   else if(InpExitMode == EXIT_STRUCTURAL_POI && InpTP1ClosePct <= 0.0)
      reason = "Structural POI partial percent must be greater than zero";
   else if(InpMinRunnerInitialLot <= 0.0)
      reason = "Minimum initial lot for runner must be greater than zero";
   else if(InpMarginSafetyBufferPct < 0.0 || InpMarginSafetyBufferPct > 500.0)
      reason = "Margin safety buffer must be between 0% and 500%";
   else if(InpMinMarginLevelPct < 0.0)
      reason = "Minimum margin level circuit-breaker cannot be negative (0 = disabled)";
   else if(PeriodSeconds(InpTrailSwingTF) <= 0 || InpTrailSwingLeftBars < 1 ||
           InpTrailSwingRightBars < 1 || InpTrailSwingBufferPips <= 0.0)
      reason = "Confirmed-swing trailing parameters are invalid";
   else if(InpSLATRMult <= 0.0)
      reason = "Institutional optimization parameters are invalid (SL ATR multiplier must be > 0)";
   else if(InpATRPeriod < 2 || InpATRPeriod > 200 ||
            InpMinFVG_ATR_Mult <= 0.0 || InpProximityATRMult <= 0.0 ||
           InpTrailBEATRMult <= 0.0 || InpTrailDistATRMult <= 0.0 ||
           InpMaxSpreadATRMult < 0.0 || InpSpreadCapFloorPips < 0.0 ||
           InpMaxFVGBarAge < 1 || InpMaxFVGBarAge > 500 ||
           InpMaxOBBarAge < 0 || InpMaxOBBarAge > 500 ||
           InpFVGImpulseBodyRatio < 0.50 || InpFVGImpulseBodyRatio > 0.95 ||
           InpStructureSwingWing < 2 || InpStructureSwingWing > 8 ||
           InpFVGSwingWingLTF < 2 || InpFVGSwingWingLTF > 8 ||
           InpFVGSwingWingHTF < 2 || InpFVGSwingWingHTF > 8)
      reason = "ATR/FVG engine inputs are invalid (period 2-200; FVG ATR mult > 0; impulse body 0.50-0.95; FVG age 1-500; OB age 0-500; swing wings 2-8)";
   
   else if(InpMilestoneTriggerR < 0.0 || InpMilestoneLockR < 0.0 ||
           InpMinimumSoftScore < 0.0 ||
           InpMinimumSoftScore > 100.0 || InpCounterBiasStagnationBars < 1 ||
           InpCounterBiasMinScore < InpMinimumSoftScore || InpCounterBiasMinScore > 100.0)
      reason = "Institutional soft-score inputs are invalid";
   else if(InpLimitExpirationBars < 0)
      reason = "Limit expiration cannot be negative";
   else if(InpTesterUTCOffsetWinter < -12 || InpTesterUTCOffsetWinter > 14)
      reason = "Tester UTC offset must be between -12 and +14";

   if(reason != "")
     {
      LogSystemError("YANSTD", "ValidateInputs", 0, reason);
      return false;
     }
   return true;
  }

bool CheckAndPreloadHistoricalData(string sym)
  {
   ENUM_TIMEFRAMES requiredTFs[3] = {inp_htf_period, g_effectiveRefinementTF, inp_ltf_period};
   int minRequiredBars[3]         = {300, MathMax(300, InpPOIScanBars), 300};
   bool allDataComplete           = true;

   for(int i = 0; i < 3; i++)
     {
      bool alreadyChecked = false;
      for(int prev = 0; prev < i; prev++)
         if(requiredTFs[prev] == requiredTFs[i]) { alreadyChecked = true; break; }
      if(alreadyChecked) continue;

      int required = minRequiredBars[i];
       for(int j = i + 1; j < 3; j++)
         if(requiredTFs[j] == requiredTFs[i]) required = MathMax(required, minRequiredBars[j]);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(sym, requiredTFs[i], 0, required, rates);
      if(copied < required)
        {
         Print("[YANSTD DATA] Incomplete history for ", sym, " ", EnumToString(requiredTFs[i]),
               " | available=", copied, " required>=", required);
         allDataComplete = false;
        }
     }

   if(!allDataComplete)
     {
      Print("================================================================");
      Print("[YANSTD DATA] Historical candles for this test window are incomplete.");
      Print("Fix: open ", sym, " on M15 / optional M5 / M3 and press Home to back-fill,");
      Print("or use View -> Symbols -> Bars -> Request.");
      Print("================================================================");
     }
   else
     {
      Print("[YANSTD DATA] Required timeframe history verified.");
     }

   return allDataComplete;
  }

// AUDIT FIX (#4): single place that turns the session actually used for
// sizing/attribution (SessionManager::GetCurrentSession()) into the label
// shown on the dashboard's Signal Card, replacing the old raw-TimeGMT()
// re-derivation that lived inside CStatsDashboard::DrawSignalCard().
string SessionLabel(ENUM_SESSION_TYPE sess)
  {
   switch(sess)
     {
      case SESSION_ASIA:    return "ASIA";
      case SESSION_LONDON:  return "LDN";
      case SESSION_OVERLAP: return "LDN+NY";
      case SESSION_NEWYORK: return "NY";
      default:              return "â€”";
     }
  }

void LogUTCOffsetSelfCheck()
  {
   datetime serverNow = TimeTradeServer();
   if(serverNow <= 0) serverNow = TimeCurrent();

   if(MQLInfoInteger(MQL_TESTER))
     {
      int configuredOffset = g_session.GetConfiguredTesterOffsetHours(serverNow);
      datetime derivedUTC = g_session.ConvertServerToUTC(serverNow);
      long observedSeconds = (long)(serverNow - derivedUTC);
      Print("[YANSTD UTC SELF-CHECK] TESTER | Server=", TimeToString(serverNow, TIME_DATE|TIME_SECONDS),
            " | Derived UTC=", TimeToString(derivedUTC, TIME_DATE|TIME_SECONDS),
            " | Applied UTC offset=", (configuredOffset >= 0 ? "+" : ""), configuredOffset,
            " | European DST=", (InpTesterUseEuropeanDST ? "ON" : "OFF"));
      if(observedSeconds != (long)configuredOffset * 3600)
         Print("[YANSTD UTC WARNING] Internal tester UTC conversion mismatch detected.");
      Print("[YANSTD UTC NOTICE] Strategy Tester does not expose an authoritative historical broker-GMT offset; ",
            "the applied offset is the configured tester assumption and must match the tested broker dataset.");
      return;
     }

   datetime gmtNow = TimeGMT();
   if(serverNow <= 0 || gmtNow <= 0)
     {
      Print("[YANSTD UTC WARNING] Live broker/GMT clocks unavailable during OnInit; UTC check deferred to journal observation.");
      return;
     }
   double rawOffset = (double)(serverNow - gmtNow) / 3600.0;
   int actualOffset = (int)MathRound(rawOffset);
   double minuteError = MathAbs(rawOffset - actualOffset) * 60.0;
   Print("[YANSTD UTC SELF-CHECK] LIVE | Broker server=", TimeToString(serverNow, TIME_DATE|TIME_SECONDS),
         " | GMT=", TimeToString(gmtNow, TIME_DATE|TIME_SECONDS),
         " | Observed broker offset=UTC", (actualOffset >= 0 ? "+" : ""), actualOffset);
   if(actualOffset < -12 || actualOffset > 14 || minuteError > 2.0)
      Print("[YANSTD UTC WARNING] Broker clock offset is outside a normal whole-hour range; verify session/news timing.");
   if(actualOffset != InpTesterUTCOffsetWinter &&
      (!InpTesterUseEuropeanDST || actualOffset != InpTesterUTCOffsetWinter + 1))
      Print("[YANSTD UTC WARNING] Live broker offset differs from the tester winter/DST profile. ",
            "Update tester offset before comparing live and backtest session statistics.");
  }

//+------------------------------------------------------------------+
//|  OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;
   g_logLevel = (int)InpLogLevel;
   ConfigurePushAlerts(InpEnablePushAlerts);
   g_diagnostics.SetOOSStart(InpOOSStart);

   if(SymbolInfoDouble(Symbol(), SYMBOL_POINT) == 0)
     {
      Alert("YANSTD: Invalid symbol â€” cannot get point value!");
      return INIT_FAILED;
     }

   g_effectiveRefinementTF = InpUseM5Refinement ? inp_mtf_period : inp_htf_period;

   // Pre-validate historical candle data availability
   if(!CheckAndPreloadHistoricalData(Symbol()))
     {
      if(MQLInfoInteger(MQL_TESTER))
        {
         Alert("YANSTD: Required historical data is incomplete. Initialization stopped for safety.");
         return INIT_FAILED;
        }
      Print("âš ï¸ [YANSTD DATA] Historical data still incomplete on live terminal; continuing â€” scans will self-heal as history downloads.");
     }

   if(MQLInfoInteger(MQL_TESTER))
      g_autoMode = AUTO_ON;
   else
      g_autoMode = InpAutoTrading ? AUTO_ON : AUTO_OFF;

   long accountMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   bool isHedging = (accountMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   bool historicalMatrixTest = IsHistoricalMatrixTest();
   bool historicalTester = (bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_FORWARD);
   if(historicalMatrixTest)
      Print("[YANSTD TEST MODE] MATRIX COLLECTION is active: up to six correlated POI candidates are sampled. Tester PF/DD are exploration statistics, not live-strategy performance.");
   else if(MQLInfoInteger(MQL_TESTER))
      Print("[YANSTD TEST MODE] LIVE SINGLE VALIDATION is active: one best candidate is taken; Brain overlay may reduce lot, never block entry.");
   g_effectiveCollectionMode = InpDataCollectionMode && historicalTester;
   g_allowSingleExitBelowRunnerMin = InpAllowSingleExitFallback;
   if(InpDataCollectionMode && !historicalTester)
      Print("[YANSTD SAFETY] DataCollectionMode ignored for real/forward execution.");
   // Parse the active set before deriving matrix capacity. Seven active IDs
   // are used; the current strategy can generate at most six pending candidates.
   g_entryVariants.Parse(InpEntryVariants);
   Print("[YANSTD H2] Allowed entry variants: ", g_entryVariants.ToString(),
         " (", g_entryVariants.AllowedCount(), " IDs; max ", MATRIX_MAX_CANDIDATE_COUNT,
         " pending candidates per matrix setup)");
   if(g_entryVariants.AllowedCount() <= 0)
     {
      Print("[YANSTD H2] ERROR: no entry variants allowed after parsing; initialization stopped.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_multiLayerAllowed = (InpMultiLayerEntry || g_effectiveCollectionMode || historicalMatrixTest) && isHedging;
   int requestedMaxPositions = historicalMatrixTest
                              ? MathMin(MATRIX_MAX_CANDIDATE_COUNT, g_entryVariants.AllowedCount())
                              : (g_effectiveCollectionMode ? InpCollectionMaxPositions : InpMaxActivePositions);
   g_effectiveMaxPositions = isHedging ? MathMax(1, MathMin(MAX_POSITIONS, requestedMaxPositions)) : 1;
   if((InpMultiLayerEntry || g_effectiveCollectionMode) && !isHedging)
      Print("âš ï¸ [YANSTD SAFETY] Netting account detected: multi-layer disabled and max position forced to 1.");

   // Initialize all core subsystems

   g_session.Init(InpTesterUTCOffsetWinter, InpTesterUseEuropeanDST);
   LogUTCOffsetSelfCheck();
   g_news.Init(InpNewsHighOnly, InpNewsPreMinutes, InpNewsPostMinutes,
                InpNewsTesterSimulate, InpTesterUTCOffsetWinter, InpTesterUseEuropeanDST,
                InpFomcDatesOverride);
   g_news.SetSessionManager(&g_session);
   if(InpUseNewsFilter)
      g_news.RefreshEvents();
   if(MQLInfoInteger(MQL_TESTER) && InpUseNewsFilter)
     {
      if(InpNewsTesterSimulate)
         Print("[YANSTD TESTER] News filter ACTIVE with synthetic NFP/CPI/FOMC calendar (M4). ",
               "Backtests now pause around high-impact releases like live does. ",
               "FOMC dates are rule-generated and approximate within a few days.");
      else
         Print("âš ï¸ [YANSTD TESTER] Synthetic news calendar DISABLED (InpNewsTesterSimulate=false); ",
               "the news filter is bypassed and results are NOT comparable to live.");
     }

   g_risk.Init(Symbol());
   g_risk.SetRejectBelowMinLot(InpRejectBelowMinLot);
   // Gen-7 fix: absolute lot policy ceiling, enforced inside
   // NormalizeLotToBrokerLimits() BEFORE the broker's SYMBOL_VOLUME_MAX so an
   // oversized risk request is capped by policy AND counted, instead of being
   // silently absorbed by the broker limit (0 = disabled).
   g_maxLotCap = (InpMaxLot > 0.0) ? InpMaxLot : 0.0;
   g_lotPolicyCapCount = 0;
   g_lotMaxClampCount  = 0;
   g_spreadMonitor.Init(InpDynamicSpreadSamples);
   g_adxM15Handle = iADX(Symbol(), PERIOD_M15, InpADXPeriod);
   g_atrM5Handle  = iATR(Symbol(), PERIOD_M5, InpATRSpreadPeriod);
   if((InpUseADXGuard && g_adxM15Handle == INVALID_HANDLE) ||
      ((InpUseATRSpreadGate || InpUseTimeInvalidation) && g_atrM5Handle == INVALID_HANDLE))
     {
      LogSystemError("YANSTD", "OnInit", GetLastError(), "Failed to create ADX/ATR market-quality handles");
      if(g_adxM15Handle != INVALID_HANDLE) { IndicatorRelease(g_adxM15Handle); g_adxM15Handle = INVALID_HANDLE; }
      if(g_atrM5Handle  != INVALID_HANDLE) { IndicatorRelease(g_atrM5Handle);  g_atrM5Handle  = INVALID_HANDLE; }
      return INIT_FAILED;
     }
   g_effectiveMaxSpreadPts = inp_max_spread;
   double effectiveTP1RR = (InpExitMode == EXIT_FIXED_RR) ? InpFixedRR : InpTP1RR;
   double effectiveTP2RR = (InpExitMode == EXIT_FIXED_RR) ? InpFixedRR : InpTP2RR;
   double effectiveTP1Pct = (InpExitMode == EXIT_FIXED_RR) ? 0.0 : InpTP1ClosePct;
   double effectiveTP2Pct = (InpExitMode == EXIT_FIXED_RR) ? 0.0 : InpTP2ClosePct;
   g_orders.Init(InpMagicNumber, InpSlippage, effectiveTP1RR, effectiveTP2RR,
                 effectiveTP1Pct, effectiveTP2Pct, InpAutoRoundLot,
                 InpMinRunnerInitialLot, InpMarginSafetyBufferPct,
                 InpTradeRetryAttempts, InpTradeRetryDelayMs);
   g_orders.SetDiagnostics(&g_diagnostics);
   g_partial.Init(&g_orders);
   g_partial.SetDiagnostics(&g_diagnostics);
   g_partial.SetStagedFallback(STAGED_FALLBACK_CLOSE_ALL);
   g_trail.Init(&g_orders);
   g_trail.SetParams(InpTrailSwingTF, InpTrailSwingLeftBars,
                     InpTrailSwingRightBars, InpTrailSwingBufferPips);
   g_trail.SetATRParams(InpATRPeriod, InpTrailDistATRMult); // ATR Engine wiring

   bool strictHistoricalValidation = (bool)MQLInfoInteger(MQL_TESTER) &&
                                     !(bool)MQLInfoInteger(MQL_FORWARD) &&
                                     InpTesterExecutionMode == TESTER_LIVE_STRICT;
   bool effectiveBrainLearning = InpAILearning &&
                                 (!strictHistoricalValidation || InpStrictValidationLearning);
   if(strictHistoricalValidation && InpAILearning && !InpStrictValidationLearning)
      Print("[YANSTD TEST SAFETY] SmartBrain learning is READ-ONLY during strict validation; loaded evidence is frozen.");
   g_brain.Init(Symbol(), InpMinAIConfidence, effectiveBrainLearning, InpTesterBrainSource,
                 InpBrainInstrumentKey, InpBrokerSpecificLiveBrain,
                 InpBrainDecayHalfLifeDays, InpQAlpha, InpQGamma, InpQMinUpdates,
                 InpQRewardClip,
                 InpBrainLiveWeight, InpBrainRealTickWeight, InpBrainOHLCWeight,
                  InpBrainEventJournal, InpBrainJournalSegmentMB, InpBrainEventJournalInTester);
   g_brain.SetMinRewardRisk(InpBrainMinRewardRisk);
   g_brain.SetZoneATRParams(inp_htf_period, InpATRPeriod); // OPT-A: zone-size buckets in ATR(M15) units

   if(InpUseSmartBrain)
     {
      double learnedEvidence = g_brain.TotalRealEvidence();
      if(strictHistoricalValidation && !effectiveBrainLearning && learnedEvidence <= 0.0)
        {
         Print("ðŸ›‘ [YANSTD TEST VALIDITY] STRICT run started on an EMPTY brain while learning is read-only.");
         Print("ðŸ›‘ [YANSTD TEST VALIDITY] Brain reward/penalty sizing is INERT for this run; MSNR+SMC entry logic remains fully active.");
         Print("ðŸ›‘ [YANSTD TEST VALIDITY] This validates SMC+MSNR only. Train Brain on 2010-2022 first, then run read-only validation/holdout on the saved evidence.");
        }
      g_brain.LogEvidenceDensity("INIT");
     }
   if(InpFixedLot > 0.0 && InpUseDynamicRisk)
      Print("[YANSTD CONFIG WARNING] InpFixedLot > 0 bypasses risk-percent sizing and the Brain 0.50x overlay.");

   // Initialize integrated MSNR-primary / SMC-confirmation engine.
   g_signal.SetATRPeriod(InpATRPeriod);
   g_signal.SetATRStopBounds(true, InpSLMinATRMult, InpSLMaxATRMult);
   // SetRejectOutOfBoundsSL tidak ada di engine; ApplyBoundSL() menanganinya di EA.
   const double fvgMinMult = InpMinFVG_ATR_Mult;
   SetFVGValidatorParams(Symbol(), fvgMinMult, InpMaxFVGBarAge,
                         InpFVGImpulseBodyRatio, InpRequireFVGStructureOverlap, InpATRPeriod,
                         InpFVGSwingWingLTF, InpFVGSwingWingHTF);
   g_signal.SetFVGATRMult(fvgMinMult); // M5 and Layer-2 M15 use the same ATR-normalized gap rule
   g_signal.Init(Symbol(), inp_htf_period, g_effectiveRefinementTF, inp_ltf_period,
                 inp_m15_depth, inp_m15_dev, inp_m15_back,
                 inp_m5_depth,  inp_m5_dev,  inp_m5_back,
                 inp_m3_depth,  inp_m3_dev,  inp_m3_back,
                  inp_fvg_min_multiplier, InpFibMatchTolerance,
                  inp_zone_max_bars, InpPOIScanBars,
                  inp_sl_buffer_pips, inp_max_spread,
                   InpTP1RR, InpTP2RR, InpUseDynamicRisk,
                  InpMinSLPips, InpMaxSLPips,
                  InpUseDynamicSLBuffer, InpSLATRMult,
                  InpUseLiquiditySweep, InpUseOTEFilter, 
                  InpMinimumSoftScore, InpAllowCounterBias,
                  InpCounterBiasStagnationBars, InpCounterBiasMinScore,
                  InpCHoCHTransitionMaxBars,
                  InpPOIInvalidationCloses, InpPOIInvalidationBufferPips);
   g_signal.SetRequireM3Sweep(InpRequireM3Sweep);
   g_signal.SetPoiPartialPips(InpPoiPartialPips);
   // Initialize MSNR Primary Engine (Layer 1: King SNR, Fresh SnD, QML)
   // composed with the Layer 2 (SMC OB/FVG M15) engine for the Overlap Logic gate.
   g_msnr.Init(Symbol(), inp_htf_period, InpMSNROTEFibMin, InpMSNROTEFibMax,
               InpPOIInvalidationCloses, InpPOIInvalidationBufferPips,
               InpKingSNR_PrimaryTF, InpKingSNR_SecondaryTF, InpKingSNR_LookbackBars,
               InpUseLayer2M15Gate, InpRequireZoneOTE,
               InpFVGImpulseBodyRatio, InpMaxOBBarAge);
   g_msnr.SetRequireM5Contained(InpRequireM5ContainedInM15);
   g_msnr.SetStructureSwingWing(InpStructureSwingWing);
   g_msnr.SetOBRequireOppositeColor(InpOBRequireOppositeColor);
   g_msnr.SetATRParams(InpATRPeriod, InpProximityATRMult, fvgMinMult); // ATR Engine wiring (also forwards FVG mult to Layer-2 M15)
   if(MathAbs(g_fvgVal.impulseBodyRatio - g_msnr.GetLayer2MinDispBodyRatio()) > 0.0001)
     {
      Print("ðŸš¨ [YANSTD] FVG impulse body ratio desync â€” refusing to start. FVGValidator=",
            DoubleToString(g_fvgVal.impulseBodyRatio, 2),
            " Layer2 OB/FVG=", DoubleToString(g_msnr.GetLayer2MinDispBodyRatio(), 2),
            " input=", DoubleToString(InpFVGImpulseBodyRatio, 2));
      return(INIT_PARAMETERS_INCORRECT);
     }
   GetCachedATR(Symbol(), inp_htf_period, InpATRPeriod);
   GetCachedATR(Symbol(), inp_mtf_period, InpATRPeriod);
   // PURE_SMC (3): the MSNR engine is never consulted -- no map, no soft overlay,
   // no MSNR targets. SMC_PRIMARY (2) keeps it as a soft scoring overlay.
   g_signal.SetMSNREngine(&g_msnr, InpSetupMode != SETUP_PURE_SMC);
   g_signal.SetSetupMode(InpSetupMode);
   // PURE_SMC ladder switch on the otherwise-dead InpMinTradeGrade string input:
   // "D"=default, "C"=1 counter-only, "B"=2 no-OTE-veto, "A"=3 both.
   g_signal.SetPureLadder(InpMinTradeGrade == "C" ? 1 :
                          InpMinTradeGrade == "B" ? 2 :
                          InpMinTradeGrade == "A" ? 3 : 0);
   // SetKillzoneFilter/SetMinimumRRRGate tidak ada di engine; keduanya ditangani di EA
   // (killzone di PassEntryMarketQuality, RRR gate di ketiga titik entry).
   if(InpSetupMode != SETUP_PURE_SMC) g_msnr.Scan(InpMSNRScanBars);
   RecoverOpenPositionTargets();

   g_mtf.Init(Symbol());
   g_mtf.Calculate();
   g_signal.SetTrendBullPct(g_mtf.GetResult().bullPct);

   g_signal.SetDependencies((InpUseSmartBrain ? &g_brain : NULL), &g_session);
   g_signal.SetDiagnostics(&g_diagnostics);
   g_signal.SetBrainExplorationMode(g_effectiveCollectionMode || historicalMatrixTest);
   g_signal.SetMaxAggregateRiskPct(InpMaxAggregateRiskPct);

   // H2 (v4.47.8): startup sizing log. gradeMultMax is derived from the
   // single SetupGradeLotMultiplier() table (MaxSetupGradeLotMultiplier()),
   // never a second hardcoded number, so this line can never drift from
   // the table that actually sizes trades.
   double gradeMultMax  = MaxSetupGradeLotMultiplier();
   double effMaxRiskPct = InpRiskPercent * gradeMultMax;
   Print(StringFormat("[YANSTD SIZING] Base risk=%s%% | Grade multiplier max=%sx | Max effective risk/trade=%s%% (before aggregate cap %s%% / Brain overlay)",
                       DoubleToString(InpRiskPercent, 2),
                       DoubleToString(gradeMultMax, 2),
                       DoubleToString(effMaxRiskPct, 2),
                       DoubleToString(InpMaxAggregateRiskPct, 2)));
   Print(StringFormat("[YANSTD SIZING] Absolute lot cap InpMaxLot=%s (0=disabled) | broker max=%s | broker min=%s",
                       (InpMaxLot > 0.0 ? DoubleToString(InpMaxLot, 2) : "OFF"),
                       DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX), 2),
                       DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), 2)));

   // Initialize GUI (Only in Live or Visual Tester mode)
   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     {
      ChartSetInteger(0, CHART_FOREGROUND, false);
      ChartSetInteger(0, CHART_SHOW_GRID, false);
      if(InpShowDashboard)
        {
         g_dashboard.Init(CORNER_LEFT_UPPER, InpDashboardX, InpDashboardY, InpDashboardDark,
                          InpMagicNumber, YANSTD_NAME + " v" + YANSTD_VERSION);
         g_dashboard.SetSetupModeDisplay(g_signal.GetSetupMode());
        }
     }

   UpdateStatsFromHistory();

   g_lotDisplay  = (InpFixedLot > 0) ? InpFixedLot : g_risk.CalcLotSize(InpRiskPercent, 35.0);
   g_riskDisplay = InpRiskPercent;
   g_tp1Enabled  = ((InpExitMode == EXIT_STAGED && InpUseTP1) ||
                    (IsStructuralExitMode() && InpUseTP1));

   string effectiveMode = MQLInfoInteger(MQL_TESTER)
                          ? EnumToString(InpTesterExecutionMode)
                          : (g_autoMode == AUTO_ON ? "LIVE_AUTO" : "LIVE_MANUAL");
   Print("[YANSTD CONFIG] mode=", effectiveMode,
         " | collection=", (g_effectiveCollectionMode ? "ON" : "OFF"),
         " | matrix=", (IsHistoricalMatrixTest() ? "ON" : "OFF"),
         " | spreadCapPts=", g_effectiveMaxSpreadPts,
         " | maxPositions=", g_effectiveMaxPositions,
         " | defaultLot=", DoubleToString(g_lotDisplay, 2),
         " | riskPct=", DoubleToString(g_riskDisplay, 2),
         " | Brain=", (InpUseSmartBrain ? "ON" : "OFF"),
         " | news=", (InpUseNewsFilter ? "ON" : "OFF"),
         " | sessionFilter=", (InpUseTimeFilter ? "ON" : "OFF"),
         " | testerUTC=", InpTesterUTCOffsetWinter,
         " | testerDST=", (InpTesterUseEuropeanDST ? "ON" : "OFF"),
         " | pushAlerts=", (InpEnablePushAlerts ? "ON" : "OFF"),
         " | setupMode=", SetupModeName(InpSetupMode),
         " | exit=", EnumToString(InpExitMode),
         " | slPips=", DoubleToString(InpMinSLPips, 0), "-", DoubleToString(InpMaxSLPips, 0),
         " | version=", YANSTD_VERSION);

   // Initial SMC Calculation
   g_signal.EvaluatePhase1_HTFBias();
   g_signal.EvaluatePhase2_M5POIs();


   RenderAllSMCVisuals();

   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     {
      EventSetTimer(1);
      if(InpShowDashboard)
         OnTimer();
     }

   Print("YANSTD v", YANSTD_VERSION, " Hybrid MSNR+SMC Engine initialized on ", Symbol(),
         " | KingSNR ", EnumToString(InpKingSNR_PrimaryTF), ">", EnumToString(InpKingSNR_SecondaryTF),
         " | M3Sweep=", (InpRequireM3Sweep ? "REQUIRED" : "optional"),
         " | M5subset=", (InpRequireM5ContainedInM15 ? "strict" : "overlap"),
         " [M15 Bias -> M5 POI -> M3 Sweep+ChoCH] | Magic: ", InpMagicNumber);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpUseSmartBrain)
     {
      g_brain.LogEvidenceDensity("DEINIT");
      g_brain.Shutdown();
     }
   if(g_adxM15Handle != INVALID_HANDLE) IndicatorRelease(g_adxM15Handle);
   if(g_atrM5Handle  != INVALID_HANDLE) IndicatorRelease(g_atrM5Handle);
   ReleaseCachedATRHandles();
   g_diagnostics.PrintFinalSummary("DEINIT");

   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     {
      if(InpShowDashboard)
         g_dashboard.Destroy();

      // Clean up chart objects created by this EA
      ObjectsDeleteAll(0, "YANSTD_UI_");
      ObjectsDeleteAll(0, "YANSTD_");
      ObjectsDeleteAll(0, "POI_");
      ObjectsDeleteAll(0, "MACRO_");
      ChartRedraw();
     }

   Print("ðŸ“‹ [YANSTD DEINIT] EA deinitialized | Reason Code: ", reason, " (", GetDeinitReasonText(reason), ")");
  }

//+------------------------------------------------------------------+
//|  OnTick â€” Fast Trading Logic & SMC Execution                      |
//+------------------------------------------------------------------+
void OnTick()
  {
   // L4: detect intraday M5 data discontinuities. Weekend/session gaps are
   // classified and counted. An UNEXPECTED gap also starts GAP_PAUSE, which
   // blocks new entries for InpPauseBarsAfterUnexpectedGap complete bars.
   static datetime lastQualityBar = 0;
   datetime qualityBar = iTime(Symbol(), PERIOD_M5, 1);
   if(qualityBar > 0 && lastQualityBar > 0 && qualityBar > lastQualityBar)
     {
      long deltaMin = (long)(qualityBar - lastQualityBar) / 60;
      if(deltaMin > 5)
        {
         ENUM_DATA_GAP_KIND kind = ClassifyBarGap(Symbol(), lastQualityBar, qualityBar);
         g_diagnostics.RecordDataGap(deltaMin - 5, kind);
         if(kind == DATA_GAP_UNEXPECTED)
           {
            if(InpPauseBarsAfterUnexpectedGap > 0)
              {
               // This tick also opens a new M3 bar and decrements the counter
               // below. Seed one extra so exactly the configured number of
               // complete entry bars remain blocked.
               g_gapPauseBarsLeft = InpPauseBarsAfterUnexpectedGap + 1;
               g_diagnostics.RecordGapPause();
               Print("[YANSTD DATA] GAP_PAUSE start | bars=", InpPauseBarsAfterUnexpectedGap,
                     " | from=", TimeToString(lastQualityBar, TIME_DATE|TIME_MINUTES));
              }
            Print("[YANSTD DATA] UNEXPECTED_DATA_GAP | minutes=", deltaMin,
                  " | from=", TimeToString(lastQualityBar, TIME_DATE|TIME_MINUTES),
                  " | to=", TimeToString(qualityBar, TIME_DATE|TIME_MINUTES));
           }
        }
     }
   if(qualityBar > 0) lastQualityBar = qualityBar;

   // Keep calendar protection alive even when the dashboard timer is disabled.
   if(InpUseNewsFilter && TimeCurrent() - g_lastNewsPoll > YANSTD_NEWS_POLL_SECONDS)
     {
      g_news.RefreshEvents();
      g_lastNewsPoll = TimeCurrent();
     }

   // Spread cap has one explicit active mode: ATR when enabled and available,
   // otherwise the rolling mean+stddev detector when enabled, otherwise the
   // manual hard cap. This makes both spread flags operational and predictable.
   g_spreadMonitor.Sample((int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD));
   double spreadPoint = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double atrSpread   = GetCachedATR(Symbol(), inp_mtf_period, InpATRPeriod);
   int floorPts = (int)MathMax(InpDynamicSpreadFloor,
                               MathRound(InpSpreadCapFloorPips * GetPipFactor(Symbol())));
   if(InpUseATRSpreadGate && InpMaxSpreadATRMult > 0.0 && atrSpread > 0.0 && spreadPoint > 0.0)
     {
       int atrCapPts = (int)MathRound((atrSpread * InpMaxSpreadATRMult) / spreadPoint);
       g_effectiveMaxSpreadPts = (int)MathMax(floorPts, MathMin(inp_max_spread, atrCapPts));
     }
   else if(InpUseDynamicSpread)
      g_effectiveMaxSpreadPts = (int)MathRound(
                                 g_spreadMonitor.GetDynamicThreshold(InpDynamicSpreadStdDevMult,
                                                                     floorPts, inp_max_spread));
   else
      g_effectiveMaxSpreadPts = inp_max_spread;
   if(g_effectiveMaxSpreadPts < 1) g_effectiveMaxSpreadPts = inp_max_spread; // never collapse to zero
   g_signal.SetMaxSpreadPoints(g_effectiveMaxSpreadPts);

   // Live/demo telemetry must be visible while the EA remains attached; a
   // deinit-only summary made an all-day no-trade condition impossible to
   // diagnose until the user removed the EA.
   if(!MQLInfoInteger(MQL_TESTER) && InpDiagnosticIntervalMinutes > 0)
     {
      static datetime lastLiveDiagnostic = 0;
      int intervalSeconds = MathMax(1, InpDiagnosticIntervalMinutes) * 60;
      if(lastLiveDiagnostic == 0) lastLiveDiagnostic = TimeCurrent();
      else if(TimeCurrent() - lastLiveDiagnostic >= intervalSeconds)
        {
         g_diagnostics.PrintSummary("LIVE_PERIODIC");
         Print("[YANSTD MSNR] ", g_msnr.GetDiagOverlapSummary());
         lastLiveDiagnostic = TimeCurrent();
        }
     }

   static datetime lastStatsDay = 0;
   datetime curDay = g_session.GetSimulatedUTC() / 86400;
   if(curDay != lastStatsDay)
     {
      UpdateStatsFromHistory();
      lastStatsDay = curDay;

      // Tester Heartbeat: Log scan progress at the start of each month
      static int lastLoggedMonth = -1;
      MqlDateTime dtCur;
      TimeToStruct(TimeCurrent(), dtCur);
      if(dtCur.mon != lastLoggedMonth && MQLInfoInteger(MQL_TESTER))
        {
          Print("ðŸ“¡ [YANSTD SCANNER PROGRESS] Periode: ", dtCur.year, ".", StringFormat("%02d", dtCur.mon),
               " | Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
               " | Active POIs: ", g_signal.GetPOICount(),
               " | Total Trades: ", g_stats.totalTrades,
                " | Winrate: ", DoubleToString(CalcWinRate(g_stats.totalWins, g_stats.totalTrades), 1), "%");
         g_diagnostics.PrintMonthlySummary(g_signal.GetPOICount(), g_stats.totalTrades,
                                            g_stats.totalWins, AccountInfoDouble(ACCOUNT_BALANCE));
         Print("[YANSTD MSNR] ", g_msnr.GetDiagOverlapSummary());
         lastLoggedMonth = dtCur.mon;
        }
     }

   // 1. Performance Optimization: Calculate Phase 1 (M15) only on new M15 bar
   if(g_signal.IsNewBar(inp_htf_period, g_lastHTFBarTime))
      OnNewHTFBar();

   // 2. Performance Optimization: Calculate Phase 2 (M5 POIs) only on new M5 bar
   if(g_signal.IsNewBar(g_effectiveRefinementTF, g_lastMTFBarTime))
      OnNewMTFBar();

   // A pending order must be withdrawn as soon as the POI is structurally
   // invalidated by the configured closed M3 bars. This runs independently of
   // entry capacity, so a full pending book cannot defer the cleanup to M5.
   if(g_signal.IsNewBar(inp_ltf_period, g_lastLTFBarTime))
     {
      if(g_gapPauseBarsLeft > 0)
        {
         g_gapPauseBarsLeft--;
         if(g_gapPauseBarsLeft <= 0)
            Print("[YANSTD DATA] GAP_PAUSE end");
        }
      int invalidatedPOIs = g_signal.RefreshPOIInvalidation();
      if(invalidatedPOIs > 0)
        {
         ReconcilePOIPendingFlags();
         LogMsg(LOG_LEVEL_INFO, "POI_INVALIDATED",
                StringFormat("Invalidated %d POI(s) on closed %s bars; matching pending orders reconciled",
                             invalidatedPOIs, EnumToString(inp_ltf_period)));
        }
      g_mtf.Calculate();
      g_signal.SetTrendBullPct(g_mtf.GetResult().bullPct);
      OnNewLTFBar();
     }

   // 3. Tester GUI sync (Visual Mode only)
   if(MQLInfoInteger(MQL_TESTER) && MQLInfoInteger(MQL_VISUAL_MODE))
     {
      static datetime lastTesterTick = 0;
      if(TimeCurrent() - lastTesterTick >= 1)
        {

         UpdateStatsFromHistory();
         if(InpShowDashboard)
            OnTimer();
         lastTesterTick = TimeCurrent();
        }
     }

   // 4. Update Position State
   UpdatePositionState();
   g_diagnostics.UpdateEquityPeak();
   g_orders.AuditCloseRequests();

   // 5. Friday Weekend Auto-Close Protection
   if(InpFridayCloseEnabled)
     {
      MqlDateTime dt;
      bool inWindow = g_session.IsFridayCloseWindow(InpFridayCloseHour, dt);
      static datetime s_lastFridayDiag = 0;
      static int s_lastFridayYmd = -1;
      int fridayYmd = dt.year * 10000 + dt.mon * 100 + dt.day;
      if(inWindow)
        {
         g_orders.DeleteAllPendingByMagic();
         g_signal.ClearAllPOIPendingLimits();
         int fridayBefore = g_orders.CountOpenPositions();
         bool newFriday = (s_lastFridayYmd != fridayYmd);
         bool allowLog = newFriday || (TimeCurrent() - s_lastFridayDiag >= 300);
         if(fridayBefore <= 0)
           {
            if(allowLog)
              {
               Print("[YANSTD FRIDAY CLOSE] skip | reason=no_positions | UTC=",
                     TimeToString(g_session.GetSimulatedUTC(), TIME_DATE|TIME_MINUTES));
               s_lastFridayDiag = TimeCurrent();
               s_lastFridayYmd = fridayYmd;
              }
            return;
           }
         if(allowLog)
           {
            Print("[YANSTD FRIDAY CLOSE] requested | UTC=",
                  TimeToString(g_session.GetSimulatedUTC(), TIME_DATE|TIME_SECONDS),
                  " | Positions=", fridayBefore);
            s_lastFridayDiag = TimeCurrent();
            s_lastFridayYmd = fridayYmd;
           }
         if(g_orders.CloseAllByMagic())
           {
            g_diagnostics.RecordFridayClose();
            Print("[YANSTD FRIDAY CLOSE] executed | requested positions=", fridayBefore);
           }
         else if(allowLog)
            Print("[YANSTD FRIDAY CLOSE] broker error; managed close requests will retry on subsequent ticks.");
         return;
        }
     }

   // AUDIT FIX: snapshot tickets up front instead of iterating by cache
   // index. If a position fully closes mid-loop (e.g. an undersized TP1
   // collapses the whole position), the index->ticket mapping used to be
   // rebuilt in place, which could cause an already-open position to be
   // skipped for the rest of this tick. Iterating a stable ticket snapshot
   // and resolving each one by ticket avoids that entirely.
   int openCount = g_orders.CountOpenPositions();
   ulong openTickets[];
   ArrayResize(openTickets, openCount);
   int openTicketCount = 0;
   for(int p = openCount - 1; p >= 0; p--)
     {
      SPositionInfo snap;
      if(g_orders.GetPosition(p, snap))
         openTickets[openTicketCount++] = snap.ticket;
     }
   for(int t = 0; t < openTicketCount; t++)
     {
       SPositionInfo pos;
       if(g_orders.GetPositionByTicket(openTickets[t], pos))
         {
           UpdatePositionExcursion(pos);
          if(ApplyTimeInvalidation(pos)) continue;
       // Stage 1: optional early BEP protection before TP1.
         if(InpUseEarlyBEP && !pos.bepDone && !pos.tp1Done)
            g_partial.CheckEarlyBEP(pos, InpUseEarlyBEP, InpEarlyBEPPips, InpEarlyBEPBuffer);

         // Stage 1b: Opposing POI Guard (Exit / Partial Early if hitting opposing institutional OB)
         if(InpExitMode == EXIT_STAGED && InpUseOpposingPOIExit && !pos.tp1Done)
           {
            double pip = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
            double curPrice = (pos.posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            double profitPips = (pos.posType == POSITION_TYPE_BUY) ? ((curPrice - pos.openPrice) / pip) : ((pos.openPrice - curPrice) / pip);
            if(profitPips >= InpOpposingMinProfitPips && g_signal.IsOpposingZoneHit(pos.posType, curPrice, 5.0))
              {
               Print("YANSTD Opposing OB Guard: Approaching Wall! Securing Partial TP1 Early @ +", DoubleToString(profitPips, 1), " pips | Ticket=", pos.ticket);
               g_partial.CheckAndExecuteTP1(pos, true, InpTP1ClosePct, InpTP1ProfitLockPips, true); // forceEarly=true bypasses IsTP1Hit for Opposing Guard
              }
           }

      // Stage 2: configurable TP1 partial close and profit-lock SL.
         if(g_tp1Enabled && !pos.tp1Done)
            g_partial.CheckAndExecuteTP1(pos, g_tp1Enabled, InpTP1ClosePct, InpTP1ProfitLockPips);

         // A small position may be closed in full at TP1 because its volume
         // cannot support the 50/25/runner split. Never continue trailing or
         // invoke TP2 against that already-closed ticket.
         if(!PositionSelectByTicket(pos.ticket)) continue;

         // At 1R this applies only BE+spread. Confirmed M3 structure trailing
         // is allowed after TP1 has completed (default start 1.5R).
         if(!IsStructuralExitMode())
            ApplyM3StructureProtection(pos);

         // Gen-5: once remembered MFE reaches the trigger, lock profit in R.
         if(InpUseMilestoneLock && !pos.milestoneDone)
           {
            double triggerR = InpMilestoneTriggerR;
            double lockR = InpMilestoneLockR;
            double pipPos = SymbolInfoDouble(pos.symbol, SYMBOL_POINT) * GetPipFactor(pos.symbol);
            if(triggerR <= 0.0 && pos.initialRiskPrice > 0.0 && pipPos > 0.0)
               triggerR = InpMilestoneTriggerPips * pipPos / pos.initialRiskPrice;
            if(lockR <= 0.0 && pos.initialRiskPrice > 0.0 && pipPos > 0.0)
               lockR = InpMilestoneLockPips * pipPos / pos.initialRiskPrice;
            g_partial.CheckMilestoneLock(pos, true, triggerR, lockR);
           }

         if(pos.tp1Done && !IsStructuralExitMode())
            g_partial.CheckAndExecuteTP2(pos);

         // Stage 3: confirmed-swing trailing is active only for the runner after TP2.
         if(InpUseTrailing && pos.tp2Done && !IsStructuralExitMode())
            g_trail.Process(pos);
        }
     }

   ENUM_NEWS_STATUS newsStatus = g_news.GetStatus();
   if(InpUseNewsFilter)
      ManageNewsLivePositions(newsStatus);

   static bool s_dailyLossHaltActive = false;
   static bool s_equityDDHaltActive  = false;

   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double startDayBalance = currentBalance - g_stats.dailyProfit;
   double liveDailyPnL = g_stats.dailyProfit + g_orders.GetTotalFloatingPnL();
   double liveDailyPct = (startDayBalance > 0.0) ? (liveDailyPnL / startDayBalance) * 100.0 : 0.0;
   if(InpMaxDailyLossPct > 0.0 && liveDailyPct <= -InpMaxDailyLossPct)
     {
      g_diagnostics.Record(REJECT_DAILY_LOSS, (long)iTime(Symbol(), inp_ltf_period, 0));
      if(!s_dailyLossHaltActive)
        {
         g_diagnostics.RecordCircuitBreakerHalt();
         SendCriticalAlert("DAILY_LOSS",
                           StringFormat("New entries halted: daily P/L %.2f%% reached limit -%.2f%%",
                                        liveDailyPct, InpMaxDailyLossPct), 3600);
         s_dailyLossHaltActive = true;
        }
      g_orders.DeleteAllPendingByMagic();
      g_signal.ClearAllPOIPendingLimits();
      return;
     }
   else
      s_dailyLossHaltActive = false;

   // L2: account-level equity drawdown breaker. Unlike the daily guard this is
   // anchored to the highest equity observed during the run and does not reset
   // at midnight. Existing positions remain managed/protected; only new risk
   // is stopped and all pending entries are removed.
   double equityDD = g_diagnostics.GetEquityDDPct();
   if(InpMaxEquityDDPct > 0.0 && equityDD >= InpMaxEquityDDPct)
     {
      g_diagnostics.Record(REJECT_EQUITY_DD, (long)iTime(Symbol(), inp_ltf_period, 0));
      if(!s_equityDDHaltActive)
        {
         g_diagnostics.RecordCircuitBreakerHalt();
         LogMsg(LOG_LEVEL_ERROR, "L2_EQUITY_BREAKER",
                StringFormat("New entries halted: peak-equity drawdown %.2f%% >= limit %.2f%%",
                             equityDD, InpMaxEquityDDPct));
         SendCriticalAlert("EQUITY_DD",
                           StringFormat("New entries halted: equity drawdown %.2f%% reached %.2f%%",
                                        equityDD, InpMaxEquityDDPct), 3600);
         s_equityDDHaltActive = true;
        }
      g_orders.DeleteAllPendingByMagic();
      g_signal.ClearAllPOIPendingLimits();
      return;
     }
   else
      s_equityDDHaltActive = false;

   if(InpMinMarginLevelPct > 0.0)
     {
      double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);
      if(usedMargin > 0.0)
        {
         double marginLevelPct = AccountInfoDouble(ACCOUNT_EQUITY) / usedMargin * 100.0;
         if(marginLevelPct <= InpMinMarginLevelPct)
           {
            g_diagnostics.Record(REJECT_MARGIN_LEVEL, (long)iTime(Symbol(), inp_ltf_period, 0));
            g_orders.DeleteAllPendingByMagic();
            g_signal.ClearAllPOIPendingLimits();
            return;
           }
        }
     }

   if(InpUseNewsFilter && newsStatus != NEWS_CLEAR)
     {
      g_diagnostics.Record(REJECT_NEWS, (long)iTime(Symbol(), inp_ltf_period, 0));
      g_orders.DeleteAllPendingByMagic();
      g_signal.ClearAllPOIPendingLimits();
      return;
     }

   // 8. Auto SMC Execution (Auto Limit Order or Market Confirmation Trigger)
   if(g_autoMode == AUTO_ON)
     {
       if(!PassEntryMarketQuality((long)iTime(Symbol(), inp_ltf_period, 0))) return;
       bool historicalMatrixTest = IsHistoricalMatrixTest();
        if(historicalMatrixTest)
          {
           // M3 confirmation supplies the highest-quality context. Without it,
           // direct-zone mode may still stage parent M15/M5 OB/FVG limits.

            if(!ShouldRunGenerateSignal()) return;
            MarkGenerateSignalRan();
            SSignal matrixTrigger = g_signal.GenerateSignal(InpCollectionRiskPct, true, g_lotDisplay, false);
            NoteLotStatus(g_risk.LastLotStatus());
            if(matrixTrigger.isValid)
             {
              matrixTrigger.setupEventId = BuildSetupEventId(matrixTrigger);
              g_matrixTriggerContext = matrixTrigger;
              g_hasMatrixTriggerContext = true;
               // H8: MATRIX_COLLECTION is an explicit research mode only. The
               // normal tester defaults to TESTER_MATRIX_OFF and takes one best
               // candidate, exactly like live. Even collection mode respects the
               // operator whitelist and the cluster-distance gate.
               int placedSiblings = 0;
               for(int matrixPass = 0; matrixPass < ENTRY_VARIANT_COUNT; matrixPass++)
                 {
                  if(!g_entryVariants.IsAllowed((ENUM_SMC_ENTRY_TYPE)matrixPass)) continue;
                  if(ManageAutoLimitOrders(matrixPass, matrixTrigger.zoneIndex, "CONFIRMED")) placedSiblings++;
                 }
              RegisterMatrixSiblingCount(matrixTrigger.setupEventId, placedSiblings);
              g_hasMatrixTriggerContext = false;
             }
            else if(InpScanAllPOIsWhenNoTrigger)
             {
              // One structural scan per M3 bar avoids repeating the whole POI x
              // variant matrix on every real tick while preserving direct retests.
              static datetime lastDirectMatrixScanBar = 0;
              datetime directMatrixScanBar = iTime(Symbol(), inp_ltf_period, 0);
              if(directMatrixScanBar > 0 && directMatrixScanBar != lastDirectMatrixScanBar)
                {
                 lastDirectMatrixScanBar = directMatrixScanBar;
                 for(int matrixPass = 0; matrixPass < ENTRY_VARIANT_COUNT; matrixPass++)
                   {
                    if(!g_entryVariants.IsAllowed((ENUM_SMC_ENTRY_TYPE)matrixPass)) continue;
                    ManageAutoLimitOrders(matrixPass, -1, "DIRECT");
                   }
                }
             }
         }
       else if(g_orders.CountOpenPositions() < g_effectiveMaxPositions)
          TryAutoEntry();
     }
  }

//+------------------------------------------------------------------+
//|  OnTimer â€” GUI rendering ONLY (1 second)                         |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   if(!InpShowDashboard) return;

   if(InpUseNewsFilter && TimeCurrent() - g_lastNewsPoll > YANSTD_NEWS_POLL_SECONDS)
     {
      g_news.RefreshEvents();
      g_lastNewsPoll = TimeCurrent();
     }

   static datetime lastStatsRefresh = 0;
   if(TimeCurrent() - lastStatsRefresh >= 60)
     {
      UpdateStatsFromHistory();
      lastStatsRefresh = TimeCurrent();
     }
   ENUM_NEWS_STATUS  newsStatus = InpUseNewsFilter ? g_news.GetStatus() : NEWS_CLEAR;
   double            floatPnL   = g_orders.GetTotalFloatingPnL();

   if(InpFixedLot <= 0 && !g_lotManual)
      g_lotDisplay = g_risk.CalcLotSize(g_riskDisplay, 35.0);

   int openCount = g_orders.CountOpenPositions();
   int pendingCount = g_orders.CountPendingOrders();
   if(openCount < g_effectiveMaxPositions && ShouldRunGenerateSignal())
     {
      g_lastSignal = g_signal.GenerateSignal(g_riskDisplay, (InpFixedLot <= 0), g_lotDisplay, false, false);
      MarkGenerateSignalRan();
     }
   g_dashboard.SetSetupModeDisplay(g_signal.GetSetupMode());
   g_dashboard.Render(floatPnL, openCount, pendingCount,
                      g_lotDisplay, g_riskDisplay, g_tp1Enabled, g_autoMode,
                      g_effectiveMaxPositions, g_signal.GetPOICount() > 0,
                      newsStatus, g_lastSignal, g_mtf.GetResult(),
                      InpUseNewsFilter ? g_news.GetNextEventLabel() : "News filter OFF",
                      SessionLabel(g_session.GetCurrentSession()));

   static datetime lastRenderBar = 0;
   static int lastRenderPOICount = -1;
   datetime renderBar = iTime(Symbol(), inp_ltf_period, 0);
   int poiCount = g_signal.GetPOICount();
   if(g_dashboard.LayersVisible())
     {
      if(renderBar != lastRenderBar || poiCount != lastRenderPOICount)
        {
         RenderAllSMCVisuals();
         lastRenderBar = renderBar;
         lastRenderPOICount = poiCount;
        }
     }
   else if(lastRenderPOICount != -2)
     {
      ObjectsDeleteAll(0, "POI_");
      ObjectsDeleteAll(0, "MACRO_");
      ObjectsDeleteAll(0, "YANSTD_M15_STRUCT_");
      ObjectsDeleteAll(0, "YANSTD_M3_STRUCT_");
      ObjectsDeleteAll(0, "YANSTD_M15_STRUCTURE_EVENT");
      ObjectsDeleteAll(0, "YANSTD_STR_M15_");
      ObjectsDeleteAll(0, "YANSTD_STR_M3_");
      ObjectsDeleteAll(0, "YANSTD_M15_SWING_");
      ObjectsDeleteAll(0, "YANSTD_M15_EQ");
      lastRenderPOICount = -2;
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|  OnChartEvent â€” Button Handler                                   |
//+------------------------------------------------------------------+
double RequiredStructuralRR()
  {
   if(InpExitMode == EXIT_FIXED_RR)
      return MathMax(InpMinimumStructuralRRR, InpFixedRR);
   // A structural target before TP2 means the runner is deliberately pointed
   // through opposing liquidity. Keep the operator's baseline, but require room
   // to the actual staged target whenever staged exits are enabled.
   return InpUseTP1 ? MathMax(InpMinimumStructuralRRR, InpTP2RR)
                    : InpMinimumStructuralRRR;
  }

bool PassManualEntryGuards(const SSignal &sig, ENUM_ORDER_TYPE orderType)
  {
   long key = (long)iTime(Symbol(), inp_ltf_period, 0);
   if(!sig.isValid) return false;
   if(g_orders.CountOpenPositions() >= g_effectiveMaxPositions)
     { g_diagnostics.Record(REJECT_POSITION_LIMIT, key); return false; }
   if(InpUseNewsFilter && g_news.IsBlocked())
     { g_diagnostics.Record(REJECT_NEWS, key); return false; }
   if(InpUseTimeFilter && !TimeFilterAllowsEntry())
     { g_diagnostics.Record(REJECT_TIME_FILTER, key); return false; }
   if(GapPauseBlocksEntry())
     { g_diagnostics.Record(REJECT_GAP_PAUSE, key); return false; }
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dayStart = balance - g_stats.dailyProfit;
   double dayPct = (dayStart > 0.0)
                   ? (g_stats.dailyProfit + g_orders.GetTotalFloatingPnL()) / dayStart * 100.0 : 0.0;
   if(InpMaxDailyLossPct > 0.0 && dayPct <= -InpMaxDailyLossPct)
     { g_diagnostics.Record(REJECT_DAILY_LOSS, key); return false; }
   if((int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) > g_effectiveMaxSpreadPts)
     { g_diagnostics.Record(REJECT_SPREAD, key); return false; }
   if(!PassEntryMarketQuality(key)) return false;
   if(InpUseMinimumRRRGate)
     {
      ENUM_ZONE_TYPE side = (orderType == ORDER_TYPE_BUY) ? ZONE_DEMAND : ZONE_SUPPLY;
      double target = GetStructuralTarget(sig.entryPrice, side);
      double risk = MathAbs(sig.entryPrice - sig.slPrice);
      double reward = (orderType == ORDER_TYPE_BUY) ? target - sig.entryPrice : sig.entryPrice - target;
       if(target <= 0.0 || risk <= 0.0 || reward / risk < RequiredStructuralRR())
        { g_diagnostics.Record(REJECT_MIN_RRR, key); return false; }
     }
   double fillRef = 0.0;
   double fillLots = ResizeLotForMarketFill(sig, orderType, fillRef);
   if(fillLots <= 0.0)
     { g_diagnostics.Record(REJECT_LOT_TOO_SMALL, key); return false; }
   double projected = 0.0;
   if(!CanAddAggregateRisk(orderType, fillLots, fillRef, sig.slPrice, projected))
     { g_diagnostics.Record(REJECT_AGGREGATE_RISK, key); return false; }
   return true;
  }

void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   if(InpShowDashboard && g_dashboard.HandleClick(sparam))
     {
      OnTimer();
      ChartRedraw();
      return;
     }

   if(sparam == BTN_MODE_SMC || sparam == BTN_MODE_PURE)
     {
      ENUM_SETUP_MODE next = (sparam == BTN_MODE_PURE) ? SETUP_PURE_SMC : SETUP_SMC_PRIMARY;
      if(next != g_signal.GetSetupMode())
        {
         g_orders.DeleteAllPendingByMagic();
         g_signal.ClearAllPOIPendingLimits();
         g_signal.SetSetupMode(next);
         g_dashboard.SetSetupModeDisplay(next);
         Print("[YANSTD SETUP MODE] ", SetupModeName(next),
               " | pending cleared | next signal uses this mode");
         g_dashboard.Notify("Mode " + SetupModeName(next) + " â€” pending cleared");
        }
      OnTimer();
      ChartRedraw();
      return;
     }

   if(sparam == BTN_BUY_MARKET || sparam == BTN_SELL_MARKET)
     {
      // Manual entry is NOT a blind market order: it executes the CURRENT engine
      // signal only. Rejections are now surfaced on the dashboard (Signal card)
      // instead of failing silently.
      bool wantBuy = (sparam == BTN_BUY_MARKET);
      SSignal sig = g_signal.GenerateSignal(g_riskDisplay, (InpFixedLot <= 0), g_lotDisplay);
      string side = wantBuy ? "BUY" : "SELL";
      if(!sig.isValid)
        {
         g_dashboard.Notify("Manual " + side + " rejected: no valid setup is available" +
                            (sig.invalidReason != "" ? " (" + sig.invalidReason + ")" : ""));
         OnTimer(); ChartRedraw(); return;
        }
      if((wantBuy && sig.direction != SIGNAL_BUY) || (!wantBuy && sig.direction != SIGNAL_SELL))
        {
         g_dashboard.Notify("Manual " + side + " rejected: active setup direction is " +
                            (sig.direction == SIGNAL_BUY ? "BUY" : "SELL"));
         OnTimer(); ChartRedraw(); return;
        }
      if(!PassManualEntryGuards(sig, wantBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL))
        {
         g_dashboard.Notify("Manual " + side + " rejected by guard (capacity / risk / news / duplicate)");
         OnTimer(); ChartRedraw(); return;
        }
      if(wantBuy) ExecuteBuy(sig); else ExecuteSell(sig);
     }
   else if(sparam == BTN_PASANG_LIMIT)
     {
      if(InpUseNewsFilter && g_news.IsBlocked()) return;
      ManageAutoLimitOrders(-1, -1, "MANUAL");
     }
   else if(sparam == BTN_TP1_TOGGLE)
     {
      if(InpExitMode == EXIT_FIXED_RR)
        {
         g_dashboard.Notify("TP1 is not used in FIXED_RR mode");
         return;
        }
      g_tp1Enabled = !g_tp1Enabled;
     }
   else if(sparam == BTN_CUT50)
     {
      if(!g_hasPosition) return;
      double step    = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
      double lotMin  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
      double halfLot = (step > 0.0) ? MathFloor((g_posInfo.lots * 0.5 + 1e-12) / step) * step
                                    : g_posInfo.lots * 0.5;
      if(halfLot < lotMin || halfLot >= g_posInfo.lots || (g_posInfo.lots - halfLot) < lotMin)
        {
         Print("YANSTD Cut50: Position volume cannot be split safely at broker minimum/step.");
         return;
        }
      g_orders.PartialClose(g_posInfo.ticket, halfLot);
     }
   else if(sparam == BTN_HAPUS_ORDER)
     {
      g_orders.DeleteAllPendingByMagic();
      g_signal.ClearAllPOIPendingLimits();
     }
   else if(sparam == BTN_AUTO_TOGGLE)
     {
      g_autoMode = (g_autoMode == AUTO_ON) ? AUTO_OFF : AUTO_ON;
      if(g_autoMode == AUTO_OFF)
        {
         g_orders.DeleteAllPendingByMagic();
         g_signal.ClearAllPOIPendingLimits();
        }
      Print("YANSTD SMC: Auto Mode -> ", (g_autoMode == AUTO_ON) ? "ON" : "OFF");
      if(g_autoMode == AUTO_ON &&
         (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0 || MQLInfoInteger(MQL_TRADE_ALLOWED) == 0))
         g_dashboard.Notify("AUTO is ON, but MT5 Algo Trading or EA permission is OFF; enable Algo Trading in the toolbar");
     }
   else if(sparam == BTN_CLOSE_ALL)
     {
      if(!g_closeAllPending)
         {
          g_closeAllPending = true;
          g_closeAllTick    = GetTickCount64();
          Print("YANSTD: âš  CLOSE ALL â€” Click again within 3s to confirm.");
         }
      else if(GetTickCount64() - g_closeAllTick <= 3000)
         {
          bool positionsClosed = g_orders.CloseAllByMagic();
          bool ordersDeleted   = g_orders.DeleteAllPendingByMagic();
          ReconcilePOIPendingFlags();
          g_closeAllPending = false;
          UpdatePositionState();
          if(positionsClosed && ordersDeleted)
             Print("YANSTD: All positions and pending orders closed.");
          else
             Print("YANSTD: CLOSE ALL completed with broker errors. Check remaining trades and Journal.");
        }
      else
        {
         g_closeAllPending = false;
        }
     }
   else if(sparam == BTN_LOT_MINUS)
     {
      double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
      double minL = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
      if(step <= 0.0) step = minL;
      g_lotManual = true;
      g_lotDisplay = MathMax(minL, g_risk.RoundLotToStep(g_lotDisplay - step));
     }
   else if(sparam == BTN_LOT_PLUS)
     {
      double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
      double maxL = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
      double minL = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
      if(step <= 0.0) step = minL;
      g_lotManual = true;
      g_lotDisplay = MathMin(maxL, g_risk.RoundLotToStep(g_lotDisplay + step));
     }
   else if(sparam == BTN_RISK_05) { g_riskDisplay = 0.5; UpdateLotFromRisk(); }
   else if(sparam == BTN_RISK_10) { g_riskDisplay = 1.0; UpdateLotFromRisk(); }
   else if(sparam == BTN_RISK_15) { g_riskDisplay = 1.5; UpdateLotFromRisk(); }
   else if(sparam == BTN_RISK_20) { g_riskDisplay = 2.0; UpdateLotFromRisk(); }
   else if(sparam == BTN_CLEAR_WR)
     {
      ZeroMemory(g_stats);
      g_stats.resetEpoch = TimeCurrent();
      // M4: a manual reset is one of the few cases allowed to pay for a full
      // history rebuild -- it must happen immediately (not lazily on the next
      // deal) so the dashboard reflects the reset right away, and so trades
      // closed before resetEpoch are correctly dropped from the persistent
      // per-position accumulators rather than left stale inside them.
      g_statsHistoryDirty = true;
      RebuildStatsHistoryFull();
      Print("ðŸ—‘ [YANSTD] Win Rate & Trade Stats manually reset to 0 by user.");
     }

   OnTimer();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|  SMC BAR EVENT HANDLERS                                          |
//+------------------------------------------------------------------+
void OnNewHTFBar()
  {
   UpdateStatsFromHistory();
   if(InpSetupMode != SETUP_PURE_SMC) g_msnr.Scan(InpMSNRScanBars);
   g_signal.EvaluatePhase1_HTFBias();


   RenderAllSMCVisuals();
  }

void OnNewMTFBar()
  {
   g_signal.EvaluatePhase2_M5POIs();
   // A GTC limit is valid only while its originating POI is still active.
   // Reconcile on every refinement bar, even when no fresh M3 signal occurs,
   // so stale limits cannot survive for hours and trigger through their SL.
   ReconcilePOIPendingFlags();
   RenderAllSMCVisuals();
  }

void OnNewLTFBar()
  {
   // Chart/attribution only: mirrors M15 structure detection on the LTF slot.
   g_signal.EvaluateM3Structure();
  }

//+------------------------------------------------------------------+
//|  RENDER ALL SMC VISUALS (OB, FVG, BOS/CHoCH, EQUILIBRIUM)        |
//+------------------------------------------------------------------+
void ApplySMCRectStatic(const string name, const color border, const color bg,
                        const int width, const ENUM_LINE_STYLE style, const int zorder)
  {
   ObjectSetInteger(0, name, OBJPROP_COLOR,      border);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     zorder);
  }

void ApplySMCTrendStatic(const string name, const color clr, const ENUM_LINE_STYLE style,
                         const int width, const bool rayRight)
  {
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_BACK,      true);
  }

void ApplySMCLabelStatic(const string name, const color clr, const string font,
                         const int fontSize, const int zorder)
  {
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetString(0,  name, OBJPROP_FONT,       font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     zorder);
  }

void UpsertMapRect(const string name, datetime t1, double p1, datetime t2, double p2,
                   const color border, const color bg, const int width, const ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 1, p2);
     }
   ApplySMCRectStatic(name, border, bg, width, style, 0);
  }

void UpsertMapSegment(const string name, datetime t1, double p1, datetime t2, double p2,
                      const color clr, const ENUM_LINE_STYLE style, const int width)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 1, p2);
     }
   ApplySMCTrendStatic(name, clr, style, width, false);
  }

void UpsertMapTrend(const string name, datetime t1, double price, datetime t2,
                    const color clr, const ENUM_LINE_STYLE style, const int width)
  {
   UpsertMapSegment(name, t1, price, t2, price, clr, style, width);
  }

void UpsertMapLabel(const string name, datetime t, double price, const string text, const color clr, const int fontSize)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME,  0, t);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, price);
     }
   ApplySMCLabelStatic(name, clr, "Arial", fontSize, 3);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void UpsertPivotMark(const string name, datetime t, double price, const string text, const color clr)
  {
   if(t <= 0 || price <= 0.0) { ObjectDelete(0, name); return; }
   UpsertMapLabel(name, t, price, text, clr, 8);
  }

void RenderSwingPairLabels(const string prefix, const SMC_SwingPoint &lastHigh, const SMC_SwingPoint &prevHigh,
                           const SMC_SwingPoint &lastLow, const SMC_SwingPoint &prevLow)
  {
   const color hhClr = clrLime;
   const color lhClr = clrOrange;
   const color hlClr = clrDodgerBlue;
   const color llClr = clrTomato;
   string lastH = (lastHigh.price > prevHigh.price && prevHigh.price > 0.0) ? "HH" : "LH";
   string lastL = (lastLow.price > prevLow.price && prevLow.price > 0.0) ? "HL" : "LL";
   string prevH = (prevHigh.price > 0.0 && lastHigh.price > 0.0)
                  ? ((prevHigh.price > lastHigh.price) ? "HH" : "LH") : "H";
   string prevL = (prevLow.price > 0.0 && lastLow.price > 0.0)
                  ? ((prevLow.price > lastLow.price) ? "HL" : "LL") : "L";
   UpsertPivotMark(prefix + "LAST_H", lastHigh.time, lastHigh.price, lastH, (lastH == "HH") ? hhClr : lhClr);
   UpsertPivotMark(prefix + "PREV_H", prevHigh.time, prevHigh.price, prevH, (prevH == "HH") ? hhClr : lhClr);
   UpsertPivotMark(prefix + "LAST_L", lastLow.time, lastLow.price, lastL, (lastL == "HL") ? hlClr : llClr);
   UpsertPivotMark(prefix + "PREV_L", prevLow.time, prevLow.price, prevL, (prevL == "HL") ? hlClr : llClr);
   if(prevHigh.time > 0 && lastHigh.time > 0 && prevHigh.price > 0.0 && lastHigh.price > 0.0)
      UpsertMapSegment(prefix + "HIGH_LINK", prevHigh.time, prevHigh.price, lastHigh.time, lastHigh.price,
                       (lastH == "HH") ? hhClr : lhClr, STYLE_DOT, 1);
   if(prevLow.time > 0 && lastLow.time > 0 && prevLow.price > 0.0 && lastLow.price > 0.0)
      UpsertMapSegment(prefix + "LOW_LINK", prevLow.time, prevLow.price, lastLow.time, lastLow.price,
                       (lastL == "HL") ? hlClr : llClr, STYLE_DOT, 1);
  }

void ClearStaleMapObjects(const string prefix, const int keepCount)
  {
   for(int i = keepCount; i < 80; i++)
     {
      string base = prefix + IntegerToString(i);
      ObjectDelete(0, base);
      ObjectDelete(0, base + "_LBL");
      ObjectDelete(0, base + "_HEAD");
      ObjectDelete(0, base + "_HEAD_LBL");
      ObjectDelete(0, base + "_KEY");
      ObjectDelete(0, base + "_KEY_LBL");
      ObjectDelete(0, base + "_618");
      ObjectDelete(0, base + "_618_LBL");
      ObjectDelete(0, base + "_705");
      ObjectDelete(0, base + "_705_LBL");
      ObjectDelete(0, base + "_790");
      ObjectDelete(0, base + "_790_LBL");
      ObjectDelete(0, base + "_786");
      ObjectDelete(0, base + "_786_LBL");
      ObjectDelete(0, base + "_OB");
      ObjectDelete(0, base + "_OB_LBL");
      ObjectDelete(0, base + "_FVG");
      ObjectDelete(0, base + "_FVG_LBL");
     }
  }

// Draws a bounded structure-event history into indexed object slots. The slot
// index is the array position so ClearStaleMapObjects(prefix, count) can drop
// slots that are no longer in use. Colors match the legacy single-event style.
void RenderStructureEventHistory(const SStructureEvent &events[], const int count,
                                 const string prefix, const string tfLabel,
                                 const datetime tEnd)
  {
   for(int i = 0; i < count; i++)
     {
      if(events[i].evt == STRUCTURE_EVENT_NONE || events[i].level <= 0.0 || events[i].barTime <= 0)
         continue;
      const bool bullEvt = (events[i].evt == STRUCTURE_BOS_BULLISH ||
                            events[i].evt == STRUCTURE_CHOCH_BULLISH);
      const bool isChoch = (events[i].evt == STRUCTURE_CHOCH_BULLISH ||
                            events[i].evt == STRUCTURE_CHOCH_BEARISH);
      const color evtClr = isChoch ? (bullEvt ? clrAqua : clrOrchid) : (bullEvt ? clrLime : clrTomato);
      const string name = prefix + IntegerToString(i);
      UpsertMapTrend(name, events[i].barTime, events[i].level, tEnd, evtClr, STYLE_SOLID, 2);
      UpsertMapLabel(name + "_LBL", events[i].barTime, events[i].level,
                     "  " + tfLabel + " " + StructureEventLabel(events[i].evt), evtClr, 9);
     }
   ClearStaleMapObjects(prefix, count);
  }

void RenderMSNRMapVisuals()
  {
   if(!InpShowMSNRMap && !InpShowFibLevels) return;
   const int cap = 40;
   int drawn = 0;
   int fibDrawn = 0;
   int total = g_msnr.GetZoneCount();
   datetime tNow = TimeCurrent();
   datetime tEnd = tNow + PeriodSeconds(inp_htf_period) * 8;
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   for(int i = total - 1; i >= 0 && drawn < cap; i--)
     {
      SMSNR_Zone z;
      if(!g_msnr.GetZone(i, z)) continue;
      if(!z.isActive || z.isMitigated) continue;
      if(z.top <= 0.0 || z.bottom <= 0.0 || z.top < z.bottom) continue;

      datetime t1 = (z.createTime > 0) ? z.createTime : (tNow - PeriodSeconds(inp_htf_period) * 20);
      string base = "YANSTD_MAP_MSNR_" + IntegerToString(drawn);
      color border = clrSilver;
      color bg = C'28,28,32';
      if(MsnrIsQml(z.msnrType))
        { border = C'186,85,211'; bg = C'40,18,48'; }
      else if(z.msnrType == MSNR_RBS)
        { border = clrDodgerBlue; bg = C'12,28,48'; }
      else if(z.msnrType == MSNR_SBR)
        { border = clrHotPink; bg = C'48,16,32'; }
      else if(z.isKingSNR)
        { border = C'218,165,32'; bg = C'40,32,8'; }
      else if(MsnrIsDemand(z.msnrType))
        { border = C'60,160,90'; bg = C'12,36,22'; }
      else
        { border = C'180,70,70'; bg = C'40,16,16'; }

      if(InpShowMSNRMap)
        {
         UpsertMapRect(base, t1, z.top, tEnd, z.bottom, border, bg, z.isKeyLevel ? 1 : 2,
                       z.isKeyLevel ? STYLE_DOT : STYLE_SOLID);
         string tfTxt = "";
         if(z.isKingSNR && z.kingSourceTF != PERIOD_CURRENT)
            tfTxt = " " + StringSubstr(EnumToString(z.kingSourceTF), 7);
         string lbl = MsnrTypeName(z.msnrType) + tfTxt;
         if(z.isInOTE) lbl += " OTE";
         UpsertMapLabel(base + "_LBL", t1, z.top, lbl, border, 7);

         if(MsnrIsQml(z.msnrType) && z.qmlHeadPrice > 0.0)
           {
            UpsertMapTrend(base + "_HEAD", t1, z.qmlHeadPrice, tEnd, border, STYLE_DASH, 1);
            UpsertMapLabel(base + "_HEAD_LBL", t1, z.qmlHeadPrice,
                           "QML HEAD " + DoubleToString(z.qmlHeadPrice, digits), border, 7);
           }
         if((z.msnrType == MSNR_SBR || z.msnrType == MSNR_RBS) && z.keyLevelPrice > 0.0)
           {
            UpsertMapTrend(base + "_KEY", t1, z.keyLevelPrice, tEnd, border, STYLE_DASHDOT, 1);
            UpsertMapLabel(base + "_KEY_LBL", t1, z.keyLevelPrice,
                           MsnrTypeName(z.msnrType) + " " + DoubleToString(z.keyLevelPrice, digits), border, 7);
           }
        }

      if(InpShowFibLevels && z.fiboSwingHigh > z.fiboSwingLow && z.fiboSwingLow > 0.0 && fibDrawn < 8)
        {
         double rng = z.fiboSwingHigh - z.fiboSwingLow;
         bool demand = MsnrIsDemand(z.msnrType);
         double p618 = demand ? (z.fiboSwingHigh - 0.618 * rng) : (z.fiboSwingLow + 0.618 * rng);
         double p705 = demand ? (z.fiboSwingHigh - 0.705 * rng) : (z.fiboSwingLow + 0.705 * rng);
         double p786 = demand ? (z.fiboSwingHigh - 0.786 * rng) : (z.fiboSwingLow + 0.786 * rng);
         string fb = "YANSTD_MAP_FIB_" + IntegerToString(fibDrawn);
         UpsertMapTrend(fb + "_618", t1, p618, tEnd, clrLime, STYLE_DOT, 1);
         UpsertMapLabel(fb + "_618_LBL", t1, p618, "FIB 0.618", clrLime, 7);
         UpsertMapTrend(fb + "_705", t1, p705, tEnd, clrGold, STYLE_DOT, 1);
         UpsertMapLabel(fb + "_705_LBL", t1, p705, "FIB 0.705", clrGold, 7);
         UpsertMapTrend(fb + "_786", t1, p786, tEnd, clrOrange, STYLE_DOT, 1);
         UpsertMapLabel(fb + "_786_LBL", t1, p786, "FIB 0.786", clrOrange, 7);
         fibDrawn++;
        }
      drawn++;
     }
   ClearStaleMapObjects("YANSTD_MAP_MSNR_", drawn);
   ClearStaleMapObjects("YANSTD_MAP_FIB_", fibDrawn);
  }

void RenderM3RefineVisuals()
  {
   if(!InpShowM3Refine) return;
   int drawn = 0;
   int total = g_signal.GetPOICount();
   datetime tNow = TimeCurrent();
   datetime tEnd = tNow + PeriodSeconds(inp_ltf_period) * 16;
   for(int i = 0; i < total && drawn < 20; i++)
     {
      SMC_Zone poi;
      if(!g_signal.GetPOI(i, poi)) continue;
      if(!poi.isActive || poi.isExpired || poi.isMitigated) continue;
      if(!poi.visHasM3OB && !poi.visHasM3FVG) continue;
      datetime t1 = (poi.createTime > 0) ? poi.createTime : tNow;
      string base = "YANSTD_MAP_M3_" + IntegerToString(drawn);
      if(poi.visHasM3OB && poi.visM3OBTop > poi.visM3OBBottom)
        {
         color c = (poi.type == ZONE_DEMAND) ? clrLime : clrRed;
         UpsertMapRect(base + "_OB", t1, poi.visM3OBTop, tEnd, poi.visM3OBBottom,
                       c, (poi.type == ZONE_DEMAND) ? C'8,40,16' : C'40,8,8', 2, STYLE_SOLID);
         UpsertMapLabel(base + "_OB_LBL", t1, poi.visM3OBTop, "M3 OB", c, 7);
        }
      if(poi.visHasM3FVG && poi.visM3FVGTop > poi.visM3FVGBottom)
        {
         color c = (poi.type == ZONE_DEMAND) ? clrAqua : clrOrange;
         UpsertMapRect(base + "_FVG", t1, poi.visM3FVGTop, tEnd, poi.visM3FVGBottom,
                       c, (poi.type == ZONE_DEMAND) ? C'8,28,36' : C'36,20,8', 1, STYLE_DOT);
         UpsertMapLabel(base + "_FVG_LBL", t1, poi.visM3FVGTop, "M3 FVG", c, 7);
        }
      drawn++;
     }
   ClearStaleMapObjects("YANSTD_MAP_M3_", drawn);
  }

void RenderAllSMCVisuals()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   int totalPOIs = g_signal.GetPOICount();
   int symDigits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   for(int i = 0; i < totalPOIs; i++)
     {
      SMC_Zone poi;
      if(g_signal.GetPOI(i, poi))
        {
         string name    = poi.objName;
         string fvgName = poi.fvgObjName;

         // Cleanup if inactive/mitigated/expired
         if(!poi.isActive || poi.isExpired || poi.isMitigated)
           {
            ObjectDelete(0, name);
            ObjectDelete(0, name + "_LBL");
            ObjectDelete(0, fvgName);
            ObjectDelete(0, fvgName + "_LBL");
            continue;
           }

         datetime t1 = (poi.createTime > 0) ? poi.createTime : (TimeCurrent() - PeriodSeconds(inp_mtf_period) * 10);
         datetime t2 = TimeCurrent() + PeriodSeconds(inp_htf_period) * 8;

         // 1. Render Order Block (OB) Zone Box
         if(InpShowZoneBoxes)
           {
            color obColor = (poi.type == ZONE_DEMAND) ? InpDemandColor : InpSupplyColor;
            color obBg    = (poi.type == ZONE_DEMAND) ? C'15,55,30' : C'60,18,18';
            if(ObjectFind(0, name) < 0)
              {
               ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, poi.top, t2, poi.bottom);
               ApplySMCRectStatic(name, obColor, obBg, 2, STYLE_SOLID, 1);
              }
            else
              {
               ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
               ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, poi.top);
               ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
               ObjectSetDouble(0,  name, OBJPROP_PRICE, 1, poi.bottom);
              }

            string lblName = name + "_LBL";
            if(ObjectFind(0, lblName) < 0)
              {
               ObjectCreate(0, lblName, OBJ_TEXT, 0, t1, poi.top);
               ApplySMCLabelStatic(lblName, obColor, "Arial Bold", 8, 2);
              }
            else
              {
               ObjectSetInteger(0, lblName, OBJPROP_TIME,  0, t1);
               ObjectSetDouble(0,  lblName, OBJPROP_PRICE, 0, poi.top);
              }
            string lbl = (poi.type == ZONE_DEMAND ? "DEMAND OB [M5] #" : "SUPPLY OB [M5] #") + IntegerToString(i);
            if(poi.hasFVG) lbl += " (FVG âœ“)";
            ObjectSetString(0, lblName, OBJPROP_TEXT, lbl);
           }

         // 2. Render Fair Value Gap (FVG Imbalance) Box
         if(InpShowFVGBoxes && poi.hasFVG && poi.fvgTop > 0 && poi.fvgBottom > 0)
           {
            color fvgColor = (poi.type == ZONE_DEMAND) ? InpFVGBullColor : InpFVGBearColor;
            color fvgBg    = (poi.type == ZONE_DEMAND) ? C'10,40,50' : C'50,30,10';
            if(ObjectFind(0, fvgName) < 0)
              {
               ObjectCreate(0, fvgName, OBJ_RECTANGLE, 0, t1, poi.fvgTop, t2, poi.fvgBottom);
               ApplySMCRectStatic(fvgName, fvgColor, fvgBg, 1, STYLE_DOT, 1);
              }
            else
              {
               ObjectSetInteger(0, fvgName, OBJPROP_TIME,  0, t1);
               ObjectSetDouble(0,  fvgName, OBJPROP_PRICE, 0, poi.fvgTop);
               ObjectSetInteger(0, fvgName, OBJPROP_TIME,  1, t2);
               ObjectSetDouble(0,  fvgName, OBJPROP_PRICE, 1, poi.fvgBottom);
              }

            string fvgLblName = fvgName + "_LBL";
            if(ObjectFind(0, fvgLblName) < 0)
              {
               ObjectCreate(0, fvgLblName, OBJ_TEXT, 0, t1, poi.fvgTop);
               ApplySMCLabelStatic(fvgLblName, fvgColor, "Arial", 7, 2);
              }
            else
              {
               ObjectSetInteger(0, fvgLblName, OBJPROP_TIME,  0, t1);
               ObjectSetDouble(0,  fvgLblName, OBJPROP_PRICE, 0, poi.fvgTop);
              }
            string fvgLbl = StringFormat("FVG [M5] %s (CE: %s)",
                                         (poi.type == ZONE_DEMAND ? "BULL" : "BEAR"),
                                         DoubleToString(poi.fvgMidpoint, symDigits));
            ObjectSetString(0, fvgLblName, OBJPROP_TEXT, fvgLbl);
           }
         else
           {
            ObjectDelete(0, fvgName);
            ObjectDelete(0, fvgName + "_LBL");
           }
        }
     }

   // 3. Render Structure Lines (BOS, CHoCH, Equilibrium)
   if(InpShowStructureLines)
     {
      double swH = g_signal.GetM15SwingHigh();
      double swL = g_signal.GetM15SwingLow();
      double eq  = g_signal.GetM15Equilibrium();
      datetime tStart = TimeCurrent() - PeriodSeconds(inp_htf_period) * 30;
      datetime tEnd   = TimeCurrent() + PeriodSeconds(inp_htf_period) * 8;

      // Confirmed swing levels are liquidity references. They become BOS/CHoCH
      // only after an actual structure event closes through the proper level.
      if(swH > 0)
        {
         string hLine = "YANSTD_M15_SWING_H";
         if(ObjectFind(0, hLine) < 0)
           {
            ObjectCreate(0, hLine, OBJ_TREND, 0, tStart, swH, tEnd, swH);
            ApplySMCTrendStatic(hLine, InpBOSColor, STYLE_DASH, 1, true);
           }
         else
           {
            ObjectSetInteger(0, hLine, OBJPROP_TIME, 0, tStart); ObjectSetDouble(0, hLine, OBJPROP_PRICE, 0, swH);
            ObjectSetInteger(0, hLine, OBJPROP_TIME, 1, tEnd);   ObjectSetDouble(0, hLine, OBJPROP_PRICE, 1, swH);
           }

         string hLbl = hLine + "_LBL";
         if(ObjectFind(0, hLbl) < 0)
           {
            ObjectCreate(0, hLbl, OBJ_TEXT, 0, tStart, swH);
            ApplySMCLabelStatic(hLbl, InpBOSColor, "Arial Bold", 8, 2);
            ObjectSetString(0, hLbl, OBJPROP_TEXT, "  M15 SWING HIGH / LIQUIDITY");
           }
         else
           {
            ObjectSetInteger(0, hLbl, OBJPROP_TIME, 0, tStart); ObjectSetDouble(0, hLbl, OBJPROP_PRICE, 0, swH);
           }
        }

      // M15 confirmed swing low / sell-side liquidity reference
      if(swL > 0)
        {
         string lLine = "YANSTD_M15_SWING_L";
         if(ObjectFind(0, lLine) < 0)
           {
            ObjectCreate(0, lLine, OBJ_TREND, 0, tStart, swL, tEnd, swL);
            ApplySMCTrendStatic(lLine, InpBOSColor, STYLE_DASH, 1, true);
           }
         else
           {
            ObjectSetInteger(0, lLine, OBJPROP_TIME, 0, tStart); ObjectSetDouble(0, lLine, OBJPROP_PRICE, 0, swL);
            ObjectSetInteger(0, lLine, OBJPROP_TIME, 1, tEnd);   ObjectSetDouble(0, lLine, OBJPROP_PRICE, 1, swL);
           }

         string lLbl = lLine + "_LBL";
         if(ObjectFind(0, lLbl) < 0)
           {
            ObjectCreate(0, lLbl, OBJ_TEXT, 0, tStart, swL);
            ApplySMCLabelStatic(lLbl, InpBOSColor, "Arial Bold", 8, 2);
            ObjectSetString(0, lLbl, OBJPROP_TEXT, "  M15 SWING LOW / LIQUIDITY");
           }
         else
           {
            ObjectSetInteger(0, lLbl, OBJPROP_TIME, 0, tStart); ObjectSetDouble(0, lLbl, OBJPROP_PRICE, 0, swL);
           }
        }

      SMC_SwingPoint m15H, m15PH, m15L, m15PL;
      if(g_signal.GetM15StructureSwings(m15H, m15PH, m15L, m15PL))
         RenderSwingPairLabels("YANSTD_STR_M15_", m15H, m15PH, m15L, m15PL);
      g_signal.RefreshLTFStructureCache();
      SMC_SwingPoint m3H, m3PH, m3L, m3PL;
      if(g_signal.GetM3StructureSwings(m3H, m3PH, m3L, m3PL))
         RenderSwingPairLabels("YANSTD_STR_M3_", m3H, m3PH, m3L, m3PL);

      // Bounded history of real structure events: several recent M15 macro and
      // M3 entry events. Expired events are dropped by the engine TTL filter;
      // ClearStaleMapObjects removes index slots no longer in use.
      ObjectDelete(0, "YANSTD_M15_STRUCTURE_EVENT");
      ObjectDelete(0, "YANSTD_M15_STRUCTURE_EVENT_LBL");
      datetime tM3End = TimeCurrent() + PeriodSeconds(inp_ltf_period) * 16;
      SStructureEvent m15Evts[], m3Evts[];
      int m15Count = g_signal.GetM15StructureEvents(m15Evts);
      int m3Count  = g_signal.GetM3StructureEvents(m3Evts);
      RenderStructureEventHistory(m15Evts, m15Count, "YANSTD_M15_STRUCT_", "M15", tEnd);
      RenderStructureEventHistory(m3Evts,  m3Count,  "YANSTD_M3_STRUCT_",  "M3",  tM3End);

      // M15 Equilibrium (50% Premium / Discount)
      if(eq > 0)
        {
         string eqLine = "YANSTD_M15_EQ";
         if(ObjectFind(0, eqLine) < 0)
           {
            ObjectCreate(0, eqLine, OBJ_TREND, 0, tStart, eq, tEnd, eq);
            ApplySMCTrendStatic(eqLine, InpEQColor, STYLE_DOT, 1, true);
           }
         else
           {
            ObjectSetInteger(0, eqLine, OBJPROP_TIME, 0, tStart); ObjectSetDouble(0, eqLine, OBJPROP_PRICE, 0, eq);
            ObjectSetInteger(0, eqLine, OBJPROP_TIME, 1, tEnd);   ObjectSetDouble(0, eqLine, OBJPROP_PRICE, 1, eq);
           }

         string eqLbl = eqLine + "_LBL";
         if(ObjectFind(0, eqLbl) < 0)
           {
            ObjectCreate(0, eqLbl, OBJ_TEXT, 0, tStart, eq);
            ApplySMCLabelStatic(eqLbl, InpEQColor, "Arial", 7, 2);
            ObjectSetString(0, eqLbl, OBJPROP_TEXT, "  M15 50% EQUILIBRIUM (EQ)");
           }
         else
           {
            ObjectSetInteger(0, eqLbl, OBJPROP_TIME, 0, tStart); ObjectSetDouble(0, eqLbl, OBJPROP_PRICE, 0, eq);
           }
        }
     }
   else
     {
      // Toggle OFF must clear every structure layer, not just the event lines.
      ObjectsDeleteAll(0, "YANSTD_M15_STRUCT_");
      ObjectsDeleteAll(0, "YANSTD_M3_STRUCT_");
      ObjectsDeleteAll(0, "YANSTD_M15_STRUCTURE_EVENT");
      ObjectsDeleteAll(0, "YANSTD_STR_M15_");
      ObjectsDeleteAll(0, "YANSTD_STR_M3_");
      ObjectsDeleteAll(0, "YANSTD_M15_SWING_");
      ObjectsDeleteAll(0, "YANSTD_M15_EQ");
     }

   RenderMSNRMapVisuals();
   RenderM3RefineVisuals();
  }
//|  EXECUTION & ORDER HANDLING                                      |
//+------------------------------------------------------------------+
double CalculatePlannedRiskMoney(ENUM_ORDER_TYPE orderType, double lots,
                                 double entryPrice, double slPrice)
  {
   if(lots <= 0.0 || entryPrice <= 0.0 || slPrice <= 0.0) return DBL_MAX;
   double profitAtSL = 0.0;
   if(OrderCalcProfit(orderType, Symbol(), lots, entryPrice, slPrice, profitAtSL))
      return MathMax(0.0, -profitAtSL);

   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0) tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return DBL_MAX;
   return MathAbs(entryPrice - slPrice) / tickSize * tickValue * lots;
  }

double GetTotalOpenRiskMoney()
  {
   double totalRisk = 0.0;
   for(int p = 0; p < PositionsTotal(); p++)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket <= 0 || PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
        {
         static datetime s_lastNoSLWarn = 0;
         datetime nw = TimeCurrent();
         if(s_lastNoSLWarn == 0 || nw - s_lastNoSLWarn >= 300)
           {
            LogSystemWarning("YANSTD", "GetTotalOpenRiskMoney",
               StringFormat("Open position #%I64u has NO stop-loss; aggregate-risk cap treats total risk as unbounded and is BLOCKING all new entries until it is protected.", ticket));
            s_lastNoSLWarn = nw;
           }
         return DBL_MAX;
        }
      ENUM_ORDER_TYPE type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                             ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double risk = CalculatePlannedRiskMoney(type, PositionGetDouble(POSITION_VOLUME),
                                              PositionGetDouble(POSITION_PRICE_OPEN), sl);
      if(risk == DBL_MAX) return DBL_MAX;
      totalRisk += risk;
     }

   for(int o = 0; o < OrdersTotal(); o++)
     {
      ulong ticket = OrderGetTicket(o);
      if(ticket <= 0 || OrderGetInteger(ORDER_MAGIC) != (long)InpMagicNumber ||
         OrderGetString(ORDER_SYMBOL) != Symbol()) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT &&
         type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP) continue;
      ENUM_ORDER_TYPE calcType = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
                                 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double risk = CalculatePlannedRiskMoney(calcType, OrderGetDouble(ORDER_VOLUME_CURRENT),
                                              OrderGetDouble(ORDER_PRICE_OPEN),
                                              OrderGetDouble(ORDER_SL));
      if(risk == DBL_MAX) return DBL_MAX;
      totalRisk += risk;
     }
   return totalRisk;
  }

bool CanAddAggregateRisk(ENUM_ORDER_TYPE orderType, double lots, double entryPrice,
                         double slPrice, double &projectedRiskPct)
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentMoney = GetTotalOpenRiskMoney();
   projectedRiskPct = (equity > 0.0 && currentMoney != DBL_MAX)
                      ? currentMoney / equity * 100.0 : 100.0;
   if(InpMaxAggregateRiskPct <= 0.0) return true;
   double newMoney = CalculatePlannedRiskMoney(orderType, lots, entryPrice, slPrice);
   if(equity <= 0.0 || currentMoney == DBL_MAX || newMoney == DBL_MAX)
     {
      projectedRiskPct = 100.0;
      return false;
     }
   projectedRiskPct = (currentMoney + newMoney) / equity * 100.0;
   return projectedRiskPct <= InpMaxAggregateRiskPct + 1e-8;
  }

void ManageNewsLivePositions(ENUM_NEWS_STATUS status)
  {
   static bool actedThisWindow = false;
   static datetime lastAttempt = 0;
   if(status != NEWS_LIVE)
     {
      actedThisWindow = false;
      lastAttempt = 0;
      return;
     }
   if(actedThisWindow || InpNewsLivePositionAction == NEWS_POSITION_HOLD) return;
   if(lastAttempt > 0 && TimeCurrent() - lastAttempt < 2) return;
   lastAttempt = TimeCurrent();

   if(InpNewsLivePositionAction == NEWS_POSITION_CLOSE_ALL)
     {
      bool closed = g_orders.CloseAllByMagic();
      actedThisWindow = closed;
      Print("[YANSTD NEWS PROTECTION] NEWS_LIVE CLOSE_ALL | Result=", closed ? "OK" : "RETRY/ERROR");
      return;
     }

   bool allHandled = true;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket <= 0 || PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if(g_orders.IsTrackTP1Done(ticket)) continue; // already protected in this/normal TP1 flow
      double volume = PositionGetDouble(POSITION_VOLUME);
      double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
      double closeLots = (step > 0.0)
                         ? MathFloor((volume * InpNewsLivePartialPct / 100.0 + 1e-12) / step) * step
                         : 0.0;
      if(closeLots >= minLot && volume - closeLots >= minLot)
        {
         bool closed = g_orders.PartialClose(ticket, closeLots);
         if(closed) g_orders.MarkProtectivePartial(ticket);
         else allHandled = false;
         Print("[YANSTD NEWS PROTECTION] NEWS_LIVE PARTIAL | Ticket=", ticket,
               " | Lots=", DoubleToString(closeLots, 2), " | Result=", closed ? "OK" : "ERROR");
        }
      else
         Print("[YANSTD NEWS PROTECTION] Partial skipped: broker minimum/step would leave invalid remainder | Ticket=", ticket);
     }
   actedThisWindow = allHandled;
  }

void TryAutoEntry()
  {
   // 1. Anti-Double Tick Debounce: Minimum 5 seconds between ANY order executions
   if(TimeCurrent() - g_lastEntryTime < 5) return;

   int currentOpen = g_orders.CountOpenPositions();
   long diagKey = (long)iTime(Symbol(), inp_ltf_period, 0);
   int maxPendingNow = g_multiLayerAllowed ? MathMax(1, g_effectiveMaxPositions - currentOpen) : 1;
   if(g_orders.CountPendingOrders() >= maxPendingNow)
     { g_diagnostics.Record(REJECT_PENDING_LIMIT, diagKey); return; }
   if(currentOpen >= g_effectiveMaxPositions)
     { g_diagnostics.Record(REJECT_POSITION_LIMIT, diagKey); return; }

   double effRisk = g_effectiveCollectionMode ? InpCollectionRiskPct
                                           : (g_multiLayerAllowed ? (InpRiskPercent / MathMax(1, g_effectiveMaxPositions)) : g_riskDisplay);

   bool useRiskSizing = g_effectiveCollectionMode || (InpFixedLot <= 0);
    if(!ShouldRunGenerateSignal()) return;
    MarkGenerateSignalRan();
    // GenerateSignal is the M3 structural trigger here. Final live approval
    // must be performed per candidate below, otherwise a rejected midpoint
    // could hide another OB/FVG/Fibo level with superior Brain statistics.
    g_signal.SetBrainExplorationMode(true);
    SSignal sig = g_signal.GenerateSignal(effRisk, useRiskSizing, g_lotDisplay);
    NoteLotStatus(g_risk.LastLotStatus());
     g_signal.SetBrainExplorationMode(g_effectiveCollectionMode || IsHistoricalMatrixTest());
    if(!sig.isValid)
      {
       TryAutoLimitFallback();
       return;
      }
    // Gen-6C M1: same-direction re-entry cooldown, covering every entry path.
    if(SameDirectionReentryBlocked(sig.direction == SIGNAL_BUY ? ORDER_TYPE_BUY_LIMIT
                                                              : ORDER_TYPE_SELL_LIMIT))
      {
       g_diagnostics.Record(REJECT_REENTRY_COOLDOWN, diagKey);
       return;
      }

    sig.setupEventId = BuildSetupEventId(sig);

    // Live/forward and matrix now consume the exact same confirmed M3 object.
    // ManageAutoLimitOrders evaluates every available candidate once and live
    // places only the single highest-scoring one.
    g_matrixTriggerContext = sig;
    g_hasMatrixTriggerContext = true;
    ManageAutoLimitOrders(-1, sig.zoneIndex, "CONFIRMED");
    g_hasMatrixTriggerContext = false;
    return;
   }

void TryAutoLimitFallback()
  {
   if(!InpScanAllPOIsWhenNoTrigger) return;
   if(TimeCurrent() - g_lastEntryTime < 5) return;

   int currentOpen = g_orders.CountOpenPositions();
   long diagKey = (long)iTime(Symbol(), inp_ltf_period, 0);
   int maxPendingNow = g_multiLayerAllowed ? MathMax(1, g_effectiveMaxPositions - currentOpen) : 1;
   if(g_orders.CountPendingOrders() >= maxPendingNow)
     { g_diagnostics.Record(REJECT_PENDING_LIMIT, diagKey); return; }
   if(currentOpen >= g_effectiveMaxPositions)
     { g_diagnostics.Record(REJECT_POSITION_LIMIT, diagKey); return; }

   // ManageAutoLimitOrders resolves its own risk budget; the candidate scan here
   // is purely structural. With no M3 refinement context it falls back to the
   // parent M15/M5 zone geometry (its documented behaviour when
   // g_hasMatrixTriggerContext is false).
   g_hasMatrixTriggerContext = false;
   ManageAutoLimitOrders(-1, -1, "FALLBACK");
  }

double ResizeLotForMarketFill(const SSignal &sig, ENUM_ORDER_TYPE type, double &fillRef)
  {
   fillRef = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                                      : SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(InpFixedLot > 0.0) return sig.lotSize;   // fixed-lot mode: nothing to re-size
   double pip      = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
   double riskDist = MathAbs(fillRef - sig.slPrice);
   if(fillRef <= 0.0 || pip <= 0.0 || riskDist <= 0.0) return sig.lotSize;
   double lots = g_risk.CalcLotSize(sig.riskPct, riskDist / pip, Symbol(), fillRef, type);
   NoteLotStatus(g_risk.LastLotStatus());
   return lots;
  }

void ExecuteBuy(const SSignal &sig)
  {
   g_lastEntryTime = TimeCurrent();
   NoteEntryDirection(ORDER_TYPE_BUY);
   ulong eventId = (sig.setupEventId > 0) ? sig.setupEventId : BuildSetupEventId(sig);
   string comm = FormatEntryComment(sig.brainBucketIdx, (int)sig.entryType,
                                    (int)sig.setupGrade, eventId);
   double fillRef = 0.0;
   double lots = EnforceBrokerMinLot(ResizeLotForMarketFill(sig, ORDER_TYPE_BUY, fillRef), Symbol());
   if(lots <= 0.0)
      lots = EnforceBrokerMinLot(sig.lotSize, Symbol());
   if(lots <= 0.0)
     {
      Print("YANSTD SMC: BUY skipped â€” lot could not be normalized to broker minimum");
      g_diagnostics.Record(REJECT_LOT_TOO_SMALL, (long)TimeCurrent());
      return;
     }
   // Gen-7 fix: the automatic market path (MSNR_PRIMARY) never consulted the
   // aggregate risk cap — only the manual guard and the limit path did. Without
   // this, a market fill could open a position far past InpMaxAggregateRiskPct.
   double projectedMktRisk = 0.0;
   if(!CanAddAggregateRisk(ORDER_TYPE_BUY, lots, fillRef, sig.slPrice, projectedMktRisk))
     {
      g_diagnostics.Record(REJECT_AGGREGATE_RISK, (long)TimeCurrent());
      LogThrottled("RISK_GUARD", 5,
                   StringFormat("Market BUY rejected | Projected aggregate risk=%s%% > cap %s%% | lot=%s",
                                DoubleToString(projectedMktRisk, 2),
                                DoubleToString(InpMaxAggregateRiskPct, 2),
                                DoubleToString(lots, 2)));
      return;
     }
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double pipExec = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
   double serverTP = 0.0, tp1Px = sig.tp1Price, tp2Px = sig.tp2Price, tp1Pct = InpTP1ClosePct, tp2Pct = 0.0;
   double emergencyTP = 0.0;
   if(IsStructuralExitMode())
     {
      PlanStructuralTP(fillRef, true, ZONE_DEMAND, pipExec, digits,
                       serverTP, tp1Px, tp2Px, tp1Pct, tp2Pct,
                       MathAbs(fillRef - sig.slPrice));
      double minLot = EffectiveBrokerMinLot(Symbol());
      double half   = g_risk.RoundLotToStep(lots * 0.5);
      if(tp1Pct > 0.0 && (half < minLot || (lots - half) < minLot))
        { tp1Px = 0.0; tp1Pct = 0.0; }
      emergencyTP = serverTP;
     }
   else
     {
      double serverTPRR = (InpExitMode == EXIT_FIXED_RR) ? InpFixedRR : InpEmergencyServerTPRR;
      emergencyTP = (serverTPRR > 0.0)
                    ? NormalizeDouble(fillRef + MathAbs(fillRef - sig.slPrice) * serverTPRR, digits) : 0.0;
     }
   if(g_orders.OpenBuy(lots, sig.slPrice, emergencyTP, comm))
     {
      g_signal.SetPOILayerTriggered(sig.zoneIndex, sig.entryType, g_effectiveMaxPositions);
      g_posInfo.ticket         = 0; // Will be matched by ticket in GetPosition
      g_posInfo.entryType      = sig.entryType;
      g_posInfo.tp1Level       = tp1Px;
      g_posInfo.tp2Level       = 0.0;
      g_posInfo.tp1Done        = false;
      g_posInfo.tp2Done        = false;
      g_posInfo.tp2Time        = 0;
      g_posInfo.bepDone        = false;
      g_posInfo.milestoneDone  = false; // A new BUY has not reached its milestone
      g_posInfo.trailActive    = false;
      g_posInfo.brainBucketIdx = sig.brainBucketIdx;
      g_stats.totalTrades++;

      // Register new position ticket with exact TP1 price
      for(int p = 0; p < PositionsTotal(); p++)
        {
         ulong ticket = PositionGetTicket(p);
         if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == Symbol() &&
            PositionGetString(POSITION_COMMENT) == comm && !g_orders.IsTracked(ticket))
           {
              g_orders.RegisterNewTrack(ticket, tp1Px, 0.0, sig.brainBucketIdx,
                                        IsStructuralExitMode() ? tp1Pct :
                                        (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP1ClosePct),
                                        IsStructuralExitMode() ? 0.0 :
                                        (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP2ClosePct),
                                        eventId, 1.0, emergencyTP,
                                        IsStructuralExitMode() ? g_lastPlanTargetSource : TARGET_NONE);
              g_orders.SetTrackAttribution(ticket, (int)sig.entryType, (int)sig.setupGrade);
              g_orders.RecalcTrackFromFill(ticket, fillRef, sig.slPrice);
           }
        }

      string setupStr = g_signal.GetSetupTypeString(sig.entryType);
      Print("YANSTD SMC: BUY Executed [", setupStr, "] | Lot:", lots, " SL:", sig.slPrice,
            " TP:", emergencyTP, " partial@:", tp1Px,
            " | TARGET_SOURCE=", TargetSourceLabel(g_lastPlanTargetSource),
            " | Conf:", DoubleToString(sig.aiConfidence, 1), "%");
     }
   else if(!g_orders.LastRejectWasEntryStopsTooClose())
      g_diagnostics.Record(REJECT_ORDER_SEND, (long)TimeCurrent());
  }

void ExecuteSell(const SSignal &sig)
  {
   g_lastEntryTime = TimeCurrent();
   NoteEntryDirection(ORDER_TYPE_SELL);
   ulong eventId = (sig.setupEventId > 0) ? sig.setupEventId : BuildSetupEventId(sig);
   string comm = FormatEntryComment(sig.brainBucketIdx, (int)sig.entryType,
                                    (int)sig.setupGrade, eventId);
   double fillRef = 0.0;
   double lots = EnforceBrokerMinLot(ResizeLotForMarketFill(sig, ORDER_TYPE_SELL, fillRef), Symbol());
   if(lots <= 0.0)
      lots = EnforceBrokerMinLot(sig.lotSize, Symbol());
   if(lots <= 0.0)
     {
      Print("YANSTD SMC: SELL skipped â€” lot could not be normalized to broker minimum");
      g_diagnostics.Record(REJECT_LOT_TOO_SMALL, (long)TimeCurrent());
      return;
     }
   // Gen-7 fix: same aggregate-risk guard as ExecuteBuy — the automatic market
   // path must respect InpMaxAggregateRiskPct, not just the limit path.
   double projectedMktRisk = 0.0;
   if(!CanAddAggregateRisk(ORDER_TYPE_SELL, lots, fillRef, sig.slPrice, projectedMktRisk))
     {
      g_diagnostics.Record(REJECT_AGGREGATE_RISK, (long)TimeCurrent());
      LogThrottled("RISK_GUARD", 5,
                   StringFormat("Market SELL rejected | Projected aggregate risk=%s%% > cap %s%% | lot=%s",
                                DoubleToString(projectedMktRisk, 2),
                                DoubleToString(InpMaxAggregateRiskPct, 2),
                                DoubleToString(lots, 2)));
      return;
     }
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double pipExec = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
   double serverTP = 0.0, tp1Px = sig.tp1Price, tp2Px = 0.0, tp1Pct = InpTP1ClosePct, tp2Pct = 0.0;
   double emergencyTP = 0.0;
   if(IsStructuralExitMode())
     {
      PlanStructuralTP(fillRef, false, ZONE_SUPPLY, pipExec, digits,
                       serverTP, tp1Px, tp2Px, tp1Pct, tp2Pct,
                       MathAbs(sig.slPrice - fillRef));
      double minLot = EffectiveBrokerMinLot(Symbol());
      double half   = g_risk.RoundLotToStep(lots * 0.5);
      if(tp1Pct > 0.0 && (half < minLot || (lots - half) < minLot))
        { tp1Px = 0.0; tp1Pct = 0.0; }
      emergencyTP = serverTP;
     }
   else
     {
      double serverTPRR = (InpExitMode == EXIT_FIXED_RR) ? InpFixedRR : InpEmergencyServerTPRR;
      emergencyTP = (serverTPRR > 0.0)
                    ? NormalizeDouble(fillRef - MathAbs(sig.slPrice - fillRef) * serverTPRR, digits) : 0.0;
     }
   if(g_orders.OpenSell(lots, sig.slPrice, emergencyTP, comm))
     {
      g_signal.SetPOILayerTriggered(sig.zoneIndex, sig.entryType, g_effectiveMaxPositions);
      g_posInfo.ticket         = 0; // Will be matched by ticket in GetPosition
      g_posInfo.entryType      = sig.entryType;
      g_posInfo.tp1Level       = tp1Px;
      g_posInfo.tp2Level       = 0.0;
      g_posInfo.tp1Done        = false;
      g_posInfo.tp2Done        = false;
      g_posInfo.tp2Time        = 0;
      g_posInfo.bepDone        = false;
      g_posInfo.milestoneDone  = false;
      g_posInfo.trailActive    = false;
      g_posInfo.brainBucketIdx = sig.brainBucketIdx;
      g_stats.totalTrades++;

      for(int p = 0; p < PositionsTotal(); p++)
        {
         ulong ticket = PositionGetTicket(p);
         if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == Symbol() &&
            PositionGetString(POSITION_COMMENT) == comm && !g_orders.IsTracked(ticket))
           {
              g_orders.RegisterNewTrack(ticket, tp1Px, 0.0, sig.brainBucketIdx,
                                        IsStructuralExitMode() ? tp1Pct :
                                        (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP1ClosePct),
                                        IsStructuralExitMode() ? 0.0 :
                                        (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP2ClosePct),
                                        eventId, 1.0, emergencyTP,
                                        IsStructuralExitMode() ? g_lastPlanTargetSource : TARGET_NONE);
              g_orders.SetTrackAttribution(ticket, (int)sig.entryType, (int)sig.setupGrade);
              g_orders.RecalcTrackFromFill(ticket, fillRef, sig.slPrice);
           }
        }

      string setupStr = g_signal.GetSetupTypeString(sig.entryType);
      Print("YANSTD SMC: SELL Executed [", setupStr, "] | Lot:", lots, " SL:", sig.slPrice,
            " TP:", emergencyTP, " partial@:", tp1Px,
            " | TARGET_SOURCE=", TargetSourceLabel(g_lastPlanTargetSource),
            " | Conf:", DoubleToString(sig.aiConfidence, 1), "%");
     }
   else if(!g_orders.LastRejectWasEntryStopsTooClose())
      g_diagnostics.Record(REJECT_ORDER_SEND, (long)TimeCurrent());
  }

void ReconcilePOIPendingFlags()
  {
   g_signal.ClearAllPOIPendingLimits();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != Symbol()) continue;
      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      ENUM_ZONE_TYPE zoneType;
      if(orderType == ORDER_TYPE_BUY_LIMIT) zoneType = ZONE_DEMAND;
      else if(orderType == ORDER_TYPE_SELL_LIMIT) zoneType = ZONE_SUPPLY;
      else continue;
       string orderComment = OrderGetString(ORDER_COMMENT);
       int bucketFromComment = -1, setupValue = -1, gradeFromComment = -1;
       ulong eventValue = 0;
       ParseEntryComment(orderComment, bucketFromComment, setupValue, gradeFromComment, eventValue);
       bool matched = false;
       double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
       if(setupValue >= 0 && setupValue < ENTRY_VARIANT_COUNT)
         {
          if(eventValue > 0)
             matched = g_signal.SetMatchingPOIPendingEvent(zoneType, eventValue,
                                                           (ENUM_SMC_ENTRY_TYPE)setupValue, true);
          if(!matched)
             matched = g_signal.SetMatchingPOIPendingLayer(zoneType, orderPrice,
                                                           (ENUM_SMC_ENTRY_TYPE)setupValue, true);
         }
       // Last resort: price-only match against any active POI of that side.
       if(!matched)
          matched = g_signal.SetMatchingPOIPendingLimit(zoneType, orderPrice, true);
       if(!matched)
        {
         // GTC is safe only while its originating POI remains valid.
         Print("[YANSTD RECONCILE] Deleting pending #", ticket,
               " â€” no active POI matches its price/setup after reconciliation");
         g_orders.DeletePendingTicket(ticket);
        }
     }

  }

bool HasEquivalentPendingOrder(ENUM_ORDER_TYPE orderType, ENUM_SMC_ENTRY_TYPE setupType, double orderPrice)
  {
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tolerance = MathMax(point, tickSize) + 1e-12;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != Symbol()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != orderType) continue;

      string comment = OrderGetString(ORDER_COMMENT);
      int bucketFromComment = -1, storedType = -1, gradeFromComment = -1;
      ulong eventFromComment = 0;
      ParseEntryComment(comment, bucketFromComment, storedType, gradeFromComment, eventFromComment);
      if(storedType >= 0 && storedType != (int)setupType) continue;
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - orderPrice) <= tolerance) return true;
     }
   return false;
  }

// H2: sibling pending orders from the same structural signal are correlated,
// even when they use different mitigation labels. Do not fan out several nearly
// identical prices and pretend they are independent risk decisions.
bool HasCorrelatedPendingOrder(ENUM_ORDER_TYPE orderType, double orderPrice, double minDistance)
  {
   if(minDistance <= 0.0) return false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != Symbol()) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != orderType) continue;
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - orderPrice) < minDistance) return true;
     }
   return false;
  }

bool ManageAutoLimitOrders(int requestedVariant, int requiredPoiIndex, string entryPath)
  {
   static datetime lastCheckTime = 0;
   bool historicalMatrixTest = IsHistoricalMatrixTest();
   bool explorationMode = historicalMatrixTest || g_effectiveCollectionMode;
   if(!historicalMatrixTest)
     {
      if(TimeCurrent() - lastCheckTime < 5) return false;
      lastCheckTime = TimeCurrent();
     }


   ENUM_SIGNAL_TYPE htfBias = g_signal.GetHTFBias();

   // 1. Invalidate & Delete Pending Orders of Opposite Bias
   if(!InpAllowCounterBias && htfBias == SIGNAL_BUY)
      g_orders.DeletePendingByType(ORDER_TYPE_SELL_LIMIT);
   else if(!InpAllowCounterBias && htfBias == SIGNAL_SELL)
      g_orders.DeletePendingByType(ORDER_TYPE_BUY_LIMIT);

   int openCount    = g_orders.CountOpenPositions();
   int pendingCount = g_orders.CountPendingOrders();

   if(!historicalMatrixTest || requestedVariant <= 0)
      ReconcilePOIPendingFlags();
   pendingCount = g_orders.CountPendingOrders();

   int maxPending = historicalMatrixTest ? MATRIX_MAX_CANDIDATE_COUNT
                    : (g_effectiveCollectionMode ? MathMax(1, InpCollectionMaxPending)
                                                  : (g_multiLayerAllowed ? MathMax(1, g_effectiveMaxPositions - openCount) : 1));
   long globalDiagKey = (long)iTime(Symbol(), inp_ltf_period, 0);
   g_diagnostics.MarkEvaluation(globalDiagKey);
   if(pendingCount >= maxPending) { g_diagnostics.Record(REJECT_PENDING_LIMIT, globalDiagKey); return false; }
   if(openCount + pendingCount >= g_effectiveMaxPositions || openCount >= g_effectiveMaxPositions)
     { g_diagnostics.Record(REJECT_POSITION_LIMIT, globalDiagKey); return false; }

   double pip   = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   int    symDigits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   long   spreadRaw  = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   double stopsLvl   = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * point;
   double freezeLvl  = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_FREEZE_LEVEL) * point;
   double spreadPts  = (double)spreadRaw * point;
   double curAsk     = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double curBid     = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spreadPrice = MathMax(0.0, curAsk - curBid);
   if((int)spreadRaw > g_effectiveMaxSpreadPts)
     { g_diagnostics.Record(REJECT_SPREAD, globalDiagKey); return false; }
   double minLimitDist = MathMax(2.5 * pip, MathMax(stopsLvl, freezeLvl) + spreadPts + 2.0 * point);
   double cachedEntryATR = ReadIndicatorValue(g_atrM5Handle, 0, 1);
   double cachedSLBuffer = InpUseDynamicSLBuffer
                           ? g_signal.GetDynamicSLBuffer(inp_sl_buffer_pips, InpSLATRMult)
                           : (inp_sl_buffer_pips * pip);

   int totalPOIs = g_signal.GetPOICount();

   // Evaluate all POIs and select the SINGLE BEST candidate across all zones
   int                 bestPoiIdx       = -1;
   double              bestLimitPrice   = 0.0;
   double              bestSLPrice      = 0.0;
   double              bestSLPips       = 0.0;
   double              bestConfScore    = -1.0;
   int                 bestBucketIdx    = -1;
   ENUM_SMC_ENTRY_TYPE bestSetupType    = ENTRY_TYPE_FIB_705;
   ENUM_ZONE_TYPE      bestZoneType     = ZONE_DEMAND;
   int                 bestPrimaryZone  = -1;
   bool                bestM3Confirmed  = false;
   bool                bestKingAgainst  = false;
   bool                bestPoiInOTE     = false;
   bool                bestPoiRetested  = false;
   ENUM_OB_COLOR       bestParentOBColor    = OB_COLOR_UNKNOWN;
   ENUM_OB_COLOR       bestExecutionOBColor = OB_COLOR_UNKNOWN;

   ENUM_SESSION_TYPE sess = g_session.GetCurrentSession();

   double swHigh  = g_signal.GetM15SwingHigh();
   double swLow   = g_signal.GetM15SwingLow();

   bool timeAllowedPre = !InpUseTimeFilter || (explorationMode && InpCollectionAllSessions) ||
                          TimeFilterAllowsEntry();
   if(!timeAllowedPre)
     {
      g_diagnostics.Record(REJECT_TIME_FILTER, globalDiagKey);
      return false;
     }
   if(GapPauseBlocksEntry() && !(explorationMode && InpCollectionAllSessions))
     {
      g_diagnostics.Record(REJECT_GAP_PAUSE, globalDiagKey);
      return false;
     }
   // M2: Sunday re-open is handled in the same simulated-UTC domain as the
   // Friday close. This prevents a server-time/UTC mismatch from exposing
   // fresh limits into the XAU weekend gap.
   if(InpBlockSundayOpen && InpSundayOpenBlockHours > 0)
     {
      MqlDateTime utcNow;
      TimeToStruct(g_session.GetSimulatedUTC(), utcNow);
      if(utcNow.day_of_week == 0 && utcNow.hour < InpSundayOpenBlockHours)
        {
         g_diagnostics.Record(REJECT_SUNDAY_OPEN, globalDiagKey);
         return false;
        }
     }

   int poiStart = (requiredPoiIndex >= 0) ? requiredPoiIndex : 0;
   int poiEnd   = (requiredPoiIndex >= 0) ? MathMin(totalPOIs, requiredPoiIndex + 1) : totalPOIs;
   for(int i = poiStart; i < poiEnd; i++)
     {
      SMC_Zone poi;
      if(!g_signal.GetPOI(i, poi)) continue;
      if(!poi.isActive || poi.isExpired || poi.isMitigated) continue;
      if(!historicalMatrixTest && !g_effectiveCollectionMode && poi.hasPendingLimit) continue;
      int primaryZone = poi.primaryMSNRZoneIdx;
      bool useM3RefinementContext = (g_hasMatrixTriggerContext &&
                                 g_matrixTriggerContext.isValid &&
                                 g_matrixTriggerContext.zoneIndex == i);
      // M0 (Hybrid): M3 confirmation is a SOFT bonus, never a hard reject.
      // A fallback POI stays a candidate; a confirmed M3 context simply scores
      // higher (see M3_CONFIRMED_SOFT_BONUS in the scoring block below).
      const bool m3ConfirmedContext = useM3RefinementContext;
      bool hasRefinedOB = (useM3RefinementContext &&
                           g_matrixTriggerContext.refinedOBTop > g_matrixTriggerContext.refinedOBBottom);
      bool hasRefinedFVG = (useM3RefinementContext &&
                            g_matrixTriggerContext.refinedFVGTop > g_matrixTriggerContext.refinedFVGBottom);
      // Keep the parent M15/MSNR POI intact.  OB, FVG and Fibonacci variants
      // each receive their own geometry below; collapsing the parent POI to the
      // tiny M3 OB previously made valid Fib candidates fail the proximity gate.
      double obTop = hasRefinedOB ? g_matrixTriggerContext.refinedOBTop : poi.top;
      double obBottom = hasRefinedOB ? g_matrixTriggerContext.refinedOBBottom : poi.bottom;
      double fvgTop = hasRefinedFVG ? g_matrixTriggerContext.refinedFVGTop : poi.fvgTop;
      double fvgBottom = hasRefinedFVG ? g_matrixTriggerContext.refinedFVGBottom : poi.fvgBottom;
      if(useM3RefinementContext)
        {
         poi.fiboSwingHigh = g_matrixTriggerContext.fiboSwingHigh;
         poi.fiboSwingLow = g_matrixTriggerContext.fiboSwingLow;
        }
      bool counterTrend = false;
      ENUM_SIGNAL_TYPE poiDirection = (poi.type == ZONE_DEMAND) ? SIGNAL_BUY : SIGNAL_SELL;
      if(!g_signal.IsDirectionAllowed(poiDirection, counterTrend))
        {
         g_diagnostics.Record(REJECT_DIRECTION_BIAS, globalDiagKey + i + 1);
         continue;
        }

       double zoneSwingHigh = (poi.fiboSwingHigh > poi.fiboSwingLow) ? poi.fiboSwingHigh : swHigh;
       double zoneSwingLow  = (poi.fiboSwingHigh > poi.fiboSwingLow) ? poi.fiboSwingLow  : swLow;
       double zoneSwingRange = zoneSwingHigh - zoneSwingLow;
       double curRange = (zoneSwingRange > 0.0) ? zoneSwingRange : (poi.top - poi.bottom);

      //================================================================
      // DEMAND POI -> BUY LIMIT: 0.618/0.705/0.786 Fib, conditional 15%/45% OB,
      // and the 50% FVG consequent encroachment only.
      //================================================================
      if(poi.type == ZONE_DEMAND)
        {
         double              candPrice[ENTRY_VARIANT_COUNT];
         ENUM_SMC_ENTRY_TYPE candType[ENTRY_VARIANT_COUNT];
         int                 numCands = 0;

          // Fib levels use the dealing range frozen when the parent POI formed.
          double refHigh = (zoneSwingHigh > poi.top) ? zoneSwingHigh : poi.top;
          candPrice[numCands] = refHigh - 0.618 * curRange; candType[numCands++] = ENTRY_TYPE_FIB_618;
          candPrice[numCands] = refHigh - 0.705 * curRange; candType[numCands++] = ENTRY_TYPE_FIB_705;
          candPrice[numCands] = refHigh - 0.786 * curRange; candType[numCands++] = ENTRY_TYPE_FIB_790;

          bool useOB15Branch = false;
          if(!useM3RefinementContext || hasRefinedOB)
            {
              double obWidth = obTop - obBottom;
              double ob15Entry = obBottom + 0.15 * obWidth;
              double naturalOB15SL = obBottom - cachedSLBuffer - MathMax(stopsLvl, spreadPrice);
              double naturalOB15Pips = (ob15Entry - naturalOB15SL) / pip;
              useOB15Branch = (naturalOB15Pips <= 40.0);
              candPrice[numCands] = ob15Entry; candType[numCands++] = ENTRY_TYPE_OB_15;
              candPrice[numCands] = obBottom + 0.45 * obWidth; candType[numCands++] = ENTRY_TYPE_OB_45;
            }

         // FVG_50 is a POI-entry variant only when the FVG itself passed
         // IsFVGValidWithStructure (poi.hasFVG or refined M3 FVG).
         if((hasRefinedFVG || poi.hasFVG) && fvgTop > fvgBottom)
           {
            double gap = fvgTop - fvgBottom;
            candPrice[numCands] = fvgTop - 0.50 * gap; candType[numCands++] = ENTRY_TYPE_FVG_50;
           }

          for(int c = 0; c < numCands; c++)
            {
              if(requestedVariant >= 0 && (int)candType[c] != requestedVariant) continue;
              if(!IsVariantAllowed(candType[c], globalDiagKey + i * 32 + c + 1)) continue;
              if(poi.hasTriggeredLayer[candType[c]] || poi.hasPendingLayer[candType[c]]) continue;
              SMC_Zone candidatePoi = poi;
              bool isFibCandidate = ((int)candType[c] >= (int)ENTRY_TYPE_FIB_618 &&
                                     (int)candType[c] <= (int)ENTRY_TYPE_FIB_790);
              bool isOBCandidate = (candType[c] == ENTRY_TYPE_OB_15 || candType[c] == ENTRY_TYPE_OB_45);
              if(isOBCandidate &&
                 ((candType[c] == ENTRY_TYPE_OB_15) != useOB15Branch)) continue;
              if(isOBCandidate)
                {
                 candidatePoi.top = obTop;
                 candidatePoi.bottom = obBottom;
                }
              else if(!isFibCandidate)
                {
                 candidatePoi.top = fvgTop;
                 candidatePoi.bottom = fvgBottom;
                 candidatePoi.hasFVG = true;
                 candidatePoi.fvgTop = fvgTop;
                 candidatePoi.fvgBottom = fvgBottom;
                }
              double limitP = NormalizeDouble(candPrice[c], symDigits);
             if(HasEquivalentPendingOrder(ORDER_TYPE_BUY_LIMIT, candType[c], limitP))
               {
                g_diagnostics.Record(REJECT_LAYER_DUPLICATE, globalDiagKey + i * 32 + c + 1);
                continue;
               }
            if(curAsk <= (limitP + minLimitDist)) continue;
            double entryATR = cachedEntryATR;
            if(InpMaxEntryDistanceATR > 0.0 && entryATR > 0.0 &&
               (curAsk - limitP) > InpMaxEntryDistanceATR * entryATR)
              {
               g_diagnostics.Record(REJECT_ENTRY_TOO_FAR, globalDiagKey + i * 32 + c + 1);
               continue;
              }
            double clusterATR = entryATR;
            double clusterMinDist = (InpVariantClusterMinATR > 0.0 && clusterATR > 0.0)
                                  ? InpVariantClusterMinATR * clusterATR : 0.0;
            if(HasCorrelatedPendingOrder(ORDER_TYPE_BUY_LIMIT, limitP, clusterMinDist))
              {
               g_diagnostics.Record(REJECT_CLUSTER_TOO_CLOSE, globalDiagKey + i * 32 + c + 1);
               continue;
              }

             // Structure variants must be inside their own structure. Fibonacci
             // variants are validated against the frozen M15 dealing range.
              if(!isFibCandidate &&
                 (limitP < (candidatePoi.bottom - 5.0 * pip) || limitP > (candidatePoi.top + 5.0 * pip))) continue;
              if(isFibCandidate &&
                 (limitP < zoneSwingLow || limitP > zoneSwingHigh)) continue;

            double slBuffer = cachedSLBuffer;
            double executionBuffer = MathMax(stopsLvl, spreadPrice);
            double sl = NormalizeDouble(candidatePoi.bottom - slBuffer - executionBuffer,
                                       symDigits);
            double slP = (limitP - sl) / pip;
            g_diagnostics.RecordNaturalSL(slP);
            if(!ApplyBoundSL(limitP, true, pip, symDigits, sl, slP)) continue;

            if(InpUseMinimumRRRGate)
              {
               double structuralTarget = GetStructuralTarget(limitP, ZONE_DEMAND);
               double structuralRR = (structuralTarget > limitP)
                                     ? (structuralTarget - limitP) / MathMax(limitP - sl, point) : 0.0;
                if(structuralRR < RequiredStructuralRR())
                 {
                  g_diagnostics.Record(REJECT_MIN_RRR, globalDiagKey + i * 32 + c + 1);
                  continue;
                 }
              }
            // Distance separation filter
            bool tooClose = false;
            for(int p = 0; p < PositionsTotal(); p++)
              {
               ulong ticket = PositionGetTicket(p);
               if(ticket <= 0) continue;
               if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
               if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;

               double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
               double distPips = MathAbs(limitP - posOpen) / pip;
               if(distPips < 2.0)
                 {
                  tooClose = true;
                  break;
                 }
               if(!g_multiLayerAllowed && distPips < InpMultiPosMinDistPips)
                 {
                  tooClose = true;
                  break;
                 }
              }
            if(tooClose)
              {
               g_diagnostics.Record(REJECT_DISTANCE, globalDiagKey + i * 32 + c + 1);
               continue;
              }

            // 1. Base SMC Structural Confluence
            double smcScore = 50.0;
             if(candidatePoi.hasFVG) smcScore += 15.0; // FVG confluence bonus
             double recencyBonus = MathMax(0.0, (20.0 - candidatePoi.barAge)) / 20.0 * 15.0;
            smcScore += recencyBonus; // Newer zone bonus
            double distPips = (curAsk - limitP) / pip;
            double proxBonus = MathMax(0.0, (100.0 - distPips)) / 100.0 * 20.0;
            smcScore += proxBonus; // Closer proximity bonus

            // Optional M3 sweep bonus; never a hard requirement.
             if(InpUseLiquiditySweep && candidatePoi.m3SweepConfirmed) smcScore += 20.0;

            // Feature 3: Golden OTE Zone Confluence (+15 pts)
             if(InpUseOTEFilter && candidatePoi.isOTE) smcScore += 15.0;

            // M0 (Hybrid): M3-confirmed context is a bounded SOFT bonus. It can
            // break a tie between otherwise equal candidates but never gates.
            if(m3ConfirmedContext) smcScore += M3_CONFIRMED_SOFT_BONUS;

            smcScore += g_msnr.GetConfluenceBonus(limitP, ZONE_DEMAND, 15.0, 15.0);
             smcScore = g_signal.ApplyInstitutionalSoftScore(candidatePoi, SIGNAL_BUY, smcScore, counterTrend);

            // 2. SmartBrain weighting evaluates the complete independent pattern dimensions.
            int bIdx = -1;
            double finalScore = smcScore;
            if(InpUseSmartBrain)
              {
               ENUM_POI_PROFILE poiProfile;
               ENUM_OB_MITIGATION obMitigation;
               ENUM_FVG_MITIGATION fvgMitigation;
               ENUM_FIB_LEVEL fibLevel;
               g_signal.ClassifyPattern(limitP, candidatePoi, poiProfile, obMitigation, fvgMitigation, fibLevel);
                bIdx = g_brain.GetBucketIndex(sess, SIGNAL_BUY,
                                               MathMax((candidatePoi.top - candidatePoi.bottom)/pip, g_msnr.GetZoneWidthPips(primaryZone)),
                                               g_mtf.GetResult().bullPct,
                                               poiProfile, obMitigation, fvgMitigation, fibLevel);
              }
            if(finalScore < g_signal.GetMinimumSoftScore(counterTrend))
              {
               g_diagnostics.Record(counterTrend ? REJECT_DIRECTION_BIAS : REJECT_SOFT_SCORE,
                                    globalDiagKey + i * 32 + c + 1);
               continue;
              }

            if(finalScore > bestConfScore)
              {
               bestConfScore  = finalScore;
               bestPoiIdx     = i;
               bestLimitPrice = limitP;
               bestSLPrice    = sl;
               bestSLPips     = slP;
                bestBucketIdx  = bIdx;
                bestSetupType  = candType[c];
               bestZoneType   = ZONE_DEMAND;
               bestPrimaryZone = primaryZone;
               bestM3Confirmed = useM3RefinementContext;
               bestKingAgainst = counterTrend;
               bestPoiInOTE    = candidatePoi.isOTE;
               bestPoiRetested = poi.wasTouched;
               bestParentOBColor = poi.parentOBColor;
               bestExecutionOBColor = (hasRefinedOB && g_hasMatrixTriggerContext)
                                      ? g_matrixTriggerContext.executionOBColor : OB_COLOR_UNKNOWN;
              }
           }
        }

      //================================================================
      // SUPPLY POI mirrors demand: full wick OB, conditional 15%/45%, CE only.
      //================================================================
      else if(poi.type == ZONE_SUPPLY)
        {
         double              candPrice[ENTRY_VARIANT_COUNT];
         ENUM_SMC_ENTRY_TYPE candType[ENTRY_VARIANT_COUNT];
         int                 numCands = 0;

          double refLow = (zoneSwingLow < poi.bottom && zoneSwingLow > 0.0) ? zoneSwingLow : poi.bottom;
          candPrice[numCands] = refLow + 0.618 * curRange; candType[numCands++] = ENTRY_TYPE_FIB_618;
          candPrice[numCands] = refLow + 0.705 * curRange; candType[numCands++] = ENTRY_TYPE_FIB_705;
          candPrice[numCands] = refLow + 0.786 * curRange; candType[numCands++] = ENTRY_TYPE_FIB_790;

          bool useOB15Branch = false;
          if(!useM3RefinementContext || hasRefinedOB)
            {
              double obWidth = obTop - obBottom;
              double ob15Entry = obTop - 0.15 * obWidth;
              double naturalOB15SL = obTop + cachedSLBuffer + MathMax(stopsLvl, spreadPrice);
              double naturalOB15Pips = (naturalOB15SL - ob15Entry) / pip;
              useOB15Branch = (naturalOB15Pips <= 40.0);
              candPrice[numCands] = ob15Entry; candType[numCands++] = ENTRY_TYPE_OB_15;
              candPrice[numCands] = obTop - 0.45 * obWidth; candType[numCands++] = ENTRY_TYPE_OB_45;
            }

         if((hasRefinedFVG || poi.hasFVG) && fvgTop > fvgBottom)
           {
            double gap = fvgTop - fvgBottom;
            candPrice[numCands] = fvgBottom + 0.50 * gap; candType[numCands++] = ENTRY_TYPE_FVG_50;
           }

          for(int c = 0; c < numCands; c++)
            {
              if(requestedVariant >= 0 && (int)candType[c] != requestedVariant) continue;
              if(!IsVariantAllowed(candType[c], globalDiagKey + i * 32 + c + 1)) continue;
              if(poi.hasTriggeredLayer[candType[c]] || poi.hasPendingLayer[candType[c]]) continue;
              SMC_Zone candidatePoi = poi;
              bool isFibCandidate = ((int)candType[c] >= (int)ENTRY_TYPE_FIB_618 &&
                                     (int)candType[c] <= (int)ENTRY_TYPE_FIB_790);
              bool isOBCandidate = (candType[c] == ENTRY_TYPE_OB_15 || candType[c] == ENTRY_TYPE_OB_45);
              if(isOBCandidate &&
                 ((candType[c] == ENTRY_TYPE_OB_15) != useOB15Branch)) continue;
              if(isOBCandidate)
                {
                 candidatePoi.top = obTop;
                 candidatePoi.bottom = obBottom;
                }
              else if(!isFibCandidate)
                {
                 candidatePoi.top = fvgTop;
                 candidatePoi.bottom = fvgBottom;
                 candidatePoi.hasFVG = true;
                 candidatePoi.fvgTop = fvgTop;
                 candidatePoi.fvgBottom = fvgBottom;
                }
              double limitP = NormalizeDouble(candPrice[c], symDigits);
             if(HasEquivalentPendingOrder(ORDER_TYPE_SELL_LIMIT, candType[c], limitP))
               {
                g_diagnostics.Record(REJECT_LAYER_DUPLICATE, globalDiagKey + i * 32 + c + 1);
                continue;
               }
            if(curBid >= (limitP - minLimitDist)) continue;
            double entryATR = cachedEntryATR;
            if(InpMaxEntryDistanceATR > 0.0 && entryATR > 0.0 &&
               (limitP - curBid) > InpMaxEntryDistanceATR * entryATR)
              {
               g_diagnostics.Record(REJECT_ENTRY_TOO_FAR, globalDiagKey + i * 32 + c + 1);
               continue;
              }
            double clusterATR = entryATR;
            double clusterMinDist = (InpVariantClusterMinATR > 0.0 && clusterATR > 0.0)
                                  ? InpVariantClusterMinATR * clusterATR : 0.0;
            if(HasCorrelatedPendingOrder(ORDER_TYPE_SELL_LIMIT, limitP, clusterMinDist))
              {
               g_diagnostics.Record(REJECT_CLUSTER_TOO_CLOSE, globalDiagKey + i * 32 + c + 1);
               continue;
              }

              if(!isFibCandidate &&
                 (limitP < (candidatePoi.bottom - 5.0 * pip) || limitP > (candidatePoi.top + 5.0 * pip))) continue;
              if(isFibCandidate &&
                 (limitP < zoneSwingLow || limitP > zoneSwingHigh)) continue;

            double slBuffer = cachedSLBuffer;
            double executionBuffer = MathMax(stopsLvl, spreadPrice);
            double sl = NormalizeDouble(candidatePoi.top + slBuffer + executionBuffer,
                                       symDigits);
            double slP = (sl - limitP) / pip;
            g_diagnostics.RecordNaturalSL(slP);
            if(!ApplyBoundSL(limitP, false, pip, symDigits, sl, slP)) continue;

            if(InpUseMinimumRRRGate)
              {
               double structuralTarget = GetStructuralTarget(limitP, ZONE_SUPPLY);
               double structuralRR = (structuralTarget > 0.0 && structuralTarget < limitP)
                                     ? (limitP - structuralTarget) / MathMax(sl - limitP, point) : 0.0;
                if(structuralRR < RequiredStructuralRR())
                 {
                  g_diagnostics.Record(REJECT_MIN_RRR, globalDiagKey + i * 32 + c + 1);
                  continue;
                 }
              }
            // Distance separation filter
            bool tooClose = false;
            for(int p = 0; p < PositionsTotal(); p++)
              {
               ulong ticket = PositionGetTicket(p);
               if(ticket <= 0) continue;
               if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
               if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;

               double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
               double distPips = MathAbs(limitP - posOpen) / pip;
               if(distPips < 2.0)
                 {
                  tooClose = true;
                  break;
                 }
               if(!g_multiLayerAllowed && distPips < InpMultiPosMinDistPips)
                 {
                  tooClose = true;
                  break;
                 }
              }
            if(tooClose)
              {
               g_diagnostics.Record(REJECT_DISTANCE, globalDiagKey + i * 32 + c + 1);
               continue;
              }

            // 1. Base SMC Structural Confluence
            double smcScore = 50.0;
             if(candidatePoi.hasFVG) smcScore += 15.0; // FVG confluence bonus
             double recencyBonus = MathMax(0.0, (20.0 - candidatePoi.barAge)) / 20.0 * 15.0;
            smcScore += recencyBonus; // Newer zone bonus
            double distPips = (limitP - curBid) / pip;
            double proxBonus = MathMax(0.0, (100.0 - distPips)) / 100.0 * 20.0;
            smcScore += proxBonus; // Closer proximity bonus

            // Optional M3 sweep bonus; never a hard requirement.
             if(InpUseLiquiditySweep && candidatePoi.m3SweepConfirmed) smcScore += 20.0;

            // Feature 3: Golden OTE Zone Confluence (+15 pts)
             if(InpUseOTEFilter && candidatePoi.isOTE) smcScore += 15.0;

            // M0 (Hybrid): M3-confirmed context is a bounded SOFT bonus. It can
            // break a tie between otherwise equal candidates but never gates.
            if(m3ConfirmedContext) smcScore += M3_CONFIRMED_SOFT_BONUS;

            smcScore += g_msnr.GetConfluenceBonus(limitP, ZONE_SUPPLY, 15.0, 15.0);
             smcScore = g_signal.ApplyInstitutionalSoftScore(candidatePoi, SIGNAL_SELL, smcScore, counterTrend);

            // 2. SmartBrain weighting evaluates the complete independent pattern dimensions.
            int bIdx = -1;
            double finalScore = smcScore;
            if(InpUseSmartBrain)
              {
               ENUM_POI_PROFILE poiProfile;
               ENUM_OB_MITIGATION obMitigation;
               ENUM_FVG_MITIGATION fvgMitigation;
               ENUM_FIB_LEVEL fibLevel;
               g_signal.ClassifyPattern(limitP, candidatePoi, poiProfile, obMitigation, fvgMitigation, fibLevel);
                bIdx = g_brain.GetBucketIndex(sess, SIGNAL_SELL,
                                               MathMax((candidatePoi.top - candidatePoi.bottom)/pip, g_msnr.GetZoneWidthPips(primaryZone)),
                                               100.0 - g_mtf.GetResult().bullPct,
                                               poiProfile, obMitigation, fvgMitigation, fibLevel);
              }
            if(finalScore < g_signal.GetMinimumSoftScore(counterTrend))
              {
               g_diagnostics.Record(counterTrend ? REJECT_DIRECTION_BIAS : REJECT_SOFT_SCORE,
                                    globalDiagKey + i * 32 + c + 1);
               continue;
              }

            if(finalScore > bestConfScore)
              {
               bestConfScore  = finalScore;
               bestPoiIdx     = i;
               bestLimitPrice = limitP;
               bestSLPrice    = sl;
               bestSLPips     = slP;
                bestBucketIdx  = bIdx;
                bestSetupType  = candType[c];
               bestZoneType   = ZONE_SUPPLY;
               bestPrimaryZone = primaryZone;
               bestM3Confirmed = useM3RefinementContext;
               bestKingAgainst = counterTrend;
               bestPoiInOTE    = candidatePoi.isOTE;
               bestPoiRetested = poi.wasTouched;
               bestParentOBColor = poi.parentOBColor;
               bestExecutionOBColor = (hasRefinedOB && g_hasMatrixTriggerContext)
                                      ? g_matrixTriggerContext.executionOBColor : OB_COLOR_UNKNOWN;
              }
           }
        }
     }

   // If no valid POI candidate was selected, exit
   if(bestPoiIdx < 0 || bestLimitPrice <= 0.0)
     {
      g_diagnostics.Record(totalPOIs <= 0 ? REJECT_NO_ACTIVE_POI : REJECT_NOT_IN_POI, globalDiagKey);
      return false;
     }

   // Gen-6C M1: single same-direction re-entry cooldown at the one choke point
   // every caller (CONFIRMED / FALLBACK / DIRECT / MANUAL) routes through.
   const ENUM_ORDER_TYPE cooldownType = (bestZoneType == ZONE_DEMAND) ? ORDER_TYPE_BUY_LIMIT
                                                                     : ORDER_TYPE_SELL_LIMIT;
   if(!explorationMode && SameDirectionReentryBlocked(cooldownType))
     {
      g_diagnostics.Record(REJECT_REENTRY_COOLDOWN, globalDiagKey);
      return false;
     }

   datetime scaleBOSTime = 0;
   if(!explorationMode && openCount >= 1 && !CanSecondaryScaleIn(bestZoneType, scaleBOSTime))
     {
      g_diagnostics.Record(REJECT_POSITION_LIMIT, globalDiagKey);
      return false;
     }

   // Calculate lot size strictly based on configured risk
   double effRisk = (historicalMatrixTest || g_effectiveCollectionMode)
                    ? InpCollectionRiskPct
                    : (g_multiLayerAllowed ? (InpRiskPercent / (double)g_effectiveMaxPositions) : InpRiskPercent);
   // H5: in explicit matrix/collection mode, InpCollectionRiskPct is the total
   // risk budget for the signal cluster, not a fresh budget for every mitigation
   // order. Cap the divisor at the six candidates the current model can emit.
   // Normal/strict mode places one selected candidate.
   int clusterVariants = (historicalMatrixTest || g_effectiveCollectionMode)
                         ? MathMax(1, MathMin(MATRIX_MAX_CANDIDATE_COUNT,
                                              g_entryVariants.AllowedCount())) : 1;
   if(clusterVariants > 1) effRisk /= (double)clusterVariants;
   SBrainBucketView bestView;
   BrainViewReset(bestView);
   if(InpUseSmartBrain && bestBucketIdx >= 0)
      g_brain.GetBucketView(bestBucketIdx, bestView);
   ENUM_SETUP_GRADE limitGrade = g_signal.EvaluateSetupGrade(bestPrimaryZone, bestM3Confirmed,
                                                            bestKingAgainst, bestLimitPrice,
                                                            bestSLPrice, 0.0, bestZoneType,
                                                            bestPoiInOTE);
   double lotMult = SetupGradeLotMultiplier(limitGrade);
   if(SetupGradeRejects(limitGrade) || lotMult <= 0.0)
     {
      g_diagnostics.Record(REJECT_SETUP_GRADE, globalDiagKey);
      return false;
     }
   if(!explorationMode)
     {
      effRisk *= lotMult;
      double brainRiskMult = InpUseDynamicRisk ? BrainRiskOverlayMultiplier(bestView) : 1.0;
      effRisk *= brainRiskMult;
      if(brainRiskMult < 1.0)
         LogThrottled("BRAIN_RISK_OVERLAY", 5,
                      StringFormat("risk reduced to 0.50x for negative Brain bucket | evidence=%s ExpR=%s",
                                   DoubleToString(bestView.realEvidence, 2),
                                   DoubleToString(bestView.avgNetR, 3)), LOG_LEVEL_INFO);
      // H1/H3: a single trade must never be sized past the account's declared
      // aggregate risk appetite, or CanAddAggregateRisk below rejects it outright
      // and the entire rung silently never executes (that is precisely what the
      // 2.00x rung can exceed a deliberately tighter aggregate cap. Clamp
      // rather than reject, and log it so the ladder stays auditable from the
      // journal instead of having to be inferred from lot sizes.
      if(InpMaxAggregateRiskPct > 0.0 && effRisk > InpMaxAggregateRiskPct)
        {
         LogThrottled("LOT_LADDER", 5,
                      StringFormat("risk %s%% clamped to aggregate cap %s%% | grade=%s mult=%sx",
                                   DoubleToString(effRisk, 2),
                                   DoubleToString(InpMaxAggregateRiskPct, 2),
                                   SetupGradeName(limitGrade),
                                   DoubleToString(lotMult, 2)),
                      LOG_LEVEL_INFO);
         effRisk = InpMaxAggregateRiskPct;
        }
     }

   double baseLots = (!explorationMode && InpFixedLot > 0)
                     ? InpFixedLot
                     : g_risk.CalcLotSize(effRisk, bestSLPips, Symbol(), bestLimitPrice,
                                           bestZoneType == ZONE_DEMAND ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   NoteLotStatus(g_risk.LastLotStatus());
   double lots = (!explorationMode && InpFixedLot > 0)
                 ? g_risk.RoundLotToStep(baseLots)
                 : baseLots;
   lots = EnforceBrokerMinLot(lots, Symbol());
   if(lots <= 0.0)
      lots = EnforceBrokerMinLot(YANSTD_HARD_MIN_LOT, Symbol());
   if(lots <= 0.0)
     {
      g_diagnostics.Record(REJECT_LOT_TOO_SMALL, globalDiagKey);
      return false;
     }
   if(InpExitMode == EXIT_STAGED && InpUseTP1 && !g_orders.CanScaleOut(lots, InpTP1ClosePct, InpTP2ClosePct, Symbol()))
     {
      if(!g_allowSingleExitBelowRunnerMin)
        {
         g_diagnostics.Record(REJECT_LOT_TOO_SMALL, globalDiagKey);
         LogThrottled("H4_ENTRY_GATE", 5,
                StringFormat("Entry rejected: %.2f lots cannot support staged %.1f/%.1f/%.1f%% exits on %s",
                             lots, InpTP1ClosePct, InpTP2ClosePct,
                             100.0 - InpTP1ClosePct - InpTP2ClosePct, Symbol()));
         return false;
        }
      LogThrottled("H4_ENTRY_GATE", 5,
             StringFormat("Single-exit fallback: %.2f lots below the staged-exit floor %.2f; "
                          "trading full volume on one TP (no 50/25/25 split) on %s",
                          lots, InpMinRunnerInitialLot, Symbol()));
     }
   double projectedRiskPct = 0.0;
   ENUM_ORDER_TYPE calcType = (bestZoneType == ZONE_DEMAND) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!CanAddAggregateRisk(calcType, lots, bestLimitPrice, bestSLPrice, projectedRiskPct))
     {
      g_diagnostics.Record(REJECT_AGGREGATE_RISK, globalDiagKey);
      LogThrottled("RISK_GUARD", 5,
                  StringFormat("Pending rejected | Projected aggregate risk=%s%% > cap %s%%",
                               DoubleToString(projectedRiskPct, 2),
                               DoubleToString(InpMaxAggregateRiskPct, 2)));
      return false;
     }
   datetime expTime = (InpLimitExpirationBars > 0)
                      ? TimeCurrent() + InpLimitExpirationBars * PeriodSeconds(g_effectiveRefinementTF)
                      : 0;
    ulong setupEventId = (g_hasMatrixTriggerContext
                                             ? g_matrixTriggerContext.setupEventId
                                             : ((((ulong)TimeCurrent() ^
                                                  (ulong)MathRound(bestLimitPrice / MathMax(point, 1e-9))) &
                                                 (ulong)0x7FFFFFFF) + 1));
    string comm = historicalMatrixTest
                  ? FormatEntryComment(bestBucketIdx, (int)bestSetupType, (int)limitGrade, setupEventId, true)
                  : FormatEntryComment(bestBucketIdx, (int)bestSetupType, (int)limitGrade, setupEventId, false);

   string setupStr = g_signal.GetSetupTypeString(bestSetupType);
   string entrySource = (bestSetupType == ENTRY_TYPE_OB_15 || bestSetupType == ENTRY_TYPE_OB_45) ? "OB"
                        : (bestSetupType == ENTRY_TYPE_FVG_50 ? "FVG" : "FIB");
   string entryFreshness = bestPoiRetested ? "RETESTED" : "FRESH";
   // OB colour marker is attribution/display-only: the relevant bonus applies
   // only to an OB entry variant, and at most once. Execution OB colour wins
   // when present; otherwise the parent OB colour is used. Any OB entry whose
   // effective colour is not OPPOSITE gets NONE (bonus not active) -- never
   // UNKNOWN, which would read as "not evaluated".
   string obMarkerStr = "NONE";
   if(entrySource == "OB")
     {
      ENUM_OB_COLOR effective = (bestExecutionOBColor != OB_COLOR_UNKNOWN)
                                ? bestExecutionOBColor : bestParentOBColor;
      if(effective == OB_COLOR_OPPOSITE) obMarkerStr = "OPPOSITE";
     }

   if(bestZoneType == ZONE_DEMAND)
     {
      double serverTP = 0.0, tp1Px = 0.0, tp2Px = 0.0, tp1Pct = 0.0, tp2Pct = 0.0;
      double emergencyTP = 0.0;
      if(IsStructuralExitMode())
        {
         PlanStructuralTP(bestLimitPrice, true, ZONE_DEMAND, pip, symDigits,
                          serverTP, tp1Px, tp2Px, tp1Pct, tp2Pct,
                          MathAbs(bestLimitPrice - bestSLPrice));
         double minLot = EffectiveBrokerMinLot(Symbol());
         double half   = g_risk.RoundLotToStep(lots * 0.5);
         if(tp1Pct > 0.0 && (half < minLot || (lots - half) < minLot))
           { tp1Px = 0.0; tp1Pct = 0.0; }
         emergencyTP = serverTP;
        }
      else
        {
         double serverTPRR = (InpExitMode == EXIT_FIXED_RR) ? InpFixedRR : InpEmergencyServerTPRR;
         emergencyTP = (serverTPRR > 0.0)
                       ? NormalizeDouble(bestLimitPrice + MathAbs(bestLimitPrice - bestSLPrice) * serverTPRR,
                                         symDigits) : 0.0;
        }
      if(g_orders.PlaceBuyLimit(bestLimitPrice, lots, bestSLPrice, emergencyTP, comm, expTime))
        {
         g_diagnostics.RecordPendingPlaced();
         g_lastEntryTime    = TimeCurrent();
         NoteEntryDirection(ORDER_TYPE_BUY_LIMIT);
          if(scaleBOSTime > 0) g_lastConsumedScaleBOS = scaleBOSTime;
         g_signal.SetPOIPendingLayer(bestPoiIdx, bestSetupType, true, setupEventId);
         Print("YANSTD Auto Limit: BUY LIMIT Placed [", setupStr, "] @ ", bestLimitPrice, " | SL:", bestSLPrice, " (", DoubleToString(bestSLPips, 1), "p) | Lot:", lots, " | Session=", EnumToString(sess), " | Score:", DoubleToString(bestConfScore, 1), " | Path=", entryPath, " | Source=", entrySource, " | Freshness=", entryFreshness, " | ParentOBColor=", OBColorLabel(bestParentOBColor), " | ExecutionOBColor=", OBColorLabel(bestExecutionOBColor), " | OBColorMarker=", obMarkerStr);
         return true;
         }
      else if(!g_orders.LastRejectWasEntryStopsTooClose())
         g_diagnostics.Record(REJECT_ORDER_SEND, (long)TimeCurrent());
     }
   else if(bestZoneType == ZONE_SUPPLY)
     {
      double serverTP = 0.0, tp1Px = 0.0, tp2Px = 0.0, tp1Pct = 0.0, tp2Pct = 0.0;
      double emergencyTP = 0.0;
      if(IsStructuralExitMode())
        {
         PlanStructuralTP(bestLimitPrice, false, ZONE_SUPPLY, pip, symDigits,
                          serverTP, tp1Px, tp2Px, tp1Pct, tp2Pct,
                          MathAbs(bestSLPrice - bestLimitPrice));
         double minLot = EffectiveBrokerMinLot(Symbol());
         double half   = g_risk.RoundLotToStep(lots * 0.5);
         if(tp1Pct > 0.0 && (half < minLot || (lots - half) < minLot))
           { tp1Px = 0.0; tp1Pct = 0.0; }
         emergencyTP = serverTP;
        }
      else
        {
         double serverTPRR = (InpExitMode == EXIT_FIXED_RR) ? InpFixedRR : InpEmergencyServerTPRR;
         emergencyTP = (serverTPRR > 0.0)
                       ? NormalizeDouble(bestLimitPrice - MathAbs(bestSLPrice - bestLimitPrice) * serverTPRR,
                                         symDigits) : 0.0;
        }
      if(g_orders.PlaceSellLimit(bestLimitPrice, lots, bestSLPrice, emergencyTP, comm, expTime))
        {
         g_diagnostics.RecordPendingPlaced();
         g_lastEntryTime    = TimeCurrent();
         NoteEntryDirection(ORDER_TYPE_SELL_LIMIT);
          if(scaleBOSTime > 0) g_lastConsumedScaleBOS = scaleBOSTime;
         g_signal.SetPOIPendingLayer(bestPoiIdx, bestSetupType, true, setupEventId);
         Print("YANSTD Auto Limit: SELL LIMIT Placed [", setupStr, "] @ ", bestLimitPrice, " | SL:", bestSLPrice, " (", DoubleToString(bestSLPips, 1), "p) | Lot:", lots, " | Session=", EnumToString(sess), " | Score:", DoubleToString(bestConfScore, 1), " | Path=", entryPath, " | Source=", entrySource, " | Freshness=", entryFreshness, " | ParentOBColor=", OBColorLabel(bestParentOBColor), " | ExecutionOBColor=", OBColorLabel(bestExecutionOBColor), " | OBColorMarker=", obMarkerStr);
         return true;
         }
      else if(!g_orders.LastRejectWasEntryStopsTooClose())
         g_diagnostics.Record(REJECT_ORDER_SEND, (long)TimeCurrent());
     }
   return false;
  }

void UpdatePositionState()
  {
   g_orders.PurgeStaleTracks(); // Release tracking slots for closed positions
   g_hasPosition = g_orders.HasOpenPosition();
   if(g_hasPosition)
      g_orders.GetPosition(0, g_posInfo); // g_posInfo = first position (for dashboard)
  }

void UpdateLotFromRisk()
  {
   g_lotManual = false;
   if(InpFixedLot <= 0)
      g_lotDisplay = g_risk.CalcLotSize(g_riskDisplay, 35.0);
  }



int GetCandleSecondsLeft(ENUM_TIMEFRAMES tf)
  {
   datetime barTime  = (datetime)SeriesInfoInteger(Symbol(), tf, SERIES_LASTBAR_DATE);
   int      tfSecs   = PeriodSeconds(tf);
   datetime nextBar  = barTime + tfSecs;
   int      secsLeft = (int)(nextBar - TimeCurrent());
   return MathMax(0, secsLeft);
  }

// M4: find (or create) the persistent slot for a position id inside the
// g_statsPos* arrays. Mirrors the old local-array logic (sorted-array binary
// search with a linear-scan fallback once an out-of-order id is seen) but
// against arrays that live for the whole run instead of being rebuilt per
// call.
int FindOrCreateStatsPos(ulong posId)
  {
   int idx = -1;
   if(g_statsPosIdsSorted)
     {
      int lo = 0, hi = g_statsPosCount - 1;
      while(lo <= hi)
        {
         int mid = lo + (hi - lo) / 2;
         if(g_statsPosIds[mid] == posId) { idx = mid; break; }
         if(g_statsPosIds[mid] < posId) lo = mid + 1; else hi = mid - 1;
        }
     }
   else
     {
      for(int p = 0; p < g_statsPosCount; p++)
         if(g_statsPosIds[p] == posId) { idx = p; break; }
     }
   if(idx >= 0) return idx;

   if(g_statsPosCount > 0 && posId < g_statsPosIds[g_statsPosCount - 1]) g_statsPosIdsSorted = false;
   idx = g_statsPosCount++;
   // Pre-allocate in chunks to avoid O(N^2) reallocation scaling as positions accrue.
   ArrayResize(g_statsPosIds,          g_statsPosCount, 512);
   ArrayResize(g_statsPosProfit,       g_statsPosCount, 512);
   ArrayResize(g_statsPosCloseTime,    g_statsPosCount, 512);
   ArrayResize(g_statsPosHasExit,      g_statsPosCount, 512);
   ArrayResize(g_statsPosCounted,      g_statsPosCount, 512);
   ArrayResize(g_statsPosType,         g_statsPosCount, 512);
   ArrayResize(g_statsPosOpenPxVolSum, g_statsPosCount, 512);
   ArrayResize(g_statsPosOpenVol,      g_statsPosCount, 512);
   ArrayResize(g_statsPosExitPxVolSum, g_statsPosCount, 512);
   ArrayResize(g_statsPosExitVol,      g_statsPosCount, 512);
   g_statsPosIds[idx]          = posId;
   g_statsPosProfit[idx]       = 0.0;
   g_statsPosCloseTime[idx]    = 0;
   g_statsPosHasExit[idx]      = false;
   g_statsPosCounted[idx]      = false;
   g_statsPosType[idx]         = -1;
   g_statsPosOpenPxVolSum[idx] = 0.0;
   g_statsPosOpenVol[idx]      = 0.0;
   g_statsPosExitPxVolSum[idx] = 0.0;
   g_statsPosExitVol[idx]      = 0.0;
   return idx;
  }

// M4: remember a completed-today trade's session + outcome so a later session
// change (with no new deal) can re-tally sessionWins/sessionLosses against
// today's trades only, instead of rescanning the whole deal history.
void AddTodayCompletedTrade(ENUM_SESSION_TYPE sessAtClose, bool isWin)
  {
   g_statsTodayCount++;
   ArrayResize(g_statsTodaySess, g_statsTodayCount, 256);
   ArrayResize(g_statsTodayWin,  g_statsTodayCount, 256);
   g_statsTodaySess[g_statsTodayCount - 1] = (int)sessAtClose;
   g_statsTodayWin[g_statsTodayCount - 1]  = isWin;
  }

// M4: once a position's final exit deal has landed (no matching ticket left
// in PositionsTotal()), fold it into the lifetime/day/session totals exactly
// once. This replaces the old approach of rescanning every open position on
// every heavy rebuild.
void TryFinalizeStatsPosition(int idx, datetime startOfDayUTC, ENUM_SESSION_TYPE currentSess)
  {
   if(!g_statsPosHasExit[idx] || g_statsPosCounted[idx]) return;

   ulong posId = g_statsPosIds[idx];
   bool stillOpen = false;
   int totalOpen = PositionsTotal();
   for(int p = 0; p < totalOpen; p++)
     {
      ulong pt = PositionGetTicket(p);
      if(pt <= 0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == posId) { stillOpen = true; break; }
     }
   if(stillOpen) return; // a leg is still open (partial close) -- wait for the final exit deal

   g_statsPosCounted[idx] = true;
   if(g_statsPosCloseTime[idx] < g_stats.resetEpoch) return; // trade closed before the last manual reset

   double posProfit = g_statsPosProfit[idx];
   bool   isWin      = (posProfit > 0.0);

   g_stats.totalTrades++;
   g_stats.totalProfit += posProfit;
   if(isWin) g_stats.totalWins++;

   // Multi-Currency Dashboard: pip-equivalent result per completed trade, using
   // the volume-weighted average entry vs. average exit price so TP1/TP2/runner
   // partial-close legs are all correctly represented.
   double posPips = 0.0;
   double pipSize = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
   if(pipSize > 0.0 && g_statsPosOpenVol[idx] > 0.0 && g_statsPosExitVol[idx] > 0.0)
     {
      double avgOpen = g_statsPosOpenPxVolSum[idx] / g_statsPosOpenVol[idx];
      double avgExit = g_statsPosExitPxVolSum[idx] / g_statsPosExitVol[idx];
      posPips = (g_statsPosType[idx] == POSITION_TYPE_BUY) ? (avgExit - avgOpen) / pipSize
                                                            : (avgOpen - avgExit) / pipSize;
     }
   g_stats.totalPips += posPips;

   datetime closeTimeUTC = g_session.ConvertServerToUTC(g_statsPosCloseTime[idx]);
   if(closeTimeUTC >= startOfDayUTC)
     {
      g_stats.dailyPips += posPips;
      ENUM_SESSION_TYPE dealSess = g_session.GetSessionAtUTC(closeTimeUTC);
      AddTodayCompletedTrade(dealSess, isWin);
      if(dealSess == currentSess || currentSess == SESSION_NONE)
        {
         if(isWin) g_stats.sessionWins++;
         else      g_stats.sessionLosses++;
        }
     }
  }

// M4: apply ONE deal's effect on the persistent stats accumulators. Used both
// by the per-deal hot path (OnStatsDealArrived) and by the full-history
// fallback rebuild (RebuildStatsHistoryFull), so the two paths can never
// disagree on how a deal is folded into the totals.
void ApplyStatsDeal(ulong ticket, datetime startOfDayUTC, ENUM_SESSION_TYPE currentSess)
  {
   double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
   if(dealTime >= g_stats.resetEpoch &&
      g_session.ConvertServerToUTC(dealTime) >= startOfDayUTC) g_stats.dailyProfit += profit;

   ulong posId = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
   int idx = FindOrCreateStatsPos(posId);
   g_statsPosProfit[idx] += profit;

   double dealPrice  = HistoryDealGetDouble(ticket, DEAL_PRICE);
   double dealVolume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
     {
      if(g_statsPosType[idx] < 0)
         g_statsPosType[idx] = (int)HistoryDealGetInteger(ticket, DEAL_TYPE); // DEAL_TYPE_BUY==POSITION_TYPE_BUY, etc.
      g_statsPosOpenPxVolSum[idx] += dealPrice * dealVolume;
      g_statsPosOpenVol[idx]      += dealVolume;
     }
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
     {
      g_statsPosHasExit[idx] = true;
      g_statsPosExitPxVolSum[idx] += dealPrice * dealVolume;
      g_statsPosExitVol[idx]      += dealVolume;
      if(dealTime > g_statsPosCloseTime[idx]) g_statsPosCloseTime[idx] = dealTime;
     }

   if(dealTime > g_statsLastDealTime || (dealTime == g_statsLastDealTime && ticket > g_statsLastDealTicket))
     {
      g_statsLastDealTime   = dealTime;
      g_statsLastDealTicket = ticket;
     }

   TryFinalizeStatsPosition(idx, startOfDayUTC, currentSess);
  }

// M4: O(1) rolling of the day/session windows. A new UTC day zeroes the daily
// and session counters (and today's completed-trade log); a session change
// with no new deal re-tallies sessionWins/sessionLosses against today's
// (bounded) completed-trade log instead of the full deal history.
void RollDailySessionWindows(datetime startOfDayUTC, ENUM_SESSION_TYPE currentSess)
  {
   if(startOfDayUTC != g_statsRollLastDayUTC)
     {
      g_stats.dailyProfit   = 0.0;
      g_stats.dailyPips     = 0.0;
      g_stats.sessionWins   = 0;
      g_stats.sessionLosses = 0;
      g_statsTodayCount     = 0;
      g_statsRollLastDayUTC  = startOfDayUTC;
      g_statsRollLastSessKey = (int)currentSess;
      return;
     }
   if((int)currentSess != g_statsRollLastSessKey)
     {
      g_statsRollLastSessKey = (int)currentSess;
      g_stats.sessionWins   = 0;
      g_stats.sessionLosses = 0;
      for(int i = 0; i < g_statsTodayCount; i++)
        {
         if((ENUM_SESSION_TYPE)g_statsTodaySess[i] == currentSess || currentSess == SESSION_NONE)
           {
            if(g_statsTodayWin[i]) g_stats.sessionWins++;
            else                   g_stats.sessionLosses++;
           }
        }
     }
  }

// M4: clears all persistent stats-history state. Called before a full rebuild
// (startup/recovery/manual reset) so stale accumulators from a previous run
// or a previous resetEpoch can never leak into the new totals.
void ResetStatsHistoryState()
  {
   ArrayResize(g_statsPosIds,          0);
   ArrayResize(g_statsPosProfit,       0);
   ArrayResize(g_statsPosCloseTime,    0);
   ArrayResize(g_statsPosHasExit,      0);
   ArrayResize(g_statsPosCounted,      0);
   ArrayResize(g_statsPosType,         0);
   ArrayResize(g_statsPosOpenPxVolSum, 0);
   ArrayResize(g_statsPosOpenVol,      0);
   ArrayResize(g_statsPosExitPxVolSum, 0);
   ArrayResize(g_statsPosExitVol,      0);
   g_statsPosCount     = 0;
   g_statsPosIdsSorted = true;
   ArrayResize(g_statsTodaySess, 0);
   ArrayResize(g_statsTodayWin,  0);
   g_statsTodayCount = 0;
   g_statsLastDealTime   = 0;
   g_statsLastDealTicket = 0;
  }

// M4: the ONLY function that still pays for HistorySelect(0, now) plus a full
// walk of every deal. Reserved for startup, terminal/tester recovery, and a
// manual stats reset -- never called per-deal. Every other update goes
// through OnStatsDealArrived()/ApplyStatsDeal(), which cost O(1) per deal
// regardless of how large the history has grown. Kept here in one place so
// it also serves as a fallback/verification rebuild if ever needed.
void RebuildStatsHistoryFull()
  {
   datetime now = TimeCurrent();
   if(!HistorySelect(0, now)) return;

   ResetStatsHistoryState();
   g_stats.dailyProfit    = 0.0;
   g_stats.dailyPips      = 0.0;
   g_stats.totalTrades    = 0;
   g_stats.totalWins      = 0;
   g_stats.totalProfit    = 0.0;
   g_stats.totalPips      = 0.0;
   g_stats.sessionWins    = 0;
   g_stats.sessionLosses  = 0;

   datetime nowUTC = g_session.GetSimulatedUTC();
   MqlDateTime dt; TimeToStruct(nowUTC, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime startOfDayUTC = StructToTime(dt);
   ENUM_SESSION_TYPE currentSess = g_session.GetCurrentSession();
   g_statsRollLastDayUTC  = startOfDayUTC;
   g_statsRollLastSessKey = (int)currentSess;

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != Symbol()) continue;
      ApplyStatsDeal(ticket, startOfDayUTC, currentSess);
     }

   g_statsHistoryBuilt  = true;
   g_statsHistoryDirty  = false;
  }

// M4: per-deal hot path called from OnTradeTransaction() as soon as a new
// deal for this EA (magic + symbol) lands. Costs O(1) (amortized) regardless
// of how many deals already exist in history -- it never calls
// HistorySelect(0, now) or loops over past deals.
void OnStatsDealArrived(ulong dealTicket)
  {
   if(!g_statsHistoryBuilt || g_statsHistoryDirty)
     {
      RebuildStatsHistoryFull(); // first deal ever seen, or a pending reset -- safe fallback
      return;
     }

   datetime nowUTC = g_session.GetSimulatedUTC();
   MqlDateTime dt; TimeToStruct(nowUTC, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime startOfDayUTC = StructToTime(dt);
   ENUM_SESSION_TYPE currentSess = g_session.GetCurrentSession();
   RollDailySessionWindows(startOfDayUTC, currentSess);

   ApplyStatsDeal(dealTicket, startOfDayUTC, currentSess);
  }

// M4: lightweight periodic refresh (called from OnInit, day-change checks,
// the tester visual-mode sync, the 60s dashboard timer, and OnNewHTFBar).
// It no longer rescans the deal history on every call -- new deals are
// already folded in by OnStatsDealArrived() the moment they land. This
// function only (a) performs the one-time full rebuild at startup/recovery
// or after a manual reset, (b) rolls the day/session windows forward, and
// (c) refreshes the balance-based dailyProfitPct, which is cheap regardless
// of history size.
void UpdateStatsFromHistory()
  {
   if(!g_statsHistoryBuilt || g_statsHistoryDirty)
     {
      RebuildStatsHistoryFull();
     }
   else
     {
      datetime nowUTC = g_session.GetSimulatedUTC();
      MqlDateTime dt; TimeToStruct(nowUTC, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime startOfDayUTC = StructToTime(dt);
      ENUM_SESSION_TYPE currentSess = g_session.GetCurrentSession();
      RollDailySessionWindows(startOfDayUTC, currentSess);
     }

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double startDayBalance = bal - g_stats.dailyProfit;
   double dailyEquityPnL = g_stats.dailyProfit + g_orders.GetTotalFloatingPnL();
   g_stats.dailyProfitPct = (startDayBalance > 0.0) ? (dailyEquityPnL / startDayBalance) * 100.0 : 0.0;
  }

void UpdatePositionExcursion(SPositionInfo &pos)
  {
   if(pos.initialRiskPrice <= 0.0) return;

   double bid = SymbolInfoDouble(pos.symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(pos.symbol, SYMBOL_ASK);
   double currentPrice = (pos.posType == POSITION_TYPE_BUY) ? bid : ask;
   if(currentPrice <= 0.0) return;

   double moveR = (pos.posType == POSITION_TYPE_BUY)
                  ? (currentPrice - pos.openPrice) / pos.initialRiskPrice
                  : (pos.openPrice - currentPrice) / pos.initialRiskPrice;
   double newMFE = MathMax(pos.maxFavorableR, MathMax(0.0, moveR));
   double newMAE = MathMax(pos.maxAdverseR, MathMax(0.0, -moveR));
   double point = SymbolInfoDouble(pos.symbol, SYMBOL_POINT);
   double spreadPoints = (point > 0.0 && ask >= bid) ? (ask - bid) / point : 0.0;
   double newMaxSpread = MathMax(pos.maxSpreadPoints, spreadPoints);
   if(newMFE > pos.maxFavorableR || newMAE > pos.maxAdverseR || newMaxSpread > pos.maxSpreadPoints)
     {
      pos.maxFavorableR = newMFE;
      pos.maxAdverseR   = newMAE;
      pos.maxSpreadPoints = newMaxSpread;
      g_orders.UpdateTrackExcursion(pos.ticket, newMFE, newMAE, newMaxSpread);
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   // M5: count pending-order lifecycle transitions at the transaction source,
   // rather than reconstructing them from a later history scan. A filled limit
   // is counted from its DEAL_ENTRY_IN below; this branch handles deletion.
   if(trans.type == TRADE_TRANSACTION_ORDER_DELETE && trans.order > 0)
     {
      bool owned = false;
      bool expired = (trans.order_state == ORDER_STATE_EXPIRED);
      if(HistoryOrderSelect(trans.order))
        {
         owned = (HistoryOrderGetInteger(trans.order, ORDER_MAGIC) == (long)InpMagicNumber &&
                  HistoryOrderGetString(trans.order, ORDER_SYMBOL) == Symbol());
         if(!expired) expired = (HistoryOrderGetInteger(trans.order, ORDER_STATE) == ORDER_STATE_EXPIRED);
        }
      if(owned && trans.order_state != ORDER_STATE_FILLED)
        {
         if(expired) g_diagnostics.RecordPendingExpired();
         else        g_diagnostics.RecordPendingCancelled();
        }
     }

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      ulong dealTicket = trans.deal;
      if(InpShowDashboard) g_dashboard.MarkDataDirty(); // GUI v3: re-read history on next timer tick
      if(!HistoryDealSelect(dealTicket)) return;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != (long)InpMagicNumber) return;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != Symbol()) return;

      // M4: fold this single deal into the persistent stats accumulators in
      // O(1) instead of flagging the next UpdateStatsFromHistory() call to
      // pay for a full HistorySelect(0, now) + all-deals rescan. Deals from
      // other symbols or other magics are filtered out above and are
      // excluded from every aggregate below, so they never reach here.
      OnStatsDealArrived(dealTicket);

      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      string comm = HistoryDealGetString(dealTicket, DEAL_COMMENT);
       int bIdxFromComment = -1;
       int setupFromComment = -1;
       int gradeFromComment = -1;
       ulong setupEventFromComment = 0;
       double brainEvidenceWeight = 1.0;
      ParseEntryComment(comm, bIdxFromComment, setupFromComment, gradeFromComment, setupEventFromComment);
       if(StringFind(comm, "_M") >= 0)
         {
          int siblingCount = GetMatrixSiblingCount(setupEventFromComment);
          if(siblingCount <= 0) siblingCount = MATRIX_MAX_CANDIDATE_COUNT;
          brainEvidenceWeight = 1.0 / (double)siblingCount;
         }

      // A filled limit order did not pass through ExecuteBuy/ExecuteSell, so create its
      // management track immediately from the confirmed entry deal.
       if(entry == DEAL_ENTRY_IN && setupFromComment >= 0 && trans.position > 0)
        {
         ulong fillOrder = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
         bool wasPendingFill = false;
         if(fillOrder > 0 && HistoryOrderSelect(fillOrder))
           {
            long fillType = HistoryOrderGetInteger(fillOrder, ORDER_TYPE);
            wasPendingFill = (fillType == ORDER_TYPE_BUY_LIMIT || fillType == ORDER_TYPE_SELL_LIMIT);
           }
         if(wasPendingFill) g_diagnostics.RecordPendingFilled();
         long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
         double openPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         double tp1 = 0.0, tp2 = 0.0;
         double positionSL = 0.0;
         if(PositionSelectByTicket(trans.position))
            positionSL = PositionGetDouble(POSITION_SL);
         double initialRisk = MathAbs(openPrice - positionSL);
         double tp1PctFill = 0.0, tp2PctFill = 0.0;
         double serverTPFill = 0.0;
         if(IsStructuralExitMode())
           {
            int digitsFill = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
            double pipFill = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * GetPipFactor(Symbol());
            double serverTP = 0.0;
            bool isBuyFill = (dealType == DEAL_TYPE_BUY);
            ENUM_ZONE_TYPE sideFill = isBuyFill ? ZONE_DEMAND : ZONE_SUPPLY;
            PlanStructuralTP(openPrice, isBuyFill, sideFill, pipFill, digitsFill,
                             serverTP, tp1, tp2, tp1PctFill, tp2PctFill, initialRisk);
            double posLots = PositionSelectByTicket(trans.position) ? PositionGetDouble(POSITION_VOLUME) : 0.0;
            double minLot = EffectiveBrokerMinLot(Symbol());
            double half   = g_risk.RoundLotToStep(posLots * 0.5);
            if(tp1PctFill > 0.0 && (half < minLot || (posLots - half) < minLot))
              { tp1 = 0.0; tp1PctFill = 0.0; }
            tp2 = 0.0;
            tp2PctFill = 0.0;
            serverTPFill = serverTP;
            if(serverTPFill > 0.0)
               g_orders.ApplyServerTP(trans.position, serverTPFill);
           }
         else if(positionSL > 0.0 && positionSL < openPrice && initialRisk > 0.0 && dealType == DEAL_TYPE_BUY)
           {
            tp1 = openPrice + initialRisk * (InpExitMode == EXIT_FIXED_RR ? InpFixedRR : InpTP1RR);
            tp2 = openPrice + initialRisk * (InpExitMode == EXIT_FIXED_RR ? InpFixedRR : InpTP2RR);
            tp1PctFill = (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP1ClosePct);
            tp2PctFill = (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP2ClosePct);
           }
         else if(positionSL > openPrice && initialRisk > 0.0 && dealType == DEAL_TYPE_SELL)
           {
            tp1 = openPrice - initialRisk * (InpExitMode == EXIT_FIXED_RR ? InpFixedRR : InpTP1RR);
            tp2 = openPrice - initialRisk * (InpExitMode == EXIT_FIXED_RR ? InpFixedRR : InpTP2RR);
            tp1PctFill = (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP1ClosePct);
            tp2PctFill = (InpExitMode == EXIT_FIXED_RR ? 0.0 : InpTP2ClosePct);
           }
          if(tp1 > 0.0 || IsStructuralExitMode())
            {
             ENUM_TARGET_SOURCE fillSource = TARGET_NONE;
             if(IsStructuralExitMode())
                fillSource = (g_lastPlanTargetSource != TARGET_NONE)
                             ? g_lastPlanTargetSource : TARGET_EMERGENCY_RR;
             g_orders.RegisterNewTrack(trans.position, tp1, tp2, bIdxFromComment,
                                       tp1PctFill, tp2PctFill,
                                       setupEventFromComment, brainEvidenceWeight,
                                       serverTPFill, fillSource);
             g_orders.SetTrackAttribution(trans.position, setupFromComment, gradeFromComment);
             g_orders.RecalcTrackFromFill(trans.position, openPrice, positionSL);
             double trackOpen = 0.0, trackLots = 0.0, trackRiskPrice = 0.0, trackRiskMoney = 0.0;
             double trackMFE = 0.0, trackMAE = 0.0, trackSpread = 0.0;
             int trackType = -1;
             if(!g_orders.GetTrackLearningState(trans.position, trackOpen, trackType, trackLots,
                                                 trackRiskPrice, trackRiskMoney, trackMFE, trackMAE, trackSpread))
                Print("[YANSTD TRACK_REGISTER_FAIL] Position=", trans.position,
                      " | Deal=", dealTicket, " | Comment=", comm);
            }
          else if(entry == DEAL_ENTRY_IN)
            {
             Print("[YANSTD TRACK_REGISTER_SKIP] Position=", trans.position,
                   " | Deal=", dealTicket, " | Setup=", setupFromComment,
                   " | Comment=", comm);
            }
          bool fromMarketOrder = false;
          ulong originOrder = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
          if(originOrder > 0 && HistoryOrderSelect(originOrder))
            {
             long originType = HistoryOrderGetInteger(originOrder, ORDER_TYPE);
             fromMarketOrder = (originType == ORDER_TYPE_BUY || originType == ORDER_TYPE_SELL);
            }
          if(!fromMarketOrder && setupFromComment >= 0 && setupFromComment < ENTRY_VARIANT_COUNT)
            {
             ENUM_ZONE_TYPE filledZoneType = (dealType == DEAL_TYPE_BUY) ? ZONE_DEMAND : ZONE_SUPPLY;
             bool eventMatched = g_signal.SetMatchingPOIEventTriggered(filledZoneType,
                                                setupEventFromComment,
                                                (ENUM_SMC_ENTRY_TYPE)setupFromComment,
                                                g_effectiveMaxPositions);
             if(!eventMatched)
                g_signal.SetMatchingPOILayerTriggered(filledZoneType, openPrice,
                                                   (ENUM_SMC_ENTRY_TYPE)setupFromComment, g_effectiveMaxPositions);
            }
          ReconcilePOIPendingFlags();
         }

      // Closed-trade attribution is independent of whether SmartBrain learning
      // is enabled. Strict validation is intentionally read-only, but its BUY /
      // SELL / session / variant / IS-OOS statistics must still be populated.
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
        {
             double initialOpen = 0.0, initialLots = 0.0, initialRiskPrice = 0.0, initialRiskMoney = 0.0;
             double maxFavorableR = 0.0, maxAdverseR = 0.0, maxSpreadPoints = 0.0;
             int initialPosType = -1;
             bool hasLearningState = g_orders.GetTrackLearningState(trans.position,
                                      initialOpen, initialPosType, initialLots, initialRiskPrice, initialRiskMoney,
                                      maxFavorableR, maxAdverseR, maxSpreadPoints);
             // A position is allowed to teach the Brain only while its original
             // management track still exists.  The final exit callback consumes
             // and removes that track below.  Any later DEAL_ADD callback for the
             // same position (commission adjustment, OUT_BY companion deal, or
             // broker-side split execution) therefore stops here instead of
             // reconstructing a second observation with default risk/weight.
             // This keeps one position == one TAKE observation.
             if(!hasLearningState)
               {
                // A broker-side restart or an older track-file version can leave
                // an exit without an in-memory management track. Do not abort
                // lifecycle/statistics processing; continue with zero-R fallback
                // attribution and skip Brain learning below.
                Print("[YANSTD TRACK] Exit has no management track; statistics will use zero-R fallback | Position=",
                      trans.position, " | Deal=", dealTicket);
               }
             if(hasLearningState && initialRiskPrice > 0.0)
               {
                double dealExitPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                double dealMoveR = (initialPosType == POSITION_TYPE_BUY)
                                   ? (dealExitPrice - initialOpen) / initialRiskPrice
                                   : (initialOpen - dealExitPrice) / initialRiskPrice;
                maxFavorableR = MathMax(maxFavorableR, MathMax(0.0, dealMoveR));
                maxAdverseR   = MathMax(maxAdverseR, MathMax(0.0, -dealMoveR));
                g_orders.UpdateTrackExcursion(trans.position, maxFavorableR, maxAdverseR, maxSpreadPoints);
               }

             // Partial deals update excursion above, but attribution and Brain
             // learning occur exactly once at final close.
             if(PositionSelectByTicket(trans.position)) return;

             ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
              int bIdx = hasLearningState ? g_orders.GetTrackBrainBucket(trans.position) : setupFromComment;
              ulong setupEventId = hasLearningState ? g_orders.GetTrackSetupEventId(trans.position) : setupEventFromComment;
              double evidenceWeight = hasLearningState ? g_orders.GetTrackBrainEvidenceWeight(trans.position) : brainEvidenceWeight;
             double positionProfit = 0.0;
             bool currentExitDealAdded = false;

            if(HistorySelectByPosition(positionId))
              {
               int deals = HistoryDealsTotal();
               for(int i = 0; i < deals; i++)
                 {
                  ulong d = HistoryDealGetTicket(i);
                   if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID) != positionId) continue;
                   if(HistoryDealGetInteger(d, DEAL_MAGIC) != (long)InpMagicNumber) continue;
                   positionProfit += HistoryDealGetDouble(d, DEAL_PROFIT)
                                   + HistoryDealGetDouble(d, DEAL_SWAP)
                                   + HistoryDealGetDouble(d, DEAL_COMMISSION);
                   if(d == dealTicket) currentExitDealAdded = true;
                   if(bIdx < 0)
                    {
                     string dc = HistoryDealGetString(d, DEAL_COMMENT);
                     int fb = StringFind(dc, "_B");
                     if(fb < 0) fb = StringFind(dc, "SMC_B");
                     if(fb >= 0)
                       {
                        int bStart = (StringFind(dc, "SMC_B") == fb) ? fb + 5 : fb + 2;
                        bIdx = DecodeBase36Signed(dc, bStart);
                       }
                  }
              }

             // On very fast scalps an SL/TP can close in the same server second
             // as the entry. The DEAL_ADD callback may then arrive before that
             // exit appears in HistoryDealsTotal(), even though dealTicket is
             // already readable. Add it directly once so Brain never records a
             // real win/loss as $0.00.
             if(!currentExitDealAdded)
                positionProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                                + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                                + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
              }

             double netR = (initialRiskMoney > 0.0) ? positionProfit / initialRiskMoney : 0.0;
             int closedDirection = (initialPosType >= POSITION_TYPE_BUY && initialPosType <= POSITION_TYPE_SELL)
                                   ? initialPosType
                                   : ((HistoryDealGetInteger(dealTicket, DEAL_TYPE) == DEAL_TYPE_SELL)
                                      ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
             datetime closedUTC = g_session.ConvertServerToUTC(
                                      (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME));
             ENUM_SESSION_TYPE closedSession = g_session.GetSessionAtUTC(closedUTC);
             // Record directional/session/year/OOS attribution even when the
             // comment or management track has no valid Brain bucket.
             int closedVariant = setupFromComment;
             int closedGrade = gradeFromComment;
             int trackVariant = -1, trackGrade = -1;
             if(g_orders.GetTrackAttribution(trans.position, trackVariant, trackGrade))
               {
                if(trackVariant >= 0) closedVariant = trackVariant;
                if(trackGrade >= 0) closedGrade = trackGrade;
               }
             g_diagnostics.RecordClosedTrade(positionProfit, netR, closedDirection,
                                             closedVariant, closedSession, closedUTC,
                                             closedGrade);
             // Unconditional research telemetry: emitted once at final close even
             // when Brain learning is disabled, so DEV/validation attribution can
             // reconstruct risk-normalized performance and excursions.
             Print("[YANSTD TRADE_RESULT] position=", trans.position,
                   " | deal=", dealTicket,
                   " | initialVolume=", DoubleToString(initialLots, 2),
                   " | initialRiskPrice=", DoubleToString(initialRiskPrice, 8),
                   " | initialRiskMoney=", DoubleToString(initialRiskMoney, 2),
                   " | NetR=", DoubleToString(netR, 6),
                   " | MFE=", DoubleToString(maxFavorableR, 6), "R",
                   " | MAE=", DoubleToString(maxAdverseR, 6), "R",
                   " | maxSpreadPoints=", DoubleToString(maxSpreadPoints, 2));
             if(bIdx >= 0 && InpUseSmartBrain && g_brain.IsLearningEnabled())
               {
                // A sub-cent floating-point residue is a true flat result, not
                // evidence for either the win or loss side of the bucket.
                if(MathAbs(positionProfit) < 0.005)
                  {
                   Print("YANSTD SmartBrain: Neutral closed position ignored by win/loss statistics | Pattern #", bIdx,
                         " | Result: FLAT $0.00",
                         " | NetR=", DoubleToString(netR, 2),
                         " | MFE=", DoubleToString(maxFavorableR, 2), "R",
                         " | MAE=", DoubleToString(maxAdverseR, 2), "R");
                  }
                else
                  {
                    ulong observationKey = (setupEventId > 0) ? setupEventId : positionId;
                    bool learned = g_brain.RecordTradeResult(bIdx, positionProfit, (positionProfit > 0.0),
                                                              netR, maxFavorableR, maxAdverseR,
                                                              observationKey, evidenceWeight);
                    if(learned)
                     Print("YANSTD SmartBrain: Learned closed position | Pattern #", bIdx,
                          " | SetupEvent=", observationKey,
                          " | EvidenceWeight=", DoubleToString(evidenceWeight, 3),
                          " | Result: ", (positionProfit > 0 ? "WIN +$" : "LOSS -$"), DoubleToString(MathAbs(positionProfit), 2),
                         " | NetR=", DoubleToString(netR, 2),
                         " | MFE=", DoubleToString(maxFavorableR, 2), "R",
                         " | MAE=", DoubleToString(maxAdverseR, 2), "R");
                    else
                     Print("YANSTD SmartBrain: Duplicate setup-event ignored | Pattern #", bIdx,
                           " | SetupEvent=", observationKey);
                  }
               }
             g_orders.RemoveTrack(trans.position);
            }
        }
  }

double OnTester()
  {
   double netProfit      = TesterStatistics(STAT_PROFIT);
   double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
   double trades         = TesterStatistics(STAT_TRADES);

   if(trades <= 0.0 || netProfit <= 0.0) return 0.0;

   double sampleWeight = MathMin(1.0, trades / 30.0); // full weight from 30 trades up
   double score = netProfit * MathMax(0.0, recoveryFactor) * MathSqrt(trades) * sampleWeight;
   return score;
  }
//+------------------------------------------------------------------+
