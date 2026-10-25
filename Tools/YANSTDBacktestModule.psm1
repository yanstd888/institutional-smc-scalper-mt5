Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-YANSTDRelativePath([string]$Base, [string]$Path) {
    $baseUri = [Uri]((Resolve-Path -LiteralPath $Base).Path.TrimEnd('\') + '\')
    $pathUri = [Uri](Resolve-Path -LiteralPath $Path).Path
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/','\')
}

function Test-YANSTDSetFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [int]$ExpectedInputCount = 200)
    if(-not (Test-Path -LiteralPath $Path)) { throw "Preset does not exist: $Path" }
    $keys = @()
    foreach($line in Get-Content -LiteralPath $Path) {
        if($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { $keys += $Matches[1] }
    }
    $unique = @($keys | Sort-Object -Unique)
    [pscustomobject]@{
        Path = (Resolve-Path -LiteralPath $Path).Path
        InputCount = $keys.Count
        UniqueInputCount = $unique.Count
        DuplicateKeys = @($keys | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
        IsValid = ($keys.Count -eq $ExpectedInputCount -and $unique.Count -eq $ExpectedInputCount)
    }
}

function New-YANSTDBacktestConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputRoot,
        [string]$TerminalExe = 'C:\Program Files\MetaTrader 5\terminal64.exe',
        [string]$TerminalDataRoot = '',
        [string]$Expert = 'YANSTD_AUDIT\YANSTD.ex5'
    )
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    [pscustomobject]@{
        SchemaVersion = 1
        ProjectRoot = $ProjectRoot
        OutputRoot = $OutputRoot
        TerminalExe = $TerminalExe
        TerminalDataRoot = $TerminalDataRoot
        Expert = $Expert
        Symbol = 'XAUUSD.FXSPREAD'
        Period = 'M3'
        Model = 4
        Deposit = 10000
        Currency = 'USD'
        Leverage = 2000
        TesterUTCOffsetWinter = 0
        TesterUseEuropeanDST = $false
        ExpectedEAVersion = '4.47.16-HYBRID'
        ExpectedInputCount = 200
        MaxSpreadPoints = 350
        CommissionPerLotRoundTurnUSD = 0.0
        SwapBuyPerLotNightUSD = -30.0
        SwapSellPerLotNightUSD = -15.0
        TripleSwapDay = 'Wednesday'
        DelayScenariosMs = @(0,100,300,500)
        AdverseSlippagePoints = @(0,100,200)
        LiveDailyLossLimitPct = 10.0
        LiveEquityDDBreakerPct = 0.0
        OOSMaxEquityDDGatePct = 20.0
    }
}

