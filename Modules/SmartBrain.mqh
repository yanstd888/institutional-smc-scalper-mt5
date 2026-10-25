//+------------------------------------------------------------------+
//|                                                   SmartBrain.mqh |
//|                      YANSTD EA — AI Memory & Reinforcement Logic |
//|                      + Integrated Machine Learning Scoring Core  |
//+------------------------------------------------------------------+
#ifndef YANSTD_SMARTBRAIN_MQH
#define YANSTD_SMARTBRAIN_MQH

#include "Defines.mqh"

// Full signature matrix:
// 4 sessions * 2 directions * 2 POI profiles * 3 OB depths *
// 2 FVG states * 4 Fibonacci states * 3 zone sizes * 3 trend strengths.
// The CE-only FVG and 0.618/0.705/0.786 Fib model removes unreachable states,
// reducing the exact matrix from 8,640 to 3,456 buckets.
// Day-of-week carried no structural hypothesis the session axis does not
// already capture, yet it split every state's evidence 5 ways, pushing most
// EXACT buckets below AI_MIN_DECISION_SAMPLE and forcing decisions down to
// coarser hierarchy levels. Fewer, denser buckets = faster, less noisy learning.
#define AI_TOTAL_BUCKETS 3456
#define AI_LEGACY_TOTAL_BUCKETS 43200
#define AI_CORE_BUCKETS 96
#define AI_MITIGATION_BUCKETS 24
#define AI_PROFILE_BUCKETS 4
#define AI_MIN_DECISION_SAMPLE 1
// Minimum real, decayed evidence before negative Brain statistics may reduce
// sizing. This never grants entry-veto authority: MSNR+SMC always owns entry.
#define AI_MIN_SIZING_EVIDENCE 6
#define AI_MIN_HARD_OVERLAY_EVIDENCE 10
#define AI_FILE_MAGIC 1497452115
#define AI_FILE_VERSION 1370
#define AI_STRATEGY_FINGERPRINT 2096183460
#define AI_STRATEGY_NAMESPACE "HYBRID_MSNRSMC_QRL_V17_OB15_OB45"
// AUDIT FIX (#8): AI_MAX_SHADOW_TRADES removed along with the dead
// shadow-trade subsystem it sized.
#define AI_V3_FILE_VERSION 1000
#define AI_V3_FINGERPRINT 1714437891
#define AI_V4_FILE_VERSION 1100
#define AI_V4_FINGERPRINT 1843379207
#define AI_JOURNAL_MAGIC 1246645297
#define AI_JOURNAL_VERSION 2
#define AI_JOURNAL_HEADER_BYTES 16
#define AI_JOURNAL_RECORD_BYTES 88
#define AI_BLOOM_ROTATE_INSERTS 64
#define AI_SNAPSHOT_EVENT_INTERVAL 50
#define AI_SNAPSHOT_MIN_INTERVAL_MS 1800000
#define AI_ARCHIVE_INTERVAL_DAYS 7
#define AI_ARCHIVE_SLOTS 8
#define AI_JOURNAL_MAX_SEGMENTS 12


struct SPatternBucket
{
   long   wins;
   long   losses;
   double totalProfit;
   double totalNetR;
   double totalMFER;
   double totalMAER;
   long   hit1R;
   long   hit15R;
   long   hit2R;
   long   hit25R;
   long   hit3R;
   double confidence;    // 0.0 - 100.0%
   bool   isBanned;      // Auto-banned if consistency < threshold
   datetime lastUpdateTime; // bucket-specific recency for confidence decay
   ulong  lastObservationKey; // legacy/debug identity of the newest accepted setup
   double winWeight;          // independent evidence; matrix siblings are fractional
   double lossWeight;
   // Native tabular Q(s,a).  The existing 8,640-dimensional pattern index is
   // the state; TAKE and SKIP are the two explicit actions.
   double qTake;
   double qSkip;
   double qTakeWeight;
   double qSkipWeight;
   long   qTakeUpdates;
   long   qSkipUpdates;
   ulong  seenBloom0;         // persistent setup-event dedupe (256-bit Bloom filter)
   ulong  seenBloom1;
   ulong  seenBloom2;
   ulong  seenBloom3;
   // Four independent 256-bit groups (1,024 bits total). At 100 unique
   // observations in one exact bucket the false-positive probability is
   // roughly 1.1%, versus roughly 40% with the old 256-bit layout.
   ulong  seenBloom4;
   ulong  seenBloom5;
   ulong  seenBloom6;
   ulong  seenBloom7;
   ulong  seenBloom8;
   ulong  seenBloom9;
   ulong  seenBloom10;
   ulong  seenBloom11;
   ulong  seenBloom12;
   ulong  seenBloom13;
   ulong  seenBloom14;
   ulong  seenBloom15;
   ulong  prevBloom0; ulong prevBloom1; ulong prevBloom2; ulong prevBloom3;
   ulong  prevBloom4; ulong prevBloom5; ulong prevBloom6; ulong prevBloom7;
   ulong  prevBloom8; ulong prevBloom9; ulong prevBloom10; ulong prevBloom11;
   ulong  prevBloom12; ulong prevBloom13; ulong prevBloom14; ulong prevBloom15;
   int    bloomInsertCount;
   long   bloomGeneration;
};

// AUDIT FIX (#8): removed dead struct SShadowTrade — was part of the
// "shadow trade" counterfactual SKIP-learning subsystem (RegisterShadowTrade,
// ProcessShadowTrades, SetCounterfactualTPRR/SetCounterfactualTP1Fraction),
// which was never called from anywhere and hardcoded shadowEnabled=false in
// Init(). Removed in full rather than left half-wired; see CHANGELOG.

struct SBrainBucketView
{
   bool     valid;         // false = no bucket cleared selection (unproven state)
   string   level;         // EXACT / CORE / MITIGATION / PROFILE / NONE
   double   confidence;    // QConfidence of the selected bucket
   int      sample;        // EffectiveBucketSample (includes qSkipWeight, which can
                           // now only come from ReplayJournal() replaying legacy
                           // SKIP records -- the live shadow-trade path that used
                           // to feed this was removed in the 2026-09-09 audit)
   double   winWeight;     // Lot-ladder key: decayed real wins per setup
   double   realEvidence;  // decayed win+loss weight, qSkipWeight excluded
   double   avgNetR;       // realised expectancy in R
   double   avgMFER;       // Reward potential: average MFE in R
   bool     isBanned;      // quarantined by RecalculateBucket
   double   qTake;         // learned TAKE value; sizing context only
   double   qSkip;         // learned SKIP value; sizing context only
   double   qEvidence;     // decayed TAKE+SKIP evidence
};

// Neutral "Brain has no opinion" snapshot. Callers that may skip the lookup
// entirely (InpUseSmartBrain=false) must still start from a defined state.
void BrainViewReset(SBrainBucketView &view)
{
   view.valid        = false;
   view.level        = "NONE";
   view.confidence   = 50.0;
   view.sample       = 0;
   view.winWeight    = 0.0;
   view.realEvidence = 0.0;
   view.avgNetR      = 0.0;
   view.avgMFER      = 0.0;
   view.isBanned     = false;
   view.qTake        = 0.0;
   view.qSkip        = 0.0;
   view.qEvidence    = 0.0;
}

// Brain is a risk overlay only: it never vetoes a structurally valid setup and
// never increases risk. Negative expectancy needs ten decayed real-evidence
// units before the 0.50x reduction becomes available.
double BrainRiskOverlayMultiplier(const SBrainBucketView &view)
{
   if(!view.valid || view.realEvidence < (double)AI_MIN_HARD_OVERLAY_EVIDENCE || view.avgNetR >= -0.10)
      return 1.0;
   return 0.50;
}

double BrainLotMultiplier(double winWeight)
{
   int w = (int)MathFloor(winWeight + 1e-9);
   if(w >= 15) return 2.50;
   if(w >= 7)  return 2.00;
   if(w >= 4)  return 1.50;
   return 1.00;
}

class CSmartBrain
{
private:
   string          m_symbol;
   string          m_chartSymbol;      // OPT-A: broker symbol for market data (m_symbol is the canonical DB key)
   ENUM_TIMEFRAMES m_zoneATRTimeframe; // OPT-A: ATR timeframe for zone-size normalisation
   int             m_zoneATRPeriod;    // OPT-A: ATR period for zone-size normalisation
   // source = dataset being learned/saved; buckets = REALTICK; fallback = OHLC.
   SPatternBucket  m_sourceBuckets[AI_TOTAL_BUCKETS];
   SPatternBucket  m_fallbackBuckets[AI_TOTAL_BUCKETS];
   SPatternBucket  m_buckets[AI_TOTAL_BUCKETS];
   SPatternBucket  m_coreBuckets[AI_CORE_BUCKETS];
   SPatternBucket  m_mitigationBuckets[AI_MITIGATION_BUCKETS];
   SPatternBucket  m_profileBuckets[AI_PROFILE_BUCKETS];
   SPatternBucket  m_realTickCoreBuckets[AI_CORE_BUCKETS];
   SPatternBucket  m_realTickMitigationBuckets[AI_MITIGATION_BUCKETS];
   SPatternBucket  m_realTickProfileBuckets[AI_PROFILE_BUCKETS];
   SPatternBucket  m_ohlcCoreBuckets[AI_CORE_BUCKETS];
   SPatternBucket  m_ohlcMitigationBuckets[AI_MITIGATION_BUCKETS];
   SPatternBucket  m_ohlcProfileBuckets[AI_PROFILE_BUCKETS];
   double          m_minConfidence;
   bool            m_learningEnabled;
   string          m_brainFile;
   string          m_liveFile;
   string          m_realTickFile;
   string          m_ohlcFile;
   string          m_sourceLabel;
   bool            m_useFallback;
   long            m_totalTradesRecorded;
   long            m_lastArchivePeriod;
   datetime        m_learnedMinTime;   // C6: earliest event time the active source has learned from
   datetime        m_learnedMaxTime;   // C6: latest event time the active source has learned from
   double          m_decayHalfLifeDays;
   double          m_qAlpha;
   double          m_qGamma;
   int             m_qMinUpdates;
   double          m_minRewardRisk;
   double          m_qRewardClip;
   // AUDIT FIX (#8): removed m_counterfactualTPRR, m_counterfactualTP1Frac,
   // m_shadowEnabled, m_shadows[], m_shadowCount — dead shadow-trade
   // (counterfactual SKIP-learning) state, never enabled or read anywhere.
   string          m_dataRoot;
   double          m_liveWeight;
   double          m_realTickWeight;
   double          m_ohlcWeight;
   ulong           m_bucketEpoch;
   bool            m_selCacheValid;
   int             m_selCacheIdx;
   datetime        m_selCacheTime;
   ulong           m_selCacheEpoch;
   bool            m_selCacheResult;
   SPatternBucket  m_selCacheBucket;
   string          m_selCacheLevel;
   int             m_lockHandle;
   string          m_lockFile;
   bool            m_journalEnabled;
   ulong           m_journalSegmentBytes;
   string          m_journalDir;
   string          m_journalPrefix;
   int             m_journalSegment;
   long            m_journalRecordsApplied;

   // AUDIT FIX (#8): removed dead RemoveShadowAt() helper along with the
   // rest of the shadow-trade subsystem (see struct SShadowTrade removal
   // above).

