$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'Tools\YANSTDBacktestModule.psm1'
Import-Module $modulePath -Force
$temp = Join-Path $env:TEMP ('yanstd-g2-' + [guid]::NewGuid().ToString('N'))
try {
    $candidates = @(New-YANSTDGeneration2CandidatePresets -ProjectRoot $projectRoot -OutputDirectory $temp)
    if($candidates.Count -ne 9) { throw "Expected 9 Generation-2 candidates, found $($candidates.Count)" }
    $magic = @($candidates | ForEach-Object { $_.MagicNumber } | Sort-Object -Unique)
    if($magic.Count -ne 9) { throw 'Generation-2 magic numbers are not unique' }
    foreach($candidate in $candidates) {
        $audit = Test-YANSTDSetFile -Path $candidate.PresetPath -ExpectedInputCount 201
        if(-not $audit.IsValid) { throw "Invalid preset: $($candidate.PresetPath)" }
        $lines = @(Get-Content -LiteralPath $candidate.PresetPath)
        foreach($required in @(
            'InpUseSmartBrain=0','InpAILearning=0','InpStrictValidationLearning=0',
            'InpMaxDailyLossPct=0.0','InpMaxEquityDDPct=0.0',
            'InpTesterUTCOffsetWinter=0','InpTesterUseEuropeanDST=0',
            'InpTimeFilterMode=0','InpUseTimeFilter=1'
        )) {
            if($required -notin $lines) { throw "$($candidate.CandidateId) missing $required" }
        }
    }
    $hybrid = @($candidates | Where-Object CandidateId -eq 'G2C01_H_CORE')[0]
    $hLines = @(Get-Content -LiteralPath $hybrid.PresetPath)
    if('InpEntryVariants=FIB_618,FIB_705' -notin $hLines -or 'InpStartHourUTC=7' -notin $hLines -or 'InpEndHourUTC=11' -notin $hLines) {
        throw 'Hybrid core hypothesis is not locked to FIB_618/FIB_705, 07-11 UTC'
    }
    $msnr = @($candidates | Where-Object CandidateId -eq 'G2C01_M_790')[0]
    $mLines = @(Get-Content -LiteralPath $msnr.PresetPath)
    if('InpEntryVariants=FIB_790' -notin $mLines -or 'InpStartHourUTC=8' -notin $mLines -or 'InpEndHourUTC=13' -notin $mLines) {
        throw 'MSNR hypothesis is not locked to FIB_790, 08-13 UTC'
    }
    $smc = @($candidates | Where-Object CandidateId -eq 'G2C01_S_618')[0]
    $sLines = @(Get-Content -LiteralPath $smc.PresetPath)
    if('InpEntryVariants=FIB_618' -notin $sLines -or 'InpStartHourUTC=2' -notin $sLines -or 'InpEndHourUTC=9' -notin $sLines) {
        throw 'SMC hypothesis is not locked to FIB_618, 02-09 UTC'
    }
    Write-Host 'TEST-GENERATION2-CANDIDATES: PASS'
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