function New-YANSTDRunManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)
    $modeInfo = @(
        @{ Mode='M0_HYBRID'; ModeValue=0 },
        @{ Mode='M1_MSNR_SOFTSMC'; ModeValue=1 },
        @{ Mode='M2_SMC_SOFTMSNR'; ModeValue=2 }
    )
    $stages = @(
        @{ Stage='P01'; Suffix='SMOKE_2022Q4'; FromDate='2022.10.01'; ToDate='2023.01.01'; BrainEnabled=$false; LearningEnabled=$false; Collection=$false; DelayMs=0; Snapshot='NONE'; Purpose='operational smoke only' },
        @{ Stage='P02'; Suffix='TRAIN_DEV_2007_2022'; FromDate='2007.01.01'; ToDate='2023.01.01'; BrainEnabled=$true; LearningEnabled=$true; Collection=$true; DelayMs=0; Snapshot='RESET'; Purpose='development Brain training' },
        @{ Stage='P03'; Suffix='VALIDATE_BASELINE_2023_2024'; FromDate='2023.01.01'; ToDate='2025.01.01'; BrainEnabled=$false; LearningEnabled=$false; Collection=$false; DelayMs=0; Snapshot='NONE'; Purpose='OOS baseline' },
        @{ Stage='P04'; Suffix='VALIDATE_BRAIN_2023_2024'; FromDate='2023.01.01'; ToDate='2025.01.01'; BrainEnabled=$true; LearningEnabled=$false; Collection=$false; DelayMs=0; Snapshot='DEV_EOY2022'; Purpose='OOS Brain paired test' },
        @{ Stage='P05'; Suffix='TRAIN_FINAL_2007_2024'; FromDate='2007.01.01'; ToDate='2025.01.01'; BrainEnabled=$true; LearningEnabled=$true; Collection=$true; DelayMs=0; Snapshot='RESET'; Purpose='final Brain training' },
        @{ Stage='P06'; Suffix='HOLDOUT_BASELINE_2025_2026'; FromDate='2025.01.01'; ToDate='2026.09.01'; BrainEnabled=$false; LearningEnabled=$false; Collection=$false; DelayMs=0; Snapshot='NONE'; Purpose='untouched holdout baseline' },
        @{ Stage='P07'; Suffix='HOLDOUT_BRAIN_2025_2026'; FromDate='2025.01.01'; ToDate='2026.09.01'; BrainEnabled=$true; LearningEnabled=$false; Collection=$false; DelayMs=0; Snapshot='FINAL_EOY2024'; Purpose='untouched holdout Brain test' },
        @{ Stage='P08'; Suffix='STRESS500_BRAIN_2025_2026'; FromDate='2025.01.01'; ToDate='2026.09.01'; BrainEnabled=$true; LearningEnabled=$false; Collection=$false; DelayMs=500; Snapshot='FINAL_EOY2024'; Purpose='500 ms execution stress' }
    )
    $jobs = foreach($mode in $modeInfo) {
        foreach($stage in $stages) {
            $preset = Join-Path $Config.ProjectRoot "Presets\RECOMMENDED 2007-2026\PROTOCOL\YANSTD_$($mode.Mode)_$($stage.Stage)_$($stage.Suffix).set"
            [pscustomobject]@{
                RunId = "$($mode.Mode)_$($stage.Stage)"
                Mode = $mode.Mode; ModeValue = $mode.ModeValue; Stage = $stage.Stage
                PresetPath = $preset; FromDate = $stage.FromDate; ToDate = $stage.ToDate
                BrainEnabled = $stage.BrainEnabled; LearningEnabled = $stage.LearningEnabled
                Collection = $stage.Collection; DelayMs = $stage.DelayMs; Snapshot = $stage.Snapshot
                Purpose = $stage.Purpose
            }
        }
    }
    [pscustomobject]@{ SchemaVersion=1; CreatedUtc=(Get-Date).ToUniversalTime().ToString('o'); Config=$Config; Jobs=@($jobs) }
}

function New-YANSTDTesterIni {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)]$Job, [Parameter(Mandatory)][string]$TesterPresetName)
@"
[Common]
ProxyEnable=0
NewsEnable=0

[Tester]
Expert=$($Config.Expert)
ExpertParameters=$TesterPresetName
Symbol=$($Config.Symbol)
Period=$($Config.Period)
Deposit=$($Config.Deposit)
Currency=$($Config.Currency)
Leverage=$($Config.Leverage)
Model=$($Config.Model)
ExecutionMode=$($Job.DelayMs)
Optimization=0
FromDate=$($Job.FromDate)
ToDate=$($Job.ToDate)
ForwardMode=0
Report=$($Job.RunId)
ReplaceReport=1
ShutdownTerminal=1
Visual=0
UseLocal=1
UseRemote=0
UseCloud=0
"@
}