   void ResetBucket(SPatternBucket &bucket)
   {
      bucket.wins        = 0;
      bucket.losses      = 0;
      bucket.totalProfit = 0.0;
      bucket.totalNetR   = 0.0;
      bucket.totalMFER   = 0.0;
      bucket.totalMAER   = 0.0;
      bucket.hit1R       = 0;
      bucket.hit15R      = 0;
      bucket.hit2R       = 0;
      bucket.hit25R      = 0;
      bucket.hit3R       = 0;
      bucket.confidence  = 50.0;
      bucket.isBanned    = false;
      bucket.lastUpdateTime = 0;
      bucket.lastObservationKey = 0;
      bucket.winWeight = 0.0;
      bucket.lossWeight = 0.0;
      bucket.qTake = 0.0;
      bucket.qSkip = 0.0;
      bucket.qTakeWeight = 0.0;
      bucket.qSkipWeight = 0.0;
      bucket.qTakeUpdates = 0;
      bucket.qSkipUpdates = 0;
      bucket.seenBloom0 = 0;
      bucket.seenBloom1 = 0;
      bucket.seenBloom2 = 0;
      bucket.seenBloom3 = 0;
      bucket.seenBloom4 = 0;
      bucket.seenBloom5 = 0;
      bucket.seenBloom6 = 0;
      bucket.seenBloom7 = 0;
      bucket.seenBloom8 = 0;
      bucket.seenBloom9 = 0;
      bucket.seenBloom10 = 0;
      bucket.seenBloom11 = 0;
      bucket.seenBloom12 = 0;
      bucket.seenBloom13 = 0;
      bucket.seenBloom14 = 0;
      bucket.seenBloom15 = 0;
      bucket.prevBloom0 = 0; bucket.prevBloom1 = 0; bucket.prevBloom2 = 0; bucket.prevBloom3 = 0;
      bucket.prevBloom4 = 0; bucket.prevBloom5 = 0; bucket.prevBloom6 = 0; bucket.prevBloom7 = 0;
      bucket.prevBloom8 = 0; bucket.prevBloom9 = 0; bucket.prevBloom10 = 0; bucket.prevBloom11 = 0;
      bucket.prevBloom12 = 0; bucket.prevBloom13 = 0; bucket.prevBloom14 = 0; bucket.prevBloom15 = 0;
      bucket.bloomInsertCount = 0;
      bucket.bloomGeneration = 0;
   }

   void ResetBucketArray(SPatternBucket &buckets[])
   {
      int size = ArraySize(buckets);
      for(int i = 0; i < size; i++) ResetBucket(buckets[i]);
   }

   //--- C6: learned date-range fingerprint (in-sample leakage guard) ----------
   // Stored in a small SIDECAR file next to each dataset (non-breaking: the main
   // snapshot format and existing learned data are untouched). Records the
   // [min,max] event time the dataset has learned from. A backtest whose
   // simulated clock starts BEFORE the dataset's max learned time is reading
   // knowledge of its own future; strict read-only validation refuses such a
   // dataset so reported performance is genuinely out-of-sample.
   #define AI_RANGE_MAGIC 0x59524E47 // 'YRNG'
   string RangeFileFor(string datasetFile) { return datasetFile + ".range.bin"; }

   void TouchLearnedRange(datetime t)
   {
      if(t <= 0) return;
      if(m_learnedMinTime == 0 || t < m_learnedMinTime) m_learnedMinTime = t;
      if(t > m_learnedMaxTime) m_learnedMaxTime = t;
   }

   bool LoadLearnedRange(string datasetFile, datetime &minT, datetime &maxT)
   {
      minT = 0; maxT = 0;
      int h = FileOpen(RangeFileFor(datasetFile), FILE_READ | FILE_BIN | FILE_COMMON);
      if(h == INVALID_HANDLE) return false;
      int magic = FileReadInteger(h);
      long a = FileReadLong(h);
      long b = FileReadLong(h);
      FileClose(h);
      if(magic != AI_RANGE_MAGIC) return false;
      minT = (datetime)a; maxT = (datetime)b;
      return (maxT > 0);
   }

