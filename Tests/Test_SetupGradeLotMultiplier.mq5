//+------------------------------------------------------------------+
//|                                Test_SetupGradeLotMultiplier.mq5  |
//|         Unit test — grade sizing contract (H2, v4.47.8)          |
//|                                                                    |
//| Verifies SetupGradeLotMultiplier() and SetupGradeRejects() against |
//| the single source-of-truth contract for all 10 ENUM_SETUP_GRADE    |
//| values:                                                             |
//|   S+ / S           = 2.00x                                         |
//|   A+ / A           = 1.50x  (recalibrated v4.48.0, §56)            |
//|   B+ / B           = 1.00x                                         |
//|   C+ / C           = 0.50x                                         |
//|   D+ / D           = reject (0.00x)                                |
//|                                                                    |
//| Run as a Script (drag onto any chart, or Strategy Tester "Script"   |
//| test). Does not place trades or touch the network. Fails loudly    |
//| (Alert + non-zero summary) if SetupGradeLotMultiplier() in         |
//| Modules/Defines.mqh ever drifts from this contract again.          |
//+------------------------------------------------------------------+
#property copyright "YANSTD EA"
#property version   "1.00"
#property strict
#property script_show_inputs

#include "../Modules/Defines.mqh"

//+------------------------------------------------------------------+
//| Expected contract row: grade, expected multiplier, expect reject  |
//+------------------------------------------------------------------+
struct GradeExpectation
  {
   ENUM_SETUP_GRADE grade;
   double           expectedMult;
   bool             expectReject;
  };

void OnStart()
  {
   GradeExpectation table[10] =
     {
      { GRADE_S_PLUS,   2.00, false },
      { GRADE_S,        2.00, false },
      { GRADE_A_PLUS,   1.50, false },
      { GRADE_A,        1.50, false },
      { GRADE_B_PLUS,   1.00, false },
      { GRADE_B,        1.00, false },
      { GRADE_C_PLUS,   0.50, false },
      { GRADE_C,        0.50, false },
      { GRADE_D_PLUS,   0.00, true  },
      { GRADE_D,        0.00, true  }
     };

   int    total  = ArraySize(table);
   int    passed = 0;
   int    failed = 0;

   Print("==================================================================");
   Print("[TEST] SetupGradeLotMultiplier / SetupGradeRejects — H2 contract v4.47.8");
   Print("==================================================================");

   for(int i = 0; i < total; i++)
     {
      ENUM_SETUP_GRADE g        = table[i].grade;
      string           gName    = SetupGradeName(g);
      double           gotMult  = SetupGradeLotMultiplier(g);
      bool             gotRej   = SetupGradeRejects(g);
      bool             multOK   = (MathAbs(gotMult - table[i].expectedMult) < 0.0001);
      bool             rejOK    = (gotRej == table[i].expectReject);
      bool             rowOK    = multOK && rejOK;

      if(rowOK)
        {
         passed++;
         PrintFormat("[PASS] Grade %-2s | multiplier=%.2fx (expected %.2fx) | reject=%s",
                     gName, gotMult, table[i].expectedMult, (gotRej ? "true" : "false"));
        }
      else
        {
         failed++;
         PrintFormat("[FAIL] Grade %-2s | multiplier=%.2fx (expected %.2fx) | reject=%s (expected %s)",
                     gName, gotMult, table[i].expectedMult,
                     (gotRej ? "true" : "false"), (table[i].expectReject ? "true" : "false"));
        }
     }

   // Cross-check MaxSetupGradeLotMultiplier() derives 2.00x from the same
   // table — this is the number the OnInit() startup log prints, so it must
   // never silently diverge from the per-grade contract checked above.
   double maxMult   = MaxSetupGradeLotMultiplier();
   bool   maxMultOK = (MathAbs(maxMult - 2.00) < 0.0001);
   if(maxMultOK)
     {
      passed++;
      PrintFormat("[PASS] MaxSetupGradeLotMultiplier() = %.2fx (expected 2.00x)", maxMult);
     }
   else
     {
      failed++;
      PrintFormat("[FAIL] MaxSetupGradeLotMultiplier() = %.2fx (expected 2.00x)", maxMult);
     }
   total++;

   Print("------------------------------------------------------------------");
   PrintFormat("[TEST SUMMARY] %d/%d passed, %d failed", passed, total, failed);
   Print("==================================================================");

   if(failed > 0)
      Alert(StringFormat("YANSTD Test_SetupGradeLotMultiplier: %d/%d FAILED — sizing contract has drifted!",
                          failed, total));
   else
      Print("[TEST] All grade sizing checks passed — contract intact (S+/S=2.00x, A+/A=1.50x, B+/B=1.00x, C+/C=0.50x, D+/D=reject).");
  }
//+------------------------------------------------------------------+