function Get-YANSTDFileHash([string]$Path) {
    if(Test-Path -LiteralPath $Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
    return $null
}

function Save-YANSTDJson([object]$Object, [string]$Path) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-YANSTDCandidatePresets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputDirectory
    )
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $definitions = @(
        @{ Mode='M0_HYBRID'; ModeValue='0'; Base='YANSTD_XAUUSD_M0_HYBRID_BT_BASELINE_R1.set'; Candidates=@(@{Id='C01_BASE'; Distance='1.50'; Score='45.0'},@{Id='C02_TIGHT'; Distance='1.25'; Score='50.0'},@{Id='C03_BROAD'; Distance='1.75'; Score='40.0'}) },
        @{ Mode='M1_MSNR_SOFTSMC'; ModeValue='1'; Base='YANSTD_XAUUSD_M1_MSNR_SOFTSMC_BT_BASELINE_R1.set'; Candidates=@(@{Id='C01_BASE'; Distance='1.50'; Score='55.0'},@{Id='C02_TIGHT'; Distance='1.25'; Score='60.0'},@{Id='C03_BROAD'; Distance='1.75'; Score='55.0'}) },
        @{ Mode='M2_SMC_SOFTMSNR'; ModeValue='2'; Base='YANSTD_XAUUSD_M2_SMC_SOFTMSNR_BT_BASELINE_R1.set'; Candidates=@(@{Id='C01_BASE'; Distance='2.50'; Score='45.0'},@{Id='C02_TIGHT'; Distance='2.25'; Score='50.0'},@{Id='C03_BROAD'; Distance='2.75'; Score='40.0'}) }
    )
    $output = @(); $serial = 0
    foreach($definition in $definitions) {
        $basePath = Join-Path $ProjectRoot "Presets\RECOMMENDED 2007-2026\$($definition.Base)"
        $audit = Test-YANSTDSetFile -Path $basePath -ExpectedInputCount 200
        if(-not $audit.IsValid) { throw "Cannot derive candidate from invalid preset: $basePath" }
        $baseLines = @(Get-Content -LiteralPath $basePath)
        foreach($candidate in $definition.Candidates) {
            $serial++
            $overrides = @{
                'InpSetupMode' = $definition.ModeValue
                'InpMaxEntryDistanceATR' = $candidate.Distance
                'InpMinimumSoftScore' = $candidate.Score
                'InpUseSmartBrain' = '0'
                'InpAILearning' = '0'
                'InpStrictValidationLearning' = '0'
                'InpDataCollectionMode' = '0'
                'InpTesterExecutionMode' = '1'
                'InpBrainInstrumentKey' = "XAUUSD_$($definition.Mode)_SELECT_$($candidate.Id)"
                'InpMagicNumber' = [string](491000 + $serial)
                'InpTesterUTCOffsetWinter' = '0'
                'InpTesterUseEuropeanDST' = '0'
                'InpShowDashboard' = '0'
                'InpEnablePushAlerts' = '0'
                'InpBrainEventJournalInTester' = '0'
                # Research-only: account kill-switches OFF so DEV measures raw
                # strategy DD. The L2 equity breaker is peak-anchored and never
                # resets mid-run (one-way latch); at 12% it halted all entries
                # from 2008.03.25 onward. Breakers stay ON only in LIVE presets.
                'InpMaxDailyLossPct' = '0.0'
                'InpMaxEquityDDPct' = '0.0'
            }
            $rendered = @(
                "; YANSTD 4.47.16-HYBRID - $($definition.Mode) $($candidate.Id) selection candidate",
                '; Candidate selection only: Brain OFF, real ticks, UTC+0/DST=NO.',
                '; Choose from validation only. Never tune candidates after opening 2025-2026 holdout.'
            )
            foreach($line in $baseLines) {
                if($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                    $key = $Matches[1]
                    if($overrides.ContainsKey($key)) { $rendered += ($key + '=' + $overrides[$key]) }
                    else { $rendered += $line }
                }
            }
            $fileName = "YANSTD_XAUUSD_$($definition.Mode)_$($candidate.Id)_SELECT.set"
            $presetPath = Join-Path $OutputDirectory $fileName
            $rendered | Set-Content -LiteralPath $presetPath -Encoding UTF8
            $verified = Test-YANSTDSetFile -Path $presetPath -ExpectedInputCount 200
            if(-not $verified.IsValid) { throw "Candidate generation failed schema audit: $presetPath" }
            $output += [pscustomobject]@{ CandidateId=$candidate.Id; Mode=$definition.Mode; ModeValue=[int]$definition.ModeValue; PresetPath=$presetPath; MaxEntryDistanceATR=[double]$candidate.Distance; MinimumSoftScore=[double]$candidate.Score; PresetSHA256=(Get-YANSTDFileHash $presetPath) }
        }
    }
    return @($output)
}