   bool SaveLearnedRange(string datasetFile)
   {
      if(m_learnedMaxTime <= 0) return true; // nothing learned yet
      string tmp = RangeFileFor(datasetFile) + ".tmp";
      int h = FileOpen(tmp, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(h == INVALID_HANDLE) return false;
      FileWriteInteger(h, AI_RANGE_MAGIC);
      FileWriteLong(h, (long)m_learnedMinTime);
      FileWriteLong(h, (long)m_learnedMaxTime);
      FileFlush(h); FileClose(h);
      if(!FileMove(tmp, FILE_COMMON, RangeFileFor(datasetFile), FILE_COMMON | FILE_REWRITE))
        { FileDelete(tmp, FILE_COMMON); return false; }
      return true;
     }

   void RotateDatedSnapshot()
     {
      if(MQLInfoInteger(MQL_TESTER) || m_brainFile == "" ||
         !FileIsExist(m_brainFile, FILE_COMMON)) return;
      long dayKey = (long)TimeCurrent() / 86400;
      long period = dayKey / AI_ARCHIVE_INTERVAL_DAYS;
      if(period == m_lastArchivePeriod) return;
      m_lastArchivePeriod = period;

      int slot = (int)(period % AI_ARCHIVE_SLOTS);
      string match = "";
      long search = FileFindFirst(m_brainFile + ".snapshot" + IntegerToString(slot) + "_*",
                                  match, FILE_COMMON);
      if(search != INVALID_HANDLE)
        {
         do { FileDelete(match, FILE_COMMON); }
         while(FileFindNext(search, match));
         FileFindClose(search);
        }
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      string dated = m_brainFile + ".snapshot" + IntegerToString(slot) + "_" +
                     StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
      if(!FileCopy(m_brainFile, FILE_COMMON, dated, FILE_COMMON | FILE_REWRITE))
         LogSystemWarning("SmartBrain", "RotateDatedSnapshot",
                          "Dated snapshot could not be created. Error=" +
                          IntegerToString(GetLastError()));
     }

   // Returns true when the dataset was learned from data that overlaps the
   // current (simulated) clock, i.e. loading it would leak future knowledge.
   bool DatasetOverlapsCurrentClock(string datasetFile, datetime &learnedMax)
   {
      datetime mn = 0; learnedMax = 0;
      if(!LoadLearnedRange(datasetFile, mn, learnedMax)) return false;
      return (learnedMax > 0 && TimeCurrent() <= learnedMax);
   }

   long BucketSample(const SPatternBucket &bucket)
   {
      return bucket.wins + bucket.losses;
   }

   double ClipReward(double reward)
   {
      return MathMax(-m_qRewardClip, MathMin(m_qRewardClip, reward));
   }

   void UpdateQ(SPatternBucket &bucket, bool takeAction, double reward, double evidenceWeight)
   {
      double w = MathMax(0.01, MathMin(1.0, evidenceWeight));
      double clipped = ClipReward(reward);
      // A completed trade is a terminal transition. Therefore max Q(s',a') is
      // zero by definition; gamma remains explicit for future non-terminal
      // state transitions without incorrectly bootstrapping from the same state.
      double terminalNextQ = 0.0;
      double window = (m_qAlpha > 0.0) ? (1.0 / m_qAlpha) : 8.0;
      if(takeAction)
      {
         bucket.qTakeWeight += w;
         double denom = MathMin(bucket.qTakeWeight, window);
         double step  = MathMin(1.0, w / MathMax(denom, 1e-9));
         bucket.qTake += step * (clipped + m_qGamma * terminalNextQ - bucket.qTake);
         bucket.qTakeUpdates++;
      }
      else
      {
         bucket.qSkipWeight += w;
         double denom = MathMin(bucket.qSkipWeight, window);
         double step  = MathMin(1.0, w / MathMax(denom, 1e-9));
         bucket.qSkip += step * (clipped + m_qGamma * terminalNextQ - bucket.qSkip);
         bucket.qSkipUpdates++;
      }
      InvalidateBucketCache(); // #15
   }

   double QConfidence(const SPatternBucket &bucket)
   {
      // Apply the same half-life to Q evidence and Q advantage. Previously
      // only win-rate/sample eligibility decayed, so an old Q veto stayed at
      // full strength and then disappeared abruptly below the sample floor.
      double decay = DecayWeight(bucket);
      double evidence = (bucket.qTakeWeight + bucket.qSkipWeight) * decay;
      if(evidence <= 0.0) return bucket.confidence;
      double advantage = (bucket.qTake - bucket.qSkip) * decay;
      double logistic = 1.0 / (1.0 + MathExp(-2.0 * advantage));
      double qConf = 100.0 * logistic;
      double blend = MathMin(1.0, evidence / MathMax(1.0, (double)m_qMinUpdates));
      return bucket.confidence * (1.0 - blend) + qConf * blend;
   }

   double BucketEvidence(const SPatternBucket &bucket)
   {
      double weighted = bucket.winWeight + bucket.lossWeight;
      return (weighted > 0.0) ? weighted : (double)BucketSample(bucket);
   }

   ulong MixObservationKey(ulong key)
   {
      key ^= (key >> 30);
      key *= (ulong)0xbf58476d1ce4e5b9;
      key ^= (key >> 27);
      key *= (ulong)0x94d049bb133111eb;
      key ^= (key >> 31);
      return key;
   }

   ulong ActionKey(ulong key, int action)
   {
      return (action == 1) ? key : (key ^ (ulong)0x9E3779B97F4A7C15);
   }

   ulong GetBloomWord(const SPatternBucket &bucket, int word)
   {
      switch(word)
      {
         case 0: return bucket.seenBloom0;   case 1: return bucket.seenBloom1;
         case 2: return bucket.seenBloom2;   case 3: return bucket.seenBloom3;
         case 4: return bucket.seenBloom4;   case 5: return bucket.seenBloom5;
         case 6: return bucket.seenBloom6;   case 7: return bucket.seenBloom7;
         case 8: return bucket.seenBloom8;   case 9: return bucket.seenBloom9;
         case 10: return bucket.seenBloom10; case 11: return bucket.seenBloom11;
         case 12: return bucket.seenBloom12; case 13: return bucket.seenBloom13;
         case 14: return bucket.seenBloom14; case 15: return bucket.seenBloom15;
      }
      return 0;
   }

   ulong GetPreviousBloomWord(const SPatternBucket &bucket, int word)
   {
      switch(word)
      {
         case 0: return bucket.prevBloom0;   case 1: return bucket.prevBloom1;
         case 2: return bucket.prevBloom2;   case 3: return bucket.prevBloom3;
         case 4: return bucket.prevBloom4;   case 5: return bucket.prevBloom5;
         case 6: return bucket.prevBloom6;   case 7: return bucket.prevBloom7;
         case 8: return bucket.prevBloom8;   case 9: return bucket.prevBloom9;
         case 10: return bucket.prevBloom10; case 11: return bucket.prevBloom11;
         case 12: return bucket.prevBloom12; case 13: return bucket.prevBloom13;
         case 14: return bucket.prevBloom14; case 15: return bucket.prevBloom15;
      }
      return 0;
   }

   void RotateBloom(SPatternBucket &bucket)
   {
      bucket.prevBloom0 = bucket.seenBloom0; bucket.prevBloom1 = bucket.seenBloom1;
      bucket.prevBloom2 = bucket.seenBloom2; bucket.prevBloom3 = bucket.seenBloom3;
      bucket.prevBloom4 = bucket.seenBloom4; bucket.prevBloom5 = bucket.seenBloom5;
      bucket.prevBloom6 = bucket.seenBloom6; bucket.prevBloom7 = bucket.seenBloom7;
      bucket.prevBloom8 = bucket.seenBloom8; bucket.prevBloom9 = bucket.seenBloom9;
      bucket.prevBloom10 = bucket.seenBloom10; bucket.prevBloom11 = bucket.seenBloom11;
      bucket.prevBloom12 = bucket.seenBloom12; bucket.prevBloom13 = bucket.seenBloom13;
      bucket.prevBloom14 = bucket.seenBloom14; bucket.prevBloom15 = bucket.seenBloom15;
      bucket.seenBloom0 = 0; bucket.seenBloom1 = 0; bucket.seenBloom2 = 0; bucket.seenBloom3 = 0;
      bucket.seenBloom4 = 0; bucket.seenBloom5 = 0; bucket.seenBloom6 = 0; bucket.seenBloom7 = 0;
      bucket.seenBloom8 = 0; bucket.seenBloom9 = 0; bucket.seenBloom10 = 0; bucket.seenBloom11 = 0;
      bucket.seenBloom12 = 0; bucket.seenBloom13 = 0; bucket.seenBloom14 = 0; bucket.seenBloom15 = 0;
      bucket.bloomInsertCount = 0;
      bucket.bloomGeneration++;
   }

   void SetBloomBit(SPatternBucket &bucket, int word, int bit)
   {
      ulong mask = ((ulong)1 << bit);
      switch(word)
      {
         case 0: bucket.seenBloom0 |= mask; break;   case 1: bucket.seenBloom1 |= mask; break;
         case 2: bucket.seenBloom2 |= mask; break;   case 3: bucket.seenBloom3 |= mask; break;
         case 4: bucket.seenBloom4 |= mask; break;   case 5: bucket.seenBloom5 |= mask; break;
         case 6: bucket.seenBloom6 |= mask; break;   case 7: bucket.seenBloom7 |= mask; break;
         case 8: bucket.seenBloom8 |= mask; break;   case 9: bucket.seenBloom9 |= mask; break;
         case 10: bucket.seenBloom10 |= mask; break; case 11: bucket.seenBloom11 |= mask; break;
         case 12: bucket.seenBloom12 |= mask; break; case 13: bucket.seenBloom13 |= mask; break;
         case 14: bucket.seenBloom14 |= mask; break; case 15: bucket.seenBloom15 |= mask; break;
      }
   }

   bool ObservationSeen(const SPatternBucket &bucket, ulong key)
   {
      if(key == 0) return false;
      ulong h1 = MixObservationKey(key);
      ulong h2 = MixObservationKey(key ^ (ulong)0x9e3779b97f4a7c15);
      int p0 = (int)(h1 & 255), p1 = (int)((h1 >> 16) & 255);
      int p2 = (int)(h2 & 255), p3 = (int)((h2 >> 16) & 255);
      bool currentSeen = ((GetBloomWord(bucket,      p0 / 64) & ((ulong)1 << (p0 & 63))) != 0 &&
              (GetBloomWord(bucket,  4 + p1 / 64) & ((ulong)1 << (p1 & 63))) != 0 &&
              (GetBloomWord(bucket,  8 + p2 / 64) & ((ulong)1 << (p2 & 63))) != 0 &&
              (GetBloomWord(bucket, 12 + p3 / 64) & ((ulong)1 << (p3 & 63))) != 0);
      bool previousSeen = ((GetPreviousBloomWord(bucket,      p0 / 64) & ((ulong)1 << (p0 & 63))) != 0 &&
              (GetPreviousBloomWord(bucket,  4 + p1 / 64) & ((ulong)1 << (p1 & 63))) != 0 &&
              (GetPreviousBloomWord(bucket,  8 + p2 / 64) & ((ulong)1 << (p2 & 63))) != 0 &&
              (GetPreviousBloomWord(bucket, 12 + p3 / 64) & ((ulong)1 << (p3 & 63))) != 0);
      return currentSeen || previousSeen;
   }

   void MarkObservationSeen(SPatternBucket &bucket, ulong key)
   {
      if(key == 0) return;
      if(bucket.bloomInsertCount >= AI_BLOOM_ROTATE_INSERTS) RotateBloom(bucket);
      ulong h1 = MixObservationKey(key);
      ulong h2 = MixObservationKey(key ^ (ulong)0x9e3779b97f4a7c15);
      int p0 = (int)(h1 & 255), p1 = (int)((h1 >> 16) & 255);
      int p2 = (int)(h2 & 255), p3 = (int)((h2 >> 16) & 255);
      SetBloomBit(bucket,      p0 / 64, p0 & 63);
      SetBloomBit(bucket,  4 + p1 / 64, p1 & 63);
      SetBloomBit(bucket,  8 + p2 / 64, p2 & 63);
      SetBloomBit(bucket, 12 + p3 / 64, p3 & 63);
      bucket.bloomInsertCount++;
   }

   double DecayWeight(const SPatternBucket &bucket)
   {
      if(m_decayHalfLifeDays <= 0.0 || bucket.lastUpdateTime <= 0) return 1.0;
      long ageSeconds = (long)TimeCurrent() - (long)bucket.lastUpdateTime;
      if(ageSeconds <= 0) return 1.0;
      double ageDays = (double)ageSeconds / 86400.0;
      return MathPow(0.5, ageDays / m_decayHalfLifeDays);
   }

   int EffectiveBucketSample(const SPatternBucket &bucket)
   {
      double decisionEvidence = MathMax(BucketEvidence(bucket),
                                        bucket.qTakeWeight + bucket.qSkipWeight);
      return (int)MathFloor(decisionEvidence * DecayWeight(bucket));
   }

   void RecalculateBucket(SPatternBucket &bucket)
   {
      double sample = BucketEvidence(bucket);
      double rawConfidence = (sample > 0.0) ? (bucket.winWeight / sample) * 100.0 : 50.0;
      double weight = DecayWeight(bucket);
      bucket.confidence = 50.0 + (rawConfidence - 50.0) * weight;
      bucket.confidence = MathMax(0.0, MathMin(100.0, bucket.confidence));
      double realEvidence = sample * weight;
      double p = (sample > 0.0) ? bucket.winWeight / sample : 0.5;
      double z = 1.959963984540054;
      double wilsonUpper = 1.0;
      if(realEvidence > 0.0)
        {
         double z2 = z * z;
         double centre = p + z2 / (2.0 * realEvidence);
         double radius = z * MathSqrt((p * (1.0 - p) + z2 / (4.0 * realEvidence)) /
                                      realEvidence);
         wilsonUpper = (centre + radius) / (1.0 + z2 / realEvidence);
        }
      bool lowWinRate = (realEvidence >= 10.0 && wilsonUpper < 0.35);
      double avgNetR = (sample > 0.0) ? (bucket.totalNetR / sample) : 0.0;
      bool negativeExpectancy = (realEvidence >= 20.0 && avgNetR < -0.10);
      bucket.isBanned = (lowWinRate || negativeExpectancy);
   }

   void MergeBucket(SPatternBucket &target, const SPatternBucket &source)
   {
      target.wins        += source.wins;
      target.losses      += source.losses;
      target.totalProfit += source.totalProfit;
      target.totalNetR   += source.totalNetR;
      target.totalMFER   += source.totalMFER;
      target.totalMAER   += source.totalMAER;
      target.hit1R       += source.hit1R;
      target.hit15R      += source.hit15R;
      target.hit2R       += source.hit2R;
      target.hit25R      += source.hit25R;
      target.hit3R       += source.hit3R;
      target.winWeight   += source.winWeight;
      target.lossWeight  += source.lossWeight;
      // Q-values are merged by evidence, never added as if they were P/L.
      double takeW = target.qTakeWeight + source.qTakeWeight;
      if(takeW > 0.0)
         target.qTake = (target.qTake * target.qTakeWeight + source.qTake * source.qTakeWeight) / takeW;
      double skipW = target.qSkipWeight + source.qSkipWeight;
      if(skipW > 0.0)
         target.qSkip = (target.qSkip * target.qSkipWeight + source.qSkip * source.qSkipWeight) / skipW;
      target.qTakeWeight = takeW;
      target.qSkipWeight = skipW;
      target.qTakeUpdates += source.qTakeUpdates;
      target.qSkipUpdates += source.qSkipUpdates;
      target.seenBloom0  |= source.seenBloom0;
      target.seenBloom1  |= source.seenBloom1;
      target.seenBloom2  |= source.seenBloom2;
      target.seenBloom3  |= source.seenBloom3;
      target.seenBloom4  |= source.seenBloom4;
      target.seenBloom5  |= source.seenBloom5;
      target.seenBloom6  |= source.seenBloom6;
      target.seenBloom7  |= source.seenBloom7;
      target.seenBloom8  |= source.seenBloom8;
      target.seenBloom9  |= source.seenBloom9;
      target.seenBloom10 |= source.seenBloom10;
      target.seenBloom11 |= source.seenBloom11;
      target.seenBloom12 |= source.seenBloom12;
      target.seenBloom13 |= source.seenBloom13;
      target.seenBloom14 |= source.seenBloom14;
      target.seenBloom15 |= source.seenBloom15;
      if(source.lastUpdateTime > target.lastUpdateTime)
         target.lastUpdateTime = source.lastUpdateTime;
      if(source.lastUpdateTime >= target.lastUpdateTime && source.lastObservationKey > 0)
         target.lastObservationKey = source.lastObservationKey;
   }

   void DecodePatternIndices(int bucketIdx, int &dirIdx, int &poiIdx,
                             int &obIdx, int &fvgIdx, int &fibIdx)
   {
      int value = bucketIdx;
      value /= 3; // trend
      value /= 3; // zone size
      fibIdx = value % 4; value /= 4;
      fvgIdx = value % 2; value /= 2;
      obIdx  = value % 3; value /= 3;
      poiIdx = value % 2; value /= 2;
      dirIdx = value % 2;
   }

   void GetHierarchyIndices(int bucketIdx, int &coreIdx, int &mitigationIdx, int &profileIdx)
   {
      int dirIdx, poiIdx, obIdx, fvgIdx, fibIdx;
      DecodePatternIndices(bucketIdx, dirIdx, poiIdx, obIdx, fvgIdx, fibIdx);
      profileIdx    = dirIdx * 2 + poiIdx;
      mitigationIdx = ((profileIdx * 3 + obIdx) * 2 + fvgIdx);
      coreIdx        = mitigationIdx * 4 + fibIdx;
   }

   void RebuildHierarchyFor(SPatternBucket &exactBuckets[],
                            SPatternBucket &coreBuckets[],
                            SPatternBucket &mitigationBuckets[],
                            SPatternBucket &profileBuckets[])
   {
      for(int i = 0; i < AI_CORE_BUCKETS; i++) ResetBucket(coreBuckets[i]);
      for(int i = 0; i < AI_MITIGATION_BUCKETS; i++) ResetBucket(mitigationBuckets[i]);
      for(int i = 0; i < AI_PROFILE_BUCKETS; i++) ResetBucket(profileBuckets[i]);

      for(int i = 0; i < AI_TOTAL_BUCKETS; i++)
      {
         if(BucketEvidence(exactBuckets[i]) <= 0.0 &&
            exactBuckets[i].qTakeWeight + exactBuckets[i].qSkipWeight <= 0.0)
           {
            exactBuckets[i].confidence = 50.0;
            exactBuckets[i].isBanned   = false;
            continue;
           }
         RecalculateBucket(exactBuckets[i]);
         int coreIdx, mitigationIdx, profileIdx;
         GetHierarchyIndices(i, coreIdx, mitigationIdx, profileIdx);
         MergeBucket(coreBuckets[coreIdx], exactBuckets[i]);
         MergeBucket(mitigationBuckets[mitigationIdx], exactBuckets[i]);
         MergeBucket(profileBuckets[profileIdx], exactBuckets[i]);
      }

      for(int i = 0; i < AI_CORE_BUCKETS; i++) RecalculateBucket(coreBuckets[i]);
      for(int i = 0; i < AI_MITIGATION_BUCKETS; i++) RecalculateBucket(mitigationBuckets[i]);
      for(int i = 0; i < AI_PROFILE_BUCKETS; i++) RecalculateBucket(profileBuckets[i]);
      InvalidateBucketCache(); // #15
   }

   bool LoadDataset(string fileName, SPatternBucket &target[], long &tradeCount,
                    bool quiet = false, bool loadCheckpoint = false)
   {
      ResetBucketArray(target);
      InvalidateBucketCache(); // #15: a reload replaces the data the memo summarised
      tradeCount = 0;
      int handle = FileOpen(fileName, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE)
        {
         handle = FileOpen(fileName, FILE_READ | FILE_BIN);
        }
      if(handle == INVALID_HANDLE)
      {
         if(!quiet) Print("[YANSTD SmartBrain] No dataset found: ", fileName);
         return false;
      }

      int magic   = FileReadInteger(handle);
      int version = FileReadInteger(handle);
      int fingerprint = (version >= 900) ? FileReadInteger(handle) : 0;
      int count   = FileReadInteger(handle);
      tradeCount  = FileReadLong(handle);
      long journalCheckpoint = FileReadLong(handle);
      uint readCount = 0;
      if(magic == AI_FILE_MAGIC && version == AI_FILE_VERSION &&
         fingerprint == AI_STRATEGY_FINGERPRINT && count == AI_TOTAL_BUCKETS)
         readCount = FileReadArray(handle, target, 0, AI_TOTAL_BUCKETS);
      FileClose(handle);

      if(readCount != AI_TOTAL_BUCKETS)
      {
         ResetBucketArray(target);
         tradeCount = 0;
         LogSystemWarning("SmartBrain", "LoadDataset", "Invalid/incompatible dataset ignored: " + fileName);
         return false;
      }
      for(int i = 0; i < AI_TOTAL_BUCKETS; i++) RecalculateBucket(target[i]);
      if(loadCheckpoint) m_journalRecordsApplied = MathMax(0, journalCheckpoint);
      return true;
   }

   bool RejectLegacyDataset(string fileName, int expectVersion, int expectFingerprint,
                            string label, long &tradeCount)
   {
      tradeCount = 0;
      if(!FileIsExist(fileName, FILE_COMMON)) return false;
      int handle = FileOpen(fileName, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE) return false;
      int magic = FileReadInteger(handle);
      int version = FileReadInteger(handle);
      int fingerprint = FileReadInteger(handle);
      int count = FileReadInteger(handle);
      long trades = (long)FileReadInteger(handle);
      FileClose(handle);
      if(magic == AI_FILE_MAGIC && version == expectVersion &&
         fingerprint == expectFingerprint && count == AI_LEGACY_TOTAL_BUCKETS)
         Print("[YANSTD SmartBrain] ", label, " dataset recognised but INCOMPATIBLE with the ",
               "current bucket scheme (", AI_LEGACY_TOTAL_BUCKETS, " -> ", AI_TOTAL_BUCKETS,
               " buckets, ATR zones, no day-of-week). Not merged; learning starts fresh. File=",
               fileName, " | LegacyTrades=", trades);
      return false;
   }

   // AUDIT FIX (#10): removed LoadV3Dataset()/LoadV4Dataset() wrappers.
   // RejectLegacyDataset() always returns false by design (it recognises a
   // legacy file only to log that it is incompatible and refuse to merge
   // it), so the wrappers could never return true either -- the "migrated in
   // memory" log branch that used to wrap their call sites was unreachable
   // and implied a migration that never actually happened. Callers now
   // invoke RejectLegacyDataset() directly as the bare diagnostic it is.

   void BuildEffectiveDataset()
   {
      RebuildHierarchyFor(m_sourceBuckets, m_coreBuckets,
                          m_mitigationBuckets, m_profileBuckets);
      if(m_useFallback)
      {
         RebuildHierarchyFor(m_buckets, m_realTickCoreBuckets,
                             m_realTickMitigationBuckets, m_realTickProfileBuckets);
         RebuildHierarchyFor(m_fallbackBuckets, m_ohlcCoreBuckets,
                             m_ohlcMitigationBuckets, m_ohlcProfileBuckets);
      }
      InvalidateBucketCache(); // #15
   }

   void ApplyResult(SPatternBucket &bucket, double profitMoney, bool isWin,
                    double netR, double mfeR, double maeR, double evidenceWeight)
   {
      if(isWin) bucket.wins++;
      else      bucket.losses++;
      double w = MathMax(0.01, MathMin(1.0, evidenceWeight));
      if(isWin) bucket.winWeight += w;
      else      bucket.lossWeight += w;
      bucket.totalProfit += profitMoney * w;
      bucket.totalNetR   += netR * w;
      bucket.totalMFER   += MathMax(0.0, mfeR) * w;
      bucket.totalMAER   += MathMax(0.0, maeR) * w;
      if(mfeR >= 1.0) bucket.hit1R++;
      if(mfeR >= 1.5) bucket.hit15R++;
      if(mfeR >= 2.0) bucket.hit2R++;
      if(mfeR >= 2.5) bucket.hit25R++;
      if(mfeR >= 3.0) bucket.hit3R++;
      RecalculateBucket(bucket);
      InvalidateBucketCache(); // #15
   }

   string JournalSegmentFile(int segment)
   {
      return m_journalPrefix + StringFormat("%06d.bin", MathMax(1, segment));
   }

   bool SaveJournalIndex()
   {
      // Read-only validation/backtest runs must never create or rewrite metadata.
      if(!m_journalEnabled || !m_learningEnabled || m_journalDir == "") return true;
      string indexFile = m_journalDir + "\\JournalIndex.bin";
      string tempFile = indexFile + ".tmp";
      int handle = FileOpen(tempFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE) return false;
      FileWriteInteger(handle, AI_JOURNAL_MAGIC);
      FileWriteInteger(handle, AI_JOURNAL_VERSION);
      FileWriteInteger(handle, AI_STRATEGY_FINGERPRINT);
      FileWriteInteger(handle, m_journalSegment);
      FileFlush(handle); FileClose(handle);
      if(!FileMove(tempFile, FILE_COMMON, indexFile, FILE_COMMON | FILE_REWRITE))
        {
         FileDelete(tempFile, FILE_COMMON);
         return false;
        }
      return true;
   }

   void InitializeJournal()
   {
      m_journalSegment = 1;
      if(!m_journalEnabled || m_journalDir == "") return;
      string indexFile = m_journalDir + "\\JournalIndex.bin";
      bool validIndex = false;
      int handle = FileOpen(indexFile, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle != INVALID_HANDLE)
        {
         int magic = FileReadInteger(handle), version = FileReadInteger(handle);
         int fingerprint = FileReadInteger(handle), segment = FileReadInteger(handle);
         FileClose(handle);
          if(magic == AI_JOURNAL_MAGIC && version == AI_JOURNAL_VERSION &&
             fingerprint == AI_STRATEGY_FINGERPRINT && segment > 0)
            {
             m_journalSegment = segment;
             validIndex = true;
            }
        }
      int discovered = m_journalSegment;
      while(discovered < 100000 &&
            FileIsExist(JournalSegmentFile(discovered + 1), FILE_COMMON))
         discovered++;
      if(!validIndex || discovered != m_journalSegment)
        {
         m_journalSegment = discovered;
         SaveJournalIndex();
        }
   }

   ulong JournalChecksum(datetime eventTime, ulong observationKey, int bucketIdx,
                         int action, int direction, bool isWin,
                         double profitMoney, double netR, double mfeR, double maeR,
                         double reward, double evidenceWeight)
   {
      ulong value = observationKey ^ (ulong)eventTime;
      value ^= ((ulong)(uint)bucketIdx << 17);
      value ^= ((ulong)(uint)(action + 1) << 49);
      value ^= ((ulong)(uint)(direction + 2) << 55);
      if(isWin) value ^= (ulong)0xa5a5a5a55a5a5a5a;
      value = MixObservationKey(value ^ (ulong)(long)MathRound(profitMoney * 1000000.0));
      value = MixObservationKey(value ^ (ulong)(long)MathRound(netR * 1000000.0));
      value = MixObservationKey(value ^ (ulong)(long)MathRound(mfeR * 1000000.0));
      value = MixObservationKey(value ^ (ulong)(long)MathRound(maeR * 1000000.0));
      value = MixObservationKey(value ^ (ulong)(long)MathRound(reward * 1000000.0));
      value = MixObservationKey(value ^ (ulong)(long)MathRound(evidenceWeight * 1000000.0));
      return MixObservationKey(value);
   }

   bool AppendJournalEvent(int bucketIdx, int action, int direction, bool isWin,
                           double profitMoney, double netR, double mfeR, double maeR,
                           double reward, double evidenceWeight, ulong observationKey)
   {
      if(!m_learningEnabled || !m_journalEnabled) return true;
      datetime eventTime = TimeCurrent();
      for(int attempt = 0; attempt < 3; attempt++)
        {
         string fileName = JournalSegmentFile(m_journalSegment);
         bool exists = FileIsExist(fileName, FILE_COMMON);
         int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_BIN | FILE_COMMON);
         if(handle == INVALID_HANDLE)
           {
            LogSystemWarning("SmartBrain", "AppendJournalEvent",
                             "Cannot open event segment. Error=" + IntegerToString(GetLastError()));
            return false;
           }
         ulong size = FileSize(handle);
         bool valid = true;
         if(!exists || size == 0)
           {
            FileWriteInteger(handle, AI_JOURNAL_MAGIC);
            FileWriteInteger(handle, AI_JOURNAL_VERSION);
            FileWriteInteger(handle, AI_STRATEGY_FINGERPRINT);
            FileWriteInteger(handle, AI_JOURNAL_RECORD_BYTES);
            size = FileTell(handle);
           }
         else
           {
            FileSeek(handle, 0, SEEK_SET);
            int magic = FileReadInteger(handle), version = FileReadInteger(handle);
            int fingerprint = FileReadInteger(handle), recordBytes = FileReadInteger(handle);
            valid = (magic == AI_JOURNAL_MAGIC && version == AI_JOURNAL_VERSION &&
                     fingerprint == AI_STRATEGY_FINGERPRINT && recordBytes == AI_JOURNAL_RECORD_BYTES &&
                     size >= 16 && ((size - 16) % AI_JOURNAL_RECORD_BYTES) == 0);
           }
         if(!valid || size + AI_JOURNAL_RECORD_BYTES > m_journalSegmentBytes)
           {
            FileClose(handle);
            if(!valid)
               LogSystemWarning("SmartBrain", "AppendJournalEvent",
                                "Damaged/incompatible journal tail preserved; rotating to a new segment: " + fileName);
            m_journalSegment++;
            int oldest = m_journalSegment - AI_JOURNAL_MAX_SEGMENTS;
            if(oldest >= 1)
              {
               string oldestFile = JournalSegmentFile(oldest);
               if(FileIsExist(oldestFile, FILE_COMMON))
                  FileDelete(oldestFile, FILE_COMMON);
              }
            SaveJournalIndex();
            continue;
           }

         FileSeek(handle, 0, SEEK_END);
         ulong before = FileTell(handle);
         FileWriteLong(handle, (long)eventTime);
         FileWriteLong(handle, (long)observationKey);
         FileWriteInteger(handle, bucketIdx);
         FileWriteInteger(handle, action);
         FileWriteInteger(handle, direction);
         FileWriteInteger(handle, isWin ? 1 : 0);
         FileWriteDouble(handle, profitMoney);
         FileWriteDouble(handle, netR);
         FileWriteDouble(handle, mfeR);
         FileWriteDouble(handle, maeR);
         FileWriteDouble(handle, reward);
         FileWriteDouble(handle, evidenceWeight);
         FileWriteLong(handle, (long)JournalChecksum(eventTime, observationKey, bucketIdx,
                                                       action, direction, isWin, profitMoney,
                                                       netR, mfeR, maeR, reward, evidenceWeight));
         FileFlush(handle);
         ulong after = FileTell(handle);
         FileClose(handle);
         if(after - before == (ulong)AI_JOURNAL_RECORD_BYTES) return true;
         LogSystemWarning("SmartBrain", "AppendJournalEvent", "Incomplete journal record write.");
         return false;
        }
      return false;
   }

