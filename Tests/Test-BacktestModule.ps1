param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $ProjectRoot 'Tools\YANSTDBacktestModule.psm1'
$fixture = Join-Path $ProjectRoot 'Presets\RECOMMENDED 2007-2026\PROTOCOL\YANSTD_M0_HYBRID_P01_SMOKE_2022Q4.set'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('YANSTD_BacktestModule_Test_' + [guid]::NewGuid().ToString('N'))

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw "ASSERT FAILED: $Message" }
}

try {
    Import-Module $modulePath -Force

    $setAudit = Test-YANSTDSetFile -Path $fixture -ExpectedInputCount 201
    Assert-True ($setAudit.IsValid -and $setAudit.InputCount -eq 201 -and $setAudit.UniqueInputCount -eq 201) 'set audit must verify 200 unique inputs'

    $config = New-YANSTDBacktestConfig -ProjectRoot $ProjectRoot -OutputRoot $tempRoot
    Assert-True ($config.Symbol -eq 'XAUUSD.FXSPREAD') 'symbol must be XAUUSD.FXSPREAD'
    Assert-True ($config.TesterUTCOffsetWinter -eq 0 -and -not $config.TesterUseEuropeanDST) 'tester time must be UTC+0 without DST'
    Assert-True ($config.Model -eq 4 -and $config.Period -eq 'M3') 'tester model must be real ticks/M3'
    Assert-True ($config.CommissionPerLotRoundTurnUSD -eq 0.0) 'commission must be zero'
    Assert-True ($config.SwapBuyPerLotNightUSD -eq -30.0 -and $config.SwapSellPerLotNightUSD -eq -15.0 -and $config.TripleSwapDay -eq 'Wednesday') 'conservative swap contract must be explicit'
    Assert-True ((@($config.DelayScenariosMs) -join ',') -eq '0,100,300,500') 'delay scenarios must be locked'
    Assert-True ((@($config.AdverseSlippagePoints) -join ',') -eq '0,100,200') 'slippage scenarios must be locked'
    Assert-True ($config.LiveDailyLossLimitPct -eq 10.0 -and $config.LiveEquityDDBreakerPct -eq 0.0 -and $config.OOSMaxEquityDDGatePct -eq 20.0) 'drawdown policy must be locked'

    $candidateRoot = Join-Path $tempRoot 'Candidates'
    $candidates = New-YANSTDCandidatePresets -ProjectRoot $ProjectRoot -OutputDirectory $candidateRoot
    Assert-True ($candidates.Count -eq 9) 'candidate universe must have 9 presets: 3 modes × 3 selectivity profiles'
    Assert-True ((@($candidates | Where-Object { -not (Test-YANSTDSetFile -Path $_.PresetPath -ExpectedInputCount 201).IsValid }).Count) -eq 0) 'every candidate must retain all 200 inputs'
    foreach($candidate in $candidates) {
        $ddLines = @(Get-Content -LiteralPath $candidate.PresetPath | Where-Object { $_ -match '^InpMax(EquityDD|DailyLoss)Pct=' })
        Assert-True ($ddLines -contains 'InpMaxEquityDDPct=0.0' -and $ddLines -contains 'InpMaxDailyLossPct=0.0') ('research candidate must disable account kill-switches: ' + $candidate.PresetPath)
    }
    $candidateManifest = New-YANSTDCandidateManifest -Config $config -Candidates $candidates
    Assert-True ($candidateManifest.Jobs.Count -eq 18) 'candidate protocol must have development and validation for every candidate'
    Assert-True ((@($candidateManifest.Jobs | Where-Object { $_.Stage -eq 'SELECT_VALIDATE' -and $_.BrainEnabled }).Count) -eq 0) 'candidate selection must be baseline-only without Brain'

    $manifest = New-YANSTDRunManifest -Config $config
    Assert-True ($manifest.SchemaVersion -eq 1) 'manifest schema version must be 1'
    Assert-True ($manifest.Jobs.Count -eq 24) 'core protocol must have 24 jobs: 3 modes × 8 stages'
    Assert-True ((@($manifest.Jobs | Where-Object { $_.Stage -eq 'P08' -and $_.DelayMs -eq 500 }).Count) -eq 3) 'exactly three stress jobs must use 500 ms delay'
    Assert-True ((@($manifest.Jobs | Where-Object { $_.Stage -in @('P03','P04','P06','P07','P08') -and $_.LearningEnabled }).Count) -eq 0) 'validation/holdout/stress must be read-only'
    Assert-True ((@($manifest.Jobs | Where-Object { $_.Stage -in @('P02','P05') -and $_.LearningEnabled }).Count) -eq 6) 'only training stages may learn'

    $p04 = @($manifest.Jobs | Where-Object { $_.Mode -eq 'M0_HYBRID' -and $_.Stage -eq 'P04' })[0]
    $ini = New-YANSTDTesterIni -Config $config -Job $p04 -TesterPresetName 'fixture.set'
    Assert-True ($ini -match 'Symbol=XAUUSD.FXSPREAD') 'ini must preserve configured symbol'
    Assert-True ($ini -match 'Model=4') 'ini must request real ticks'
    Assert-True ($ini -match 'FromDate=2023.01.01') 'P04 start date must be validation start'
    Assert-True ($ini -match 'ToDate=2025.01.01') 'P04 end date must be validation end'
    Assert-True ($ini -match 'ExpertParameters=fixture.set') 'ini must name copied tester preset'

    Write-Host 'TEST-BACKTEST-MODULE: PASS'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Force -Recurse -ErrorAction SilentlyContinue
}