function New-YANSTDGeneration2CandidatePresets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputDirectory
    )
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    # Preregistered from Generation-1 DEV/validation attribution. Each mode
    # keeps the best relative Gen-1 distance/score fixed; Generation 2 changes
    # only the structural-variant whitelist and UTC entry window.
    $definitions = @(
        @{ Mode='M0_HYBRID'; ModeValue='0'; Base='YANSTD_XAUUSD_M0_HYBRID_BT_BASELINE_R1.set'; Distance='1.75'; Score='40.0'; Candidates=@(
            @{Id='G2C01_H_CORE'; Variants='FIB_618,FIB_705'; Start='7'; End='11'},
            @{Id='G2C02_H_705';  Variants='FIB_705';         Start='9'; End='0'},
            @{Id='G2C03_H_618';  Variants='FIB_618';         Start='7'; End='11'}
        )},
        @{ Mode='M1_MSNR_SOFTSMC'; ModeValue='1'; Base='YANSTD_XAUUSD_M1_MSNR_SOFTSMC_BT_BASELINE_R1.set'; Distance='1.50'; Score='55.0'; Candidates=@(
            @{Id='G2C01_M_790';    Variants='FIB_790';         Start='8'; End='13'},
            @{Id='G2C02_M_705790'; Variants='FIB_705,FIB_790'; Start='8'; End='14'},
            @{Id='G2C03_M_790_W';  Variants='FIB_790';         Start='7'; End='13'}
        )},
        @{ Mode='M2_SMC_SOFTMSNR'; ModeValue='2'; Base='YANSTD_XAUUSD_M2_SMC_SOFTMSNR_BT_BASELINE_R1.set'; Distance='2.25'; Score='50.0'; Candidates=@(
            @{Id='G2C01_S_618';     Variants='FIB_618';         Start='2'; End='9'},
            @{Id='G2C02_S_618705';  Variants='FIB_618,FIB_705'; Start='2'; End='9'},
            @{Id='G2C03_S_618705E'; Variants='FIB_618,FIB_705'; Start='2'; End='6'}
        )}
    )

    $output = @(); $serial = 0
    foreach($definition in $definitions) {
        $basePath = Join-Path $ProjectRoot "Presets\RECOMMENDED 2007-2026\$($definition.Base)"
        $audit = Test-YANSTDSetFile -Path $basePath -ExpectedInputCount 200
        if(-not $audit.IsValid) { throw "Cannot derive Generation-2 candidate from invalid preset: $basePath" }
        $baseLines = @(Get-Content -LiteralPath $basePath)
        foreach($candidate in $definition.Candidates) {
            $serial++
            $magic = 492000 + $serial
            $overrides = @{
                'InpSetupMode' = $definition.ModeValue
                'InpMaxEntryDistanceATR' = $definition.Distance
                'InpMinimumSoftScore' = $definition.Score
                'InpEntryVariants' = $candidate.Variants
                'InpUseTimeFilter' = '1'
                'InpTimeFilterMode' = '0'
                'InpStartHourUTC' = $candidate.Start
                'InpEndHourUTC' = $candidate.End
                'InpUseSmartBrain' = '0'
                'InpAILearning' = '0'
                'InpStrictValidationLearning' = '0'
                'InpDataCollectionMode' = '0'
                'InpTesterExecutionMode' = '1'
                'InpBrainInstrumentKey' = "XAUUSD_$($definition.Mode)_GEN2_$($candidate.Id)"
                'InpMagicNumber' = [string]$magic
                'InpTesterUTCOffsetWinter' = '0'
                'InpTesterUseEuropeanDST' = '0'
                'InpShowDashboard' = '0'
                'InpEnablePushAlerts' = '0'
                'InpBrainEventJournalInTester' = '0'
                'InpMaxDailyLossPct' = '0.0'
                'InpMaxEquityDDPct' = '0.0'
            }
            $rendered = @(
                "; YANSTD 4.47.16-HYBRID - $($definition.Mode) $($candidate.Id) Generation-2 research candidate",
                "; Preregistered variants=$($candidate.Variants), UTC=$($candidate.Start)-$($candidate.End). Brain OFF; research breakers OFF.",
                '; DEV and validation only. Do not open the 2025-2026 holdout.'
            )
            foreach($line in $baseLines) {
                if($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                    $key = $Matches[1]
                    if($overrides.ContainsKey($key)) { $rendered += ($key + '=' + $overrides[$key]) }
                    else { $rendered += $line }
                }
            }
            $fileName = "YANSTD_XAUUSD_$($definition.Mode)_$($candidate.Id)_SELECT.set"
            $presetPath = Join-Path $OutputDirectory $fileName
            $rendered | Set-Content -LiteralPath $presetPath -Encoding UTF8
            $verified = Test-YANSTDSetFile -Path $presetPath -ExpectedInputCount 200
            if(-not $verified.IsValid) { throw "Generation-2 candidate schema audit failed: $presetPath" }
            $output += [pscustomobject]@{
                CandidateId=$candidate.Id; Mode=$definition.Mode; ModeValue=[int]$definition.ModeValue
                PresetPath=$presetPath; MaxEntryDistanceATR=[double]$definition.Distance
                MinimumSoftScore=[double]$definition.Score; EntryVariants=$candidate.Variants
                StartHourUTC=[int]$candidate.Start; EndHourUTC=[int]$candidate.End
                MagicNumber=$magic; PresetSHA256=(Get-YANSTDFileHash $presetPath)
            }
        }
    }
    return @($output)
}