   long ReplayJournal(SPatternBucket &target[])
   {
      if(!m_journalEnabled || m_journalDir == "") return 0;
      long replayed = 0;
      long recordOrdinal = 0;
      int startSegment = MathMax(1, m_journalSegment - AI_JOURNAL_MAX_SEGMENTS + 1);
      for(int segment = startSegment; segment <= m_journalSegment; segment++)
        {
         string fileName = JournalSegmentFile(segment);
         if(!FileIsExist(fileName, FILE_COMMON)) continue;
         int handle = FileOpen(fileName, FILE_READ | FILE_BIN | FILE_COMMON);
         if(handle == INVALID_HANDLE) continue;
         ulong size = FileSize(handle);
         int magic = FileReadInteger(handle), version = FileReadInteger(handle);
         int fingerprint = FileReadInteger(handle), recordBytes = FileReadInteger(handle);
          if(magic != AI_JOURNAL_MAGIC || version != AI_JOURNAL_VERSION ||
             fingerprint != AI_STRATEGY_FINGERPRINT || recordBytes != AI_JOURNAL_RECORD_BYTES)
            { FileClose(handle); continue; }

         // A snapshot checkpoint already contains these physical records. Skip
         // complete old segments (or the applied prefix of the active segment)
         // in O(segments), instead of deserializing an unlimited event history.
         long segmentRecords = 0;
         if(size >= (ulong)AI_JOURNAL_HEADER_BYTES)
            segmentRecords = (long)((size - (ulong)AI_JOURNAL_HEADER_BYTES) /
                                    (ulong)AI_JOURNAL_RECORD_BYTES);
         long segmentStartOrdinal = recordOrdinal; // C8: physical ordinal at segment start
         long alreadyAppliedHere = MathMin(segmentRecords,
                                           MathMax((long)0, m_journalRecordsApplied - recordOrdinal));
         if(alreadyAppliedHere > 0)
           {
            recordOrdinal += alreadyAppliedHere;
            FileSeek(handle,
                     (long)AI_JOURNAL_HEADER_BYTES + alreadyAppliedHere * AI_JOURNAL_RECORD_BYTES,
                     SEEK_SET);
           }
         while(FileTell(handle) + (ulong)AI_JOURNAL_RECORD_BYTES <= size)
           {
            datetime eventTime = (datetime)FileReadLong(handle);
            ulong observationKey = (ulong)FileReadLong(handle);
            int bucketIdx = FileReadInteger(handle);
            int action = FileReadInteger(handle);
            int direction = FileReadInteger(handle);
            bool isWin = (FileReadInteger(handle) != 0);
            double profitMoney = FileReadDouble(handle);
            double netR = FileReadDouble(handle);
            double mfeR = FileReadDouble(handle);
            double maeR = FileReadDouble(handle);
             double reward = FileReadDouble(handle);
             double evidenceWeight = FileReadDouble(handle);
             ulong checksum = (ulong)FileReadLong(handle);
             recordOrdinal++;
             if(checksum != JournalChecksum(eventTime, observationKey, bucketIdx,
                                           action, direction, isWin, profitMoney,
                                           netR, mfeR, maeR, reward, evidenceWeight))
              {
               LogSystemWarning("SmartBrain", "ReplayJournal",
                                "Checksum failure; remaining records in segment ignored: " + fileName);
               recordOrdinal = segmentStartOrdinal + segmentRecords;
                break;
               }
            if(bucketIdx < 0 || bucketIdx >= AI_TOTAL_BUCKETS || (action != 0 && action != 1)) continue;
            if(action == 1 || BucketEvidence(target[bucketIdx]) <= 0.0)
               target[bucketIdx].lastUpdateTime = MathMax(target[bucketIdx].lastUpdateTime, eventTime);
            target[bucketIdx].lastObservationKey = observationKey;
            MarkObservationSeen(target[bucketIdx], ActionKey(observationKey, action)); // C7
            if(action == 1)
               ApplyResult(target[bucketIdx], profitMoney, isWin, netR, mfeR, maeR, evidenceWeight);
            UpdateQ(target[bucketIdx], action == 1, reward, evidenceWeight);
            replayed++;
           }
         FileClose(handle);
        }
      m_journalRecordsApplied = MathMax(m_journalRecordsApplied, recordOrdinal);
      if(replayed > 0)
         Print("[YANSTD SmartBrain] Applied journal records after cache checkpoint | Records=", replayed,
               " | Checkpoint=", m_journalRecordsApplied);
      return replayed;
   }