function New-YANSTDGeneration3CandidatePresets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputDirectory
    )
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    # Gen3 is preregistered from pre-2023 evidence only. Fixed lot removes
    # long-horizon compounding distortion; all-hours-except-rollover avoids
    # reusing the already-exposed 2023-2024 hour cuts.
    $definitions = @(
        @{ Mode='M0_HYBRID'; ModeValue='0'; Base='YANSTD_XAUUSD_M0_HYBRID_BT_BASELINE_R1.set'; Distance='1.75'; Score='45.0'; Candidates=@(
            @{Id='G3H01_F618_CORE'; Variants='FIB_618'; RRR='0'; TimeBars='16'},
            @{Id='G3H02_F618_RRR';  Variants='FIB_618'; RRR='1'; TimeBars='16'},
            @{Id='G3H03_F618_T24';  Variants='FIB_618'; RRR='0'; TimeBars='24'}
        )},
        @{ Mode='M2_SMC_SOFTMSNR'; ModeValue='2'; Base='YANSTD_XAUUSD_M2_SMC_SOFTMSNR_BT_BASELINE_R1.set'; Distance='2.25'; Score='50.0'; Candidates=@(
            @{Id='G3S01_F618_CORE';   Variants='FIB_618';         RRR='0'; TimeBars='16'},
            @{Id='G3S02_F618_RRR';    Variants='FIB_618';         RRR='1'; TimeBars='16'},
            @{Id='G3S03_F618705_T24'; Variants='FIB_618,FIB_705'; RRR='0'; TimeBars='24'}
        )}
    )

    $output=@(); $serial=0
    foreach($definition in $definitions) {
        $basePath=Join-Path $ProjectRoot "Presets\RECOMMENDED 2007-2026\$($definition.Base)"
        $audit=Test-YANSTDSetFile -Path $basePath -ExpectedInputCount 200
        if(-not $audit.IsValid){throw "Cannot derive Gen3 candidate from invalid preset: $basePath"}
        $baseLines=@(Get-Content -LiteralPath $basePath)
        foreach($candidate in $definition.Candidates) {
            $serial++
            $overrides=@{
                'InpSetupMode'=$definition.ModeValue
                'InpMaxEntryDistanceATR'=$definition.Distance
                'InpMinimumSoftScore'=$definition.Score
                'InpEntryVariants'=$candidate.Variants
                'InpUseMinimumRRRGate'=$candidate.RRR
                'InpMinimumStructuralRRR'='1.10'
                'InpUseTimeInvalidation'='1'
                'InpTimeInvalidationBarsM5'=$candidate.TimeBars
                'InpUseTimeFilter'='1'
                'InpTimeFilterMode'='1'
                'InpRolloverBlockStartUTC'='20'
                'InpRolloverBlockEndUTC'='23'
                'InpFixedLot'='0.10'
                'InpUseDynamicRisk'='0'
                'InpUseSmartBrain'='0'
                'InpAILearning'='0'
                'InpStrictValidationLearning'='0'
                'InpDataCollectionMode'='0'
                'InpTesterExecutionMode'='1'
                'InpBrainInstrumentKey'="XAUUSD_$($definition.Mode)_GEN3_$($candidate.Id)"
                'InpMagicNumber'=[string](493000+$serial)
                'InpTesterUTCOffsetWinter'='0'
                'InpTesterUseEuropeanDST'='0'
                'InpShowDashboard'='0'
                'InpEnablePushAlerts'='0'
                'InpBrainEventJournalInTester'='0'
                'InpMaxDailyLossPct'='0.0'
                'InpMaxEquityDDPct'='0.0'
            }
            $rendered=@(
                "; YANSTD 4.47.16-HYBRID - $($definition.Mode) $($candidate.Id) Gen3 rolling research",
                "; FixedLot=0.10; variants=$($candidate.Variants); RRRgate=$($candidate.RRR); TimeBars=$($candidate.TimeBars).",
                '; Pre-2023 rolling walk-forward only; no holdout/live/forward.'
            )
            foreach($line in $baseLines) {
                if($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                    $key=$Matches[1]
                    if($overrides.ContainsKey($key)){$rendered+=($key+'='+$overrides[$key])}else{$rendered+=$line}
                }
            }
            $fileName="YANSTD_XAUUSD_$($definition.Mode)_$($candidate.Id)_WF.set"
            $presetPath=Join-Path $OutputDirectory $fileName
            $rendered|Set-Content -LiteralPath $presetPath -Encoding UTF8
            $verified=Test-YANSTDSetFile -Path $presetPath -ExpectedInputCount 200
            if(-not $verified.IsValid){throw "Gen3 candidate schema audit failed: $presetPath"}
            $output += [pscustomobject]@{
                CandidateId=$candidate.Id; Mode=$definition.Mode; ModeValue=[int]$definition.ModeValue
                PresetPath=$presetPath; EntryVariants=$candidate.Variants
                RRRGate=[bool]([int]$candidate.RRR); TimeInvalidationBars=[int]$candidate.TimeBars
                FixedLot=0.10; MagicNumber=(493000+$serial); PresetSHA256=(Get-YANSTDFileHash $presetPath)
            }
        }
    }
    return @($output)
}