   bool SelectFromDataset(int bucketIdx, SPatternBucket &exactBuckets[],
                          SPatternBucket &coreBuckets[],
                          SPatternBucket &mitigationBuckets[],
                          SPatternBucket &profileBuckets[],
                          string sourceLabel, SPatternBucket &selected, string &level)
   {
      int coreIdx, mitigationIdx, profileIdx;
      GetHierarchyIndices(bucketIdx, coreIdx, mitigationIdx, profileIdx);
       if(EffectiveBucketSample(exactBuckets[bucketIdx]) >= AI_MIN_DECISION_SAMPLE)
      {
         selected = exactBuckets[bucketIdx]; level = sourceLabel + "_EXACT"; return true;
      }
       if(EffectiveBucketSample(coreBuckets[coreIdx]) >= AI_MIN_DECISION_SAMPLE)
      {
         selected = coreBuckets[coreIdx]; level = sourceLabel + "_CORE"; return true;
      }
       if(EffectiveBucketSample(mitigationBuckets[mitigationIdx]) >= AI_MIN_DECISION_SAMPLE)
      {
         selected = mitigationBuckets[mitigationIdx]; level = sourceLabel + "_MITIGATION"; return true;
      }
       if(EffectiveBucketSample(profileBuckets[profileIdx]) >= AI_MIN_DECISION_SAMPLE)
      {
         selected = profileBuckets[profileIdx]; level = sourceLabel + "_PROFILE"; return true;
      }
      return false;
   }

   bool SelectBestAvailable(int bucketIdx, SPatternBucket &exactBuckets[],
                            SPatternBucket &coreBuckets[],
                            SPatternBucket &mitigationBuckets[],
                            SPatternBucket &profileBuckets[],
                            SPatternBucket &selected, string &level)
   {
      int coreIdx, mitigationIdx, profileIdx;
      GetHierarchyIndices(bucketIdx, coreIdx, mitigationIdx, profileIdx);
      int sExact = EffectiveBucketSample(exactBuckets[bucketIdx]);
      int sCore  = EffectiveBucketSample(coreBuckets[coreIdx]);
      int sMitig = EffectiveBucketSample(mitigationBuckets[mitigationIdx]);
      int sProf  = EffectiveBucketSample(profileBuckets[profileIdx]);
      if(sExact >= AI_MIN_DECISION_SAMPLE) { selected = exactBuckets[bucketIdx];          level = "EXACT";      return true; }
      if(sCore  >= AI_MIN_DECISION_SAMPLE) { selected = coreBuckets[coreIdx];             level = "CORE";       return true; }
      if(sMitig >= AI_MIN_DECISION_SAMPLE) { selected = mitigationBuckets[mitigationIdx]; level = "MITIGATION"; return true; }
      if(sProf  >= AI_MIN_DECISION_SAMPLE) { selected = profileBuckets[profileIdx];       level = "PROFILE";    return true; }
      return false;
   }

   void MergeWeightedDecision(SPatternBucket &target, const SPatternBucket &source,
                              double sourceWeight)
   {
      double factor = MathMax(0.0, sourceWeight) * DecayWeight(source);
      if(factor <= 0.0) return;
      double takeW = source.qTakeWeight * factor;
      double skipW = source.qSkipWeight * factor;
      target.wins       += (long)MathRound((double)source.wins * factor);
      target.losses     += (long)MathRound((double)source.losses * factor);
      target.winWeight  += source.winWeight * factor;
      target.lossWeight += source.lossWeight * factor;
      target.totalProfit += source.totalProfit * factor;
      target.totalNetR   += source.totalNetR * factor;
      target.totalMFER   += source.totalMFER * factor;
      target.totalMAER   += source.totalMAER * factor;
      target.qTake       += source.qTake * takeW;
      target.qSkip       += source.qSkip * skipW;
      target.qTakeWeight += takeW;
      target.qSkipWeight += skipW;
      target.qTakeUpdates += (long)MathRound((double)source.qTakeUpdates * factor);
      target.qSkipUpdates += (long)MathRound((double)source.qSkipUpdates * factor);
   }

   bool SelectDecisionBucket(int bucketIdx, SPatternBucket &selected, string &level)
   {
      if(m_selCacheValid && m_selCacheIdx == bucketIdx &&
         m_selCacheTime == TimeCurrent() && m_selCacheEpoch == m_bucketEpoch)
      {
         selected = m_selCacheBucket;
         level    = m_selCacheLevel;
         return m_selCacheResult;
      }
      bool ok = SelectDecisionBucketUncached(bucketIdx, selected, level);
      m_selCacheValid  = true;
      m_selCacheIdx    = bucketIdx;
      m_selCacheTime   = TimeCurrent();
      m_selCacheEpoch  = m_bucketEpoch;
      m_selCacheResult = ok;
      m_selCacheBucket = selected;
      m_selCacheLevel  = level;
      return ok;
   }

   void InvalidateBucketCache()
   {
      m_bucketEpoch++;
      m_selCacheValid = false;
   }