function New-YANSTDGeneration3WalkForwardManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config,[Parameter(Mandatory)][object[]]$Candidates)
    $folds=@(
        @{Id='WF1';FitFrom='2007.01.01';FitTo='2013.01.01';ValFrom='2013.01.01';ValTo='2017.01.01'},
        @{Id='WF2';FitFrom='2007.01.01';FitTo='2017.01.01';ValFrom='2017.01.01';ValTo='2020.01.01'},
        @{Id='WF3';FitFrom='2007.01.01';FitTo='2020.01.01';ValFrom='2020.01.01';ValTo='2023.01.01'}
    )
    $jobs=foreach($candidate in $Candidates){foreach($fold in $folds){foreach($stage in @(
        @{Name="$($fold.Id)_FIT";From=$fold.FitFrom;To=$fold.FitTo},
        @{Name="$($fold.Id)_VALIDATE";From=$fold.ValFrom;To=$fold.ValTo}
    )){[pscustomobject]@{
        RunId="$($candidate.Mode)_$($candidate.CandidateId)_$($stage.Name)";Mode=$candidate.Mode;ModeValue=$candidate.ModeValue
        CandidateId=$candidate.CandidateId;Fold=$fold.Id;Stage=$stage.Name;PresetPath=$candidate.PresetPath
        FromDate=$stage.From;ToDate=$stage.To;BrainEnabled=$false;LearningEnabled=$false;Collection=$false
        DelayMs=0;Snapshot='NONE';Purpose='Gen3 pre-2023 rolling walk-forward, fixed lot 0.10'
    }}}}
    [pscustomobject]@{SchemaVersion=1;CreatedUtc=(Get-Date).ToUniversalTime().ToString('o');Config=$Config;Jobs=@($jobs)}
}

function New-YANSTDCandidateManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][object[]]$Candidates)
    $jobs = foreach($candidate in $Candidates) {
        foreach($stage in @(
            @{ Name='SELECT_DEV'; From='2007.01.01'; To='2023.01.01' },
            @{ Name='SELECT_VALIDATE'; From='2023.01.01'; To='2025.01.01' }
        )) {
            [pscustomobject]@{
                RunId="$($candidate.Mode)_$($candidate.CandidateId)_$($stage.Name)"; Mode=$candidate.Mode; ModeValue=$candidate.ModeValue; CandidateId=$candidate.CandidateId
                Stage=$stage.Name; PresetPath=$candidate.PresetPath; FromDate=$stage.From; ToDate=$stage.To
                BrainEnabled=$false; LearningEnabled=$false; Collection=$false; DelayMs=0; Snapshot='NONE'
                Purpose='candidate selection, baseline-only'
            }
        }
    }
    [pscustomobject]@{ SchemaVersion=1; CreatedUtc=(Get-Date).ToUniversalTime().ToString('o'); Config=$Config; Jobs=@($jobs) }
}

Export-ModuleMember -Function Test-YANSTDSetFile,New-YANSTDBacktestConfig,New-YANSTDRunManifest,New-YANSTDCandidatePresets,New-YANSTDGeneration2CandidatePresets,New-YANSTDGeneration3CandidatePresets,New-YANSTDGeneration3WalkForwardManifest,New-YANSTDCandidateManifest,New-YANSTDTesterIni,Get-YANSTDFileHash,Save-YANSTDJson