   bool SelectDecisionBucketUncached(int bucketIdx, SPatternBucket &selected, string &level)
   {
      if(bucketIdx < 0 || bucketIdx >= AI_TOTAL_BUCKETS) return false;
      if(!m_useFallback)
         return SelectFromDataset(bucketIdx, m_sourceBuckets, m_coreBuckets,
                                  m_mitigationBuckets, m_profileBuckets,
                                  m_sourceLabel, selected, level);

      // Live/forward decisions use all available evidence instead of discarding
      // lower-priority sources as soon as LIVE reaches the minimum sample.
      ResetBucket(selected);
      selected.qTake = 0.0;
      selected.qSkip = 0.0;
      string liveLevel = "", rtLevel = "", ohlcLevel = "";
      SPatternBucket liveBucket, rtBucket, ohlcBucket;
      // m_sourceBuckets is LIVE only in forward/demo/live. In a historical
      // strict test it is the selected RT/OHLC source and those same files are
      // also loaded into the dedicated fallback arrays below. Treating source
      // as LIVE there would count the selected historical dataset twice.
      bool sourceIsLive = (m_sourceLabel == "LIVE");
      bool hasLive = sourceIsLive &&
                     SelectBestAvailable(bucketIdx, m_sourceBuckets, m_coreBuckets,
                                         m_mitigationBuckets, m_profileBuckets,
                                         liveBucket, liveLevel);
      bool hasRT = SelectBestAvailable(bucketIdx, m_buckets, m_realTickCoreBuckets,
                                       m_realTickMitigationBuckets, m_realTickProfileBuckets,
                                       rtBucket, rtLevel);
      bool hasOHLC = SelectBestAvailable(bucketIdx, m_fallbackBuckets, m_ohlcCoreBuckets,
                                         m_ohlcMitigationBuckets, m_ohlcProfileBuckets,
                                         ohlcBucket, ohlcLevel);
      if(hasLive) MergeWeightedDecision(selected, liveBucket, m_liveWeight);
      if(hasRT)   MergeWeightedDecision(selected, rtBucket, m_realTickWeight);
      if(hasOHLC) MergeWeightedDecision(selected, ohlcBucket, m_ohlcWeight);
      if(selected.qTakeWeight > 0.0) selected.qTake /= selected.qTakeWeight;
      if(selected.qSkipWeight > 0.0) selected.qSkip /= selected.qSkipWeight;
      selected.lastUpdateTime = TimeCurrent(); // evidence was already source-decayed above
      RecalculateBucket(selected);
      if(EffectiveBucketSample(selected) < AI_MIN_DECISION_SAMPLE) return false;
      level = "FUSION[" + (hasLive ? "LIVE_" + liveLevel : "") +
              (hasRT ? " RT_" + rtLevel : "") +
              (hasOHLC ? " OHLC_" + ohlcLevel : "") + "]";
      return true;
   }

public:
   bool IsLearningEnabled() const { return m_learningEnabled; }

   CSmartBrain() : m_minConfidence(42.0), m_learningEnabled(true), m_useFallback(false),
                   m_totalTradesRecorded(0), m_lastArchivePeriod(-1), m_decayHalfLifeDays(90.0),
                    m_qAlpha(0.15), m_qGamma(0.90), m_qMinUpdates(8), m_qRewardClip(2.0),
                     m_minRewardRisk(0.0),
                     m_dataRoot("YANSTD\\SmartBrain"),
                     m_liveWeight(1.0), m_realTickWeight(0.70), m_ohlcWeight(0.30),
                     m_bucketEpoch(0), m_selCacheValid(false), m_selCacheIdx(-1), // #15
                     m_selCacheTime(0), m_selCacheEpoch(0), m_selCacheResult(false),
                     m_selCacheLevel(""),
                     m_lockHandle(INVALID_HANDLE), m_lockFile(""),
                     m_journalEnabled(true), m_journalSegmentBytes(64 * 1024 * 1024),
                     m_journalDir(""), m_journalPrefix(""), m_journalSegment(1),
                     m_journalRecordsApplied(0),
                     m_learnedMinTime(0), m_learnedMaxTime(0),
                     m_chartSymbol(""), m_zoneATRTimeframe(PERIOD_M15), m_zoneATRPeriod(14)
   {
      ResetMemory();
   }

   void Init(string symbol, double minConfidence = 42.0, bool learningEnabled = true,
             ENUM_BRAIN_TEST_SOURCE testerSource = BRAIN_TEST_REALTICK,
              string portableInstrumentKey = "", bool brokerSpecificLive = true,
              double decayHalfLifeDays = 90.0,
              double qAlpha = 0.15, double qGamma = 0.90,
              int qMinUpdates = 8, double qRewardClip = 2.0,
                double liveWeight = 1.0, double realTickWeight = 0.70,
                double ohlcWeight = 0.30, bool journalEnabled = true,
                int journalSegmentMB = 64, bool allowJournalInTester = false)
   {
      m_symbol          = (portableInstrumentKey == "") ? GetCanonicalInstrumentKey(symbol)
                                                          : portableInstrumentKey;
      StringToUpper(m_symbol);
      m_chartSymbol     = symbol; // OPT-A: real broker symbol (with suffix) for ATR/pip lookups
      m_minConfidence   = minConfidence;
      m_learningEnabled = learningEnabled;
      m_decayHalfLifeDays = MathMax(0.0, decayHalfLifeDays);
      m_qAlpha = MathMax(0.001, MathMin(1.0, qAlpha));
      m_qGamma = MathMax(0.0, MathMin(1.0, qGamma));
      m_qMinUpdates = MathMax(1, qMinUpdates);
      m_qRewardClip = MathMax(0.25, qRewardClip);
      m_liveWeight = MathMax(0.0, liveWeight);
      m_realTickWeight = MathMax(0.0, realTickWeight);
      m_ohlcWeight = MathMax(0.0, ohlcWeight);
      m_journalEnabled = journalEnabled;
      m_journalSegmentBytes = (ulong)MathMax(1, journalSegmentMB) * 1024 * 1024;
      m_journalRecordsApplied = 0;
      bool isOptimization = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
      bool isTesterNonVisual = (bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE);
      if(isTesterNonVisual && m_journalEnabled && !allowJournalInTester)
        {
         m_journalEnabled = false;
         Print("[YANSTD SmartBrain] Raw-event journal DISABLED in non-visual tester (segment growth + per-record flush suppressed); in-memory learning is unaffected.");
        }
      else if(isTesterNonVisual && m_journalEnabled && allowJournalInTester)
         Print("[YANSTD SmartBrain] Raw-event journal ENABLED in tester by InpBrainEventJournalInTester");
      if(isOptimization && m_learningEnabled)
        {
         // Parallel tester agents share FILE_COMMON.  Letting them learn into
         // one database would make optimization passes order-dependent.
         m_learningEnabled = false;
         Print("[YANSTD SmartBrain] Learning disabled during optimization; each pass remains isolated.");
        }
      string safeSymbol = m_symbol;
      StringReplace(safeSymbol, "/", "_");
      StringReplace(safeSymbol, "\\", "_");
      StringReplace(safeSymbol, ":", "_");
      StringReplace(safeSymbol, "|", "_");
      StringReplace(safeSymbol, "?", "_");
      StringReplace(safeSymbol, "*", "_");
      StringReplace(safeSymbol, "\"", "_");
      StringReplace(safeSymbol, "<", "_");
      StringReplace(safeSymbol, ">", "_");
      string liveSuffix = "";
      if(brokerSpecificLive)
      {
         liveSuffix = AccountInfoString(ACCOUNT_SERVER);
         StringReplace(liveSuffix, "/", "_");
         StringReplace(liveSuffix, "\\", "_");
         StringReplace(liveSuffix, ":", "_");
         StringReplace(liveSuffix, "|", "_");
         StringReplace(liveSuffix, "?", "_");
         StringReplace(liveSuffix, "*", "_");
         StringReplace(liveSuffix, "\"", "_");
         StringReplace(liveSuffix, "<", "_");
         StringReplace(liveSuffix, ">", "_");
         StringReplace(liveSuffix, " ", "_");
      }
      string strategyTag = "_" + AI_STRATEGY_NAMESPACE;
      // FileOpen is sandboxed by MT5. These folders resolve under
      // Terminal\Common\Files, not under MQL5\Experts.
      string base = m_dataRoot + "\\";
      FolderCreate(m_dataRoot, FILE_COMMON);
      FolderCreate(base + "LIVE", FILE_COMMON);
      FolderCreate(base + "REALTICK", FILE_COMMON);
      FolderCreate(base + "OHLC", FILE_COMMON);
      m_liveFile     = base + "LIVE\\YANSTD_Brain_" + safeSymbol + strategyTag + "_LIVE" +
                        ((liveSuffix == "") ? "" : "_" + liveSuffix) + ".bin";
      m_realTickFile = base + "REALTICK\\YANSTD_Brain_" + safeSymbol + strategyTag + "_REALTICK.bin";
      m_ohlcFile     = base + "OHLC\\YANSTD_Brain_" + safeSymbol + strategyTag + "_OHLC.bin";

      ResetMemory();
      bool isTester  = (bool)MQLInfoInteger(MQL_TESTER);
      bool isForward = isTester && (bool)MQLInfoInteger(MQL_FORWARD);
      // A strict/read-only historical test must resolve decisions through the
      // same LIVE+REALTICK+OHLC fusion policy used by forward/demo/live. Matrix
      // collection remains source-isolated so training one dataset can never
      // silently ingest another dataset as prior knowledge.
      m_useFallback  = (!isTester || isForward || !m_learningEnabled);

      if(!isTester || isForward)
      {
         m_sourceLabel = "LIVE";
         m_brainFile   = m_liveFile;
      }
      else if(testerSource == BRAIN_TEST_OHLC)
      {
         m_sourceLabel = "OHLC";
         m_brainFile   = m_ohlcFile;
      }
      else
      {
         m_sourceLabel = "REALTICK";
         m_brainFile   = m_realTickFile;
      }

      string journalKey = safeSymbol + ((m_sourceLabel == "LIVE" && liveSuffix != "") ? "_" + liveSuffix : "");
      m_journalDir = base + "EVENTS\\" + m_sourceLabel + "\\" + journalKey + "\\" + AI_STRATEGY_NAMESPACE;
      if(m_journalEnabled && m_learningEnabled)
        {
         FolderCreate(base + "EVENTS", FILE_COMMON);
         FolderCreate(base + "EVENTS\\" + m_sourceLabel, FILE_COMMON);
         FolderCreate(base + "EVENTS\\" + m_sourceLabel + "\\" + journalKey, FILE_COMMON);
         FolderCreate(m_journalDir, FILE_COMMON);
        }
      m_journalPrefix = m_journalDir + "\\Events_";

      // One writer per source database.  MT5 tester agents and attached charts
      // may otherwise overwrite the same FILE_COMMON dataset with stale memory.
      m_lockFile = m_brainFile + ".lock";
      m_lockHandle = INVALID_HANDLE;
      if(m_learningEnabled)
        {
         ResetLastError();
         m_lockHandle = FileOpen(m_lockFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
         if(m_lockHandle == INVALID_HANDLE)
          {
            int lockError = GetLastError();
             m_learningEnabled = false;
             LogSystemWarning("SmartBrain", "Init",
                              "Database is locked by another EA/tester instance; learning disabled. Error=" +
                              IntegerToString(lockError));
          }
         else
           {
            FileWriteLong(m_lockHandle, AccountInfoInteger(ACCOUNT_LOGIN));
            FileWriteLong(m_lockHandle, (long)TimeLocal());
            FileFlush(m_lockHandle);
           }
        }
      InitializeJournal();

      bool sourceLoaded = LoadDataset(m_brainFile, m_sourceBuckets, m_totalTradesRecorded, true, true);
      if(!sourceLoaded)
        {
         // AUDIT FIX (#10): these used to be wrapped in
         // "if(LoadV4Dataset(...)) { sourceLoaded = true; ... 'migrated in
         // memory' ... }" branches that could never execute, since
         // RejectLegacyDataset() (which both wrappers called) always returns
         // false. No migration of legacy V3/V4 data ever actually happens;
         // these calls only log recognition of an incompatible legacy file.
         RejectLegacyDataset(m_brainFile, AI_V4_FILE_VERSION, AI_V4_FINGERPRINT, "V4", m_totalTradesRecorded);
         RejectLegacyDataset(m_brainFile, AI_V3_FILE_VERSION, AI_V3_FINGERPRINT, "V3", m_totalTradesRecorded);
        }
      if(!sourceLoaded)
        {
         sourceLoaded = LoadDataset(m_brainFile + ".bak", m_sourceBuckets,
                                    m_totalTradesRecorded, true, true);
         if(sourceLoaded)
            LogSystemWarning("SmartBrain", "Init", "Primary snapshot invalid/missing; backup snapshot restored in memory.");
        }
      if(m_journalEnabled)
        {
         long recovered = ReplayJournal(m_sourceBuckets);
         if(recovered > 0) { m_totalTradesRecorded += recovered; sourceLoaded = true; }
        }
      // C6: restore the learned date range of the active source so later saves
      // EXTEND it, then guard against in-sample leakage. A read-only tester
      // validation (learning disabled) whose simulated clock starts before the
      // dataset's max learned time would be graded on knowledge of its own
      // future; refuse the dataset and start neutral so results are honest.
      bool activeRangeKnown = LoadLearnedRange(m_brainFile, m_learnedMinTime, m_learnedMaxTime);
      bool testerRun = (bool)MQLInfoInteger(MQL_TESTER);
      if(testerRun && !m_learningEnabled && sourceLoaded)
        {
         if(!activeRangeKnown)
           {
            Print("🚨 [YANSTD SmartBrain LEAKAGE GUARD] Source dataset has no valid learned-range sidecar — dataset REFUSED for read-only validation.");
            ResetBucketArray(m_sourceBuckets);
            m_totalTradesRecorded = 0;
            sourceLoaded = false;
           }
         datetime learnedMax = 0;
         if(sourceLoaded && DatasetOverlapsCurrentClock(m_brainFile, learnedMax))
           {
            Print("🚨 [YANSTD SmartBrain LEAKAGE GUARD] Source dataset '", m_brainFile,
                  "' was learned through ", TimeToString(learnedMax, TIME_DATE),
                  " but this validation starts at ", TimeToString(TimeCurrent(), TIME_DATE),
                  ". Loading it would leak future knowledge into an out-of-sample test — dataset REFUSED, starting neutral.");
            ResetBucketArray(m_sourceBuckets);
            m_totalTradesRecorded = 0;
            sourceLoaded = false;
           }
        }
      long loadedOHLCTrades = 0;
      long loadedRealTickTrades = 0;
      if(m_useFallback)
        {
         if(!LoadDataset(m_ohlcFile, m_fallbackBuckets, loadedOHLCTrades, true))
            LoadDataset(m_ohlcFile + ".bak", m_fallbackBuckets, loadedOHLCTrades, true);
         if(!LoadDataset(m_realTickFile, m_buckets, loadedRealTickTrades, true))
            LoadDataset(m_realTickFile + ".bak", m_buckets, loadedRealTickTrades, true);
         // C6: the same guard applies to the fused historical baselines in a
         // tester FORWARD segment (live real-time can never overlap history).
         if(testerRun)
           {
            datetime lm = 0;
            datetime rangeMin = 0, rangeMax = 0;
            bool ohlcRangeKnown = LoadLearnedRange(m_ohlcFile, rangeMin, rangeMax);
            if(loadedOHLCTrades > 0 && !ohlcRangeKnown)
              {
               Print("🚨 [YANSTD SmartBrain LEAKAGE GUARD] OHLC baseline has no valid learned-range sidecar — baseline REFUSED.");
               ResetBucketArray(m_fallbackBuckets); loadedOHLCTrades = 0;
              }
            else if(loadedOHLCTrades > 0 && DatasetOverlapsCurrentClock(m_ohlcFile, lm))
              {
               Print("🚨 [YANSTD SmartBrain LEAKAGE GUARD] OHLC baseline learned through ",
                     TimeToString(lm, TIME_DATE), " overlaps this run — baseline REFUSED.");
               ResetBucketArray(m_fallbackBuckets); loadedOHLCTrades = 0;
              }
            bool rtRangeKnown = LoadLearnedRange(m_realTickFile, rangeMin, rangeMax);
            if(loadedRealTickTrades > 0 && !rtRangeKnown)
              {
               Print("🚨 [YANSTD SmartBrain LEAKAGE GUARD] RealTick baseline has no valid learned-range sidecar — baseline REFUSED.");
               ResetBucketArray(m_buckets); loadedRealTickTrades = 0;
              }
            else if(loadedRealTickTrades > 0 && DatasetOverlapsCurrentClock(m_realTickFile, lm))
              {
               Print("🚨 [YANSTD SmartBrain LEAKAGE GUARD] RealTick baseline learned through ",
                     TimeToString(lm, TIME_DATE), " overlaps this run — baseline REFUSED.");
               ResetBucketArray(m_buckets); loadedRealTickTrades = 0;
              }
           }
        }
      BuildEffectiveDataset();
      Print("[YANSTD SmartBrain] Source=", m_sourceLabel,
            " | Instrument key=", safeSymbol,
             " | Active file=", m_brainFile,
             " | Strategy=", AI_STRATEGY_NAMESPACE,
            " | Fusion weights LIVE/RT/OHLC=", DoubleToString(m_liveWeight, 2), "/",
            DoubleToString(m_realTickWeight, 2), "/", DoubleToString(m_ohlcWeight, 2),
            " | Learned source trades=", m_totalTradesRecorded,
            " | Loaded fallback RT/OHLC=", loadedRealTickTrades, "/", loadedOHLCTrades,
            " | Event journal=", (m_journalEnabled ? "ON" : "OFF"),
            (m_journalEnabled ? " segment " + IntegerToString(m_journalSegment) : ""),
            " | Decay half-life=", DoubleToString(m_decayHalfLifeDays, 1), " days",
            " | Q(alpha=", DoubleToString(m_qAlpha, 3),
            ", gamma=", DoubleToString(m_qGamma, 3),
            ", min=", m_qMinUpdates, ")");
   }

   void ResetMemory()
   {
      for(int i = 0; i < AI_TOTAL_BUCKETS; i++)
      {
         ResetBucket(m_sourceBuckets[i]);
         ResetBucket(m_fallbackBuckets[i]);
         ResetBucket(m_buckets[i]);
      }
      for(int i = 0; i < AI_CORE_BUCKETS; i++) ResetBucket(m_coreBuckets[i]);
      for(int i = 0; i < AI_MITIGATION_BUCKETS; i++) ResetBucket(m_mitigationBuckets[i]);
      for(int i = 0; i < AI_PROFILE_BUCKETS; i++) ResetBucket(m_profileBuckets[i]);
      for(int i = 0; i < AI_CORE_BUCKETS; i++)
      {
         ResetBucket(m_realTickCoreBuckets[i]);
         ResetBucket(m_ohlcCoreBuckets[i]);
      }
      for(int i = 0; i < AI_MITIGATION_BUCKETS; i++)
      {
         ResetBucket(m_realTickMitigationBuckets[i]);
         ResetBucket(m_ohlcMitigationBuckets[i]);
      }
      for(int i = 0; i < AI_PROFILE_BUCKETS; i++)
      {
         ResetBucket(m_realTickProfileBuckets[i]);
         ResetBucket(m_ohlcProfileBuckets[i]);
      }
      m_totalTradesRecorded = 0;
   }

   // Compute a unique full-pattern index.
   // OPT-B: day-of-week parameter removed (dimension dropped from the index).
   int GetBucketIndex(ENUM_SESSION_TYPE session, ENUM_SIGNAL_TYPE dir,
                      double zonePips, double trendConf,
                      ENUM_POI_PROFILE poiProfile,
                      ENUM_OB_MITIGATION obMitigation,
                      ENUM_FVG_MITIGATION fvgMitigation,
                      ENUM_FIB_LEVEL fibLevel)
   {
      int sIdx = 0;
      if(session == SESSION_LONDON)        sIdx = 1;
      else if(session == SESSION_NEWYORK)  sIdx = 2;
      else if(session == SESSION_OVERLAP)  sIdx = 3;

      int dirIdx = (dir == SIGNAL_SELL) ? 1 : 0;

      int poiIdx = (int)poiProfile;
      if(poiIdx < 0 || poiIdx > 1) poiIdx = 0;
      int obIdx = (int)obMitigation;
      if(obIdx < 0 || obIdx > 2) obIdx = 1;
      int fvgIdx = (int)fvgMitigation;
      if(fvgIdx < 0 || fvgIdx > 1) fvgIdx = 0;
      int fibIdx = (int)fibLevel;
      if(fibIdx < 0 || fibIdx > 3) fibIdx = 0;

      int zIdx = 0;
      string mdSym = (m_chartSymbol != "") ? m_chartSymbol : Symbol();
      double pip = SymbolInfoDouble(mdSym, SYMBOL_POINT) * GetPipFactor(mdSym);
      double atr = GetCachedATR(mdSym, m_zoneATRTimeframe, m_zoneATRPeriod);
      if(atr > 0.0 && pip > 0.0)
        {
         double zoneATR = (zonePips * pip) / atr;
         if(zoneATR >= 1.0)      zIdx = 2;
         else if(zoneATR >= 0.5) zIdx = 1;
        }
      else
        {
         if(zonePips >= 25.0)      zIdx = 2;
         else if(zonePips >= 15.0) zIdx = 1;
        }

      int tIdx = 0;
      if(trendConf >= 80.0) tIdx = 2;
      else if(trendConf >= 65.0) tIdx = 1;

      int idx = sIdx;
      idx = idx * 2 + dirIdx;
      idx = idx * 2 + poiIdx;
      idx = idx * 3 + obIdx;
      idx = idx * 2 + fvgIdx;
      idx = idx * 4 + fibIdx;
      idx = idx * 3 + zIdx;
      idx = idx * 3 + tIdx;

      if(idx < 0) idx = 0;
      if(idx >= AI_TOTAL_BUCKETS) idx = AI_TOTAL_BUCKETS - 1;
      return idx;
   }

   void MaybeSnapshot()
   {
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
      static uint s_lastSnapshotTick = 0;
      if(m_totalTradesRecorded % AI_SNAPSHOT_EVENT_INTERVAL != 0) return;
      uint now = GetTickCount();
      if(s_lastSnapshotTick != 0 && (now - s_lastSnapshotTick) < AI_SNAPSHOT_MIN_INTERVAL_MS) return;
      if(SaveBrain()) s_lastSnapshotTick = now;
   }

   // AUDIT FIX (#8): removed SetCounterfactualTPRR()/SetCounterfactualTP1Fraction()
   // along with the rest of the dead shadow-trade subsystem.

   // AUDIT FIX (#9): m_minRewardRisk is diagnostic-only. The comment here
   // used to claim it "caps sizing at 0.50x", but nothing in this file or
   // YANSTD.mq5 ever compares a bucket's avgMFER against it -- GetBucketView()
   // fills SBrainBucketView.avgMFER/isBanned for the caller's telemetry, and
   // YANSTD.mq5's `bestView` (see TryAutoLimitFallback) is populated and then
   // never read again. Kept as an input (InpBrainMinRewardRisk) for future
   // wiring or external logging, not as an active sizing control. Never an
   // entry gate either way.
   void SetMinRewardRisk(double rr) { m_minRewardRisk = MathMax(0.0, rr); }

   // OPT-A: ATR used to normalise zone size into volatility units for bucketing.
   void SetZoneATRParams(ENUM_TIMEFRAMES tf, int period)
   {
      m_zoneATRTimeframe = (PeriodSeconds(tf) > 0) ? tf : PERIOD_M15;
      m_zoneATRPeriod    = (period > 0) ? period : 14;
   }

   bool GetBucketView(int bucketIdx, SBrainBucketView &view)
   {
      BrainViewReset(view);
      if(bucketIdx < 0 || bucketIdx >= AI_TOTAL_BUCKETS) return false;

      SPatternBucket selected;
      string level = "NONE";
      if(!SelectDecisionBucket(bucketIdx, selected, level)) return false;

      double realSample = BucketEvidence(selected);
      double decay      = DecayWeight(selected);
      view.valid        = true;
      view.level        = level;
      view.confidence   = QConfidence(selected);
      view.sample       = EffectiveBucketSample(selected);
      view.winWeight    = selected.winWeight * decay;
      view.realEvidence = realSample * decay;
      view.avgNetR      = (realSample > 0.0) ? selected.totalNetR / realSample : 0.0;
      view.avgMFER      = (realSample > 0.0) ? selected.totalMFER / realSample : 0.0;
      view.isBanned     = selected.isBanned;
      view.qTake        = selected.qTake;
      view.qSkip        = selected.qSkip;
      view.qEvidence    = (selected.qTakeWeight + selected.qSkipWeight) * decay;
      return true;
   }

   // NOTE (v4.41 audit): a winWeight-ladder sizing multiplier used to live
   // here (GetSizingMultiplier). Since v4.41, live lot sizing is decided
   // exclusively by SetupGradeLotMultiplier() in Defines.mqh -- see
   // CHANGELOG.md 4.41 and the system guide's "Dynamic Lot Sizing v4.41"
   // section ("BrainLotMultiplier(winWeight) tidak dipakai untuk lot live").
   // The function was removed as dead code during the 2026-09-09 audit: it
   // was never called anywhere, and re-adding a winWeight-based sizing path
   // here without also updating the guide/changelog would silently
   // contradict the documented v4.41 sizing policy. BrainLotMultiplier()
   // itself is intentionally kept -- it still backs the diagnostic-only
   // rung population report in LogEvidenceDensity().

   double TotalRealEvidence()
   {
      double total = 0.0;
      for(int i = 0; i < AI_TOTAL_BUCKETS; i++)
         total += BucketEvidence(m_sourceBuckets[i]);
      return total;
   }

   // H6 (2026-09-04) DIAGNOSTIC ONLY -- no behaviour change.
   // Matrix sibling results share one unit of evidence per setup event. YANSTD
   // records the exact number of successfully placed siblings and assigns each
   // position 1/N; reconstructed tracks conservatively fall back to 1/6.
   void LogEvidenceDensity(const string tag)
   {
      int    withAny = 0, readable = 0, sizingCapable = 0, banCapable = 0, banned = 0;
      double totalRaw = 0.0, totalDecayed = 0.0, maxReal = 0.0, maxWin = 0.0;
      int    rung050 = 0, rung100 = 0, rung150 = 0, rung200 = 0, rung250 = 0;

      for(int i = 0; i < AI_TOTAL_BUCKETS; i++)
      {
         double raw = BucketEvidence(m_sourceBuckets[i]);
         if(raw <= 0.0) continue;

         double decay = DecayWeight(m_sourceBuckets[i]);
         double dec   = raw * decay;
         withAny++;
         totalRaw     += raw;
         totalDecayed += dec;
         if(dec > maxReal) maxReal = dec;
         if(EffectiveBucketSample(m_sourceBuckets[i]) >= AI_MIN_DECISION_SAMPLE) readable++;
         if(dec >= (double)AI_MIN_SIZING_EVIDENCE) sizingCapable++;
         if(dec >= 10.0) banCapable++;
         if(m_sourceBuckets[i].isBanned) banned++;

         double w = m_sourceBuckets[i].winWeight * decay;   // H3: same decayed key the ladder uses
         if(w > maxWin) maxWin = w;
         double mult = BrainLotMultiplier(w);
         if(mult <= 0.51)      rung050++;
         else if(mult <= 1.01) rung100++;
         else if(mult <= 1.51) rung150++;
         else if(mult <= 2.01) rung200++;
         else                  rung250++;
      }

      double avgPerBucket = (withAny > 0) ? totalDecayed / (double)withAny : 0.0;
      Print("[YANSTD BRAIN DENSITY ", tag, "] records=", m_totalTradesRecorded,
            " | buckets with real evidence=", withAny, "/", AI_TOTAL_BUCKETS,
            " | real evidence units raw=", DoubleToString(totalRaw, 2),
            " decayed=", DoubleToString(totalDecayed, 2),
            " | avg/bucket=", DoubleToString(avgPerBucket, 3),
            " | max in one bucket=", DoubleToString(maxReal, 2));
      Print("[YANSTD BRAIN DENSITY ", tag, "] readable (>=", AI_MIN_DECISION_SAMPLE,
            ")=", readable,
            " | sizing-capable (>=", AI_MIN_SIZING_EVIDENCE, ")=", sizingCapable,
            " | ban-capable (>=10)=", banCapable,
            " | currently quarantined=", banned,
            " | max decayed winWeight=", DoubleToString(maxWin, 2));
      Print("[YANSTD BRAIN DENSITY ", tag, "] SPEC-C rung population: 0.50x=", rung050,
            " 1.00x=", rung100, " 1.50x=", rung150,
            " 2.00x=", rung200, " 2.50x=", rung250);
      if(sizingCapable == 0)
         Print("[YANSTD BRAIN DENSITY ", tag, "] NOTE: no bucket reached negative-sizing authority; ",
               "Brain cannot apply its proven-bad 0.50x cap. MSNR+SMC still decides every entry.");
   }

   // Reinforcement update on trade closure
   bool RecordTradeResult(int bucketIdx, double profitMoney, bool isWin,
                           double netR = 0.0, double mfeR = 0.0, double maeR = 0.0,
                           ulong observationKey = 0, double evidenceWeight = 1.0)
   {
      if(!m_learningEnabled) return false;
      if(bucketIdx < 0 || bucketIdx >= AI_TOTAL_BUCKETS) return false;

      datetime observationTime = TimeCurrent();
      if(observationKey > 0 && ObservationSeen(m_sourceBuckets[bucketIdx], observationKey)) return false;
      double reward;
      if(MathAbs(netR) > 0.001) reward = MathMax(-10.0, MathMin(10.0, netR));
      else                      reward = (isWin ? 1.0 : -1.0);
      int dirIdx, poiIdx, obIdx, fvgIdx, fibIdx;
      DecodePatternIndices(bucketIdx, dirIdx, poiIdx, obIdx, fvgIdx, fibIdx);
      int direction = (dirIdx == 0) ? SIGNAL_BUY : SIGNAL_SELL;
      if(!AppendJournalEvent(bucketIdx, 1, direction, isWin, profitMoney,
                             netR, mfeR, maeR, reward, evidenceWeight, observationKey))
         return false;

      m_sourceBuckets[bucketIdx].lastUpdateTime = MathMax(m_sourceBuckets[bucketIdx].lastUpdateTime,
                                                          observationTime);
      m_sourceBuckets[bucketIdx].lastObservationKey = observationKey;
      MarkObservationSeen(m_sourceBuckets[bucketIdx], observationKey);
      ApplyResult(m_sourceBuckets[bucketIdx], profitMoney, isWin, netR, mfeR, maeR, evidenceWeight);
      UpdateQ(m_sourceBuckets[bucketIdx], true, reward, evidenceWeight);
      TouchLearnedRange(observationTime); // C6
      if(m_journalEnabled) m_journalRecordsApplied++;
      m_totalTradesRecorded++;
      BuildEffectiveDataset();

      MaybeSnapshot();
      return true;
   }

   // AUDIT FIX (#8): removed RegisterShadowTrade() and ProcessShadowTrades()
   // in full. Both were unreachable in practice (RegisterShadowTrade required
   // m_shadowEnabled, which Init() always hardcoded to false, and neither was
   // ever called from YANSTD.mq5). The two-action TAKE/SKIP Q-learning design
   // this fed never got SKIP-side evidence as a result — see CHANGELOG.

   // Save only the current source dataset.
   bool SaveBrain()
   {
      if(!m_learningEnabled) return true;
      if(m_brainFile == "" || MQLInfoInteger(MQL_OPTIMIZATION)) return false;
      if(m_lockHandle == INVALID_HANDLE)
      {
         LogSystemWarning("SmartBrain", "SaveBrain",
                          "Save rejected because the source database lock is not owned.");
         return false;
      }

      string tempFile = m_brainFile + ".tmp";
      ResetLastError();
      int handle = FileOpen(tempFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE)
      {
         LogSystemWarning("SmartBrain", "SaveBrain",
                          "Cannot open temporary database file. Error=" + IntegerToString(GetLastError()));
         return false;
      }

      FileWriteInteger(handle, AI_FILE_MAGIC);
      FileWriteInteger(handle, AI_FILE_VERSION);
      FileWriteInteger(handle, AI_STRATEGY_FINGERPRINT);
      FileWriteInteger(handle, AI_TOTAL_BUCKETS);
      FileWriteLong(handle, m_totalTradesRecorded);
      FileWriteLong(handle, m_journalRecordsApplied);
      uint written = FileWriteArray(handle, m_sourceBuckets, 0, AI_TOTAL_BUCKETS);
      FileFlush(handle);
      FileClose(handle);
      if(written != AI_TOTAL_BUCKETS)
      {
         FileDelete(tempFile, FILE_COMMON);
         LogSystemWarning("SmartBrain", "SaveBrain",
                          "Incomplete database write; active database preserved. Written=" +
                          IntegerToString((int)written));
         return false;
      }

      // Keep one known-good generation.  Journal replay covers events newer
      // than this backup's checkpoint if the primary snapshot is ever damaged.
      if(FileIsExist(m_brainFile, FILE_COMMON))
        {
         ResetLastError();
         if(!FileCopy(m_brainFile, FILE_COMMON, m_brainFile + ".bak",
                      FILE_COMMON | FILE_REWRITE))
            LogSystemWarning("SmartBrain", "SaveBrain",
                             "Backup snapshot could not be refreshed; atomic primary save will continue. Error=" +
                             IntegerToString(GetLastError()));
        }

      ResetLastError();
      if(!FileMove(tempFile, FILE_COMMON, m_brainFile, FILE_COMMON | FILE_REWRITE))
      {
         int moveError = GetLastError();
         FileDelete(tempFile, FILE_COMMON);
         LogSystemWarning("SmartBrain", "SaveBrain",
                          "Atomic database replacement failed; active database preserved. Error=" +
                          IntegerToString(moveError));
         return false;
      }
      SaveLearnedRange(m_brainFile); // C6: persist learned date-range fingerprint (sidecar)
      RotateDatedSnapshot();
      return true;
   }

   void Shutdown()
   {
      if(m_learningEnabled) SaveBrain();
      if(m_lockHandle != INVALID_HANDLE)
      {
         FileClose(m_lockHandle);
         m_lockHandle = INVALID_HANDLE;
      }
   }

};

#endif // YANSTD_SMARTBRAIN_MQH
