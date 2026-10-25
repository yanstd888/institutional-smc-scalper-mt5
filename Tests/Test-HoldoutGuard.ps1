$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $projectRoot 'Tools\Run-YANSTDBacktestJob.ps1'
$extractor = Join-Path $projectRoot 'Tools\extract_backtest_attribution.py'
$scorer = Join-Path $projectRoot 'Tools\score_backtest_candidates.py'
$temp = Join-Path $env:TEMP ('yanstd-holdout-guard-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null

function Assert-Rejected([scriptblock]$Action, [string]$Expected, [string]$Label) {
    $message = ''
    try { & $Action; throw "${Label}: unexpectedly accepted" }
    catch { $message = $_.Exception.Message }
    if($message -notmatch [regex]::Escape($Expected)) {
        throw "${Label}: expected '$Expected', got '$message'"
    }
}

try {
    Assert-Rejected {
        & $runner -PresetPath (Join-Path $temp 'missing.set') -RunId 'FORBIDDEN' `
            -FromDate '2025.01.01' -ToDate '2025.02.01' -TerminalExe (Join-Path $temp 'missing.exe')
    } 'HOLDOUT GUARD' 'runner'

    $runDir = Join-Path $temp 'Runs\M0_HYBRID_FORBIDDEN_SELECT_VALIDATE'
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    '<html><body><table></table></body></html>' | Set-Content -LiteralPath (Join-Path $runDir 'report.htm') -Encoding Unicode
    '{"FromDate":"2024.01.01","ToDate":"2025.02.01"}' | Set-Content -LiteralPath (Join-Path $runDir 'run-metadata.json') -Encoding UTF8
    $extractOutput = Join-Path $temp 'extract-out'
    $ErrorActionPreference = 'Continue'
    $extractText = & python $extractor --runs-root (Join-Path $temp 'Runs') --output-dir $extractOutput 2>&1
    $extractExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if($extractExit -eq 0 -or ($extractText -join "`n") -notmatch 'HOLDOUT GUARD') {
        throw "extractor: expected HOLDOUT GUARD rejection, got: $($extractText -join ' ')"
    }

    # Missing metadata must fail closed; otherwise a copied holdout report can
    # bypass the ToDate guard entirely.
    Remove-Item -LiteralPath (Join-Path $runDir 'run-metadata.json') -Force
    $ErrorActionPreference = 'Continue'
    $missingMetaText = & python $extractor --runs-root (Join-Path $temp 'Runs') --output-dir $extractOutput 2>&1
    $missingMetaExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if($missingMetaExit -eq 0 -or ($missingMetaText -join "`n") -notmatch 'HOLDOUT GUARD') {
        throw "extractor missing-metadata: expected fail-closed HOLDOUT GUARD, got: $($missingMetaText -join ' ')"
    }

    $journalDir = Join-Path $temp 'JournalRuns\M0_HYBRID_FORBIDDEN_SELECT_VALIDATE'
    New-Item -ItemType Directory -Force -Path $journalDir | Out-Null
    '{"TestCompleted":true,"ProfitFactor":"1.2","ExpectedPayoff":"1","RecoveryFactor":"2","EquityDrawdownMax":"1 (1%)","Errors":[]}' | Set-Content -LiteralPath (Join-Path $journalDir 'journal.json') -Encoding UTF8
    $positions = Join-Path $temp 'positions.csv'
    @(
        'run_id,split,mode,position_id,entry_year,net_profit',
        'M0_HYBRID_FORBIDDEN_SELECT_VALIDATE,VALIDATE,HYBRID,x,2025,10'
    ) | Set-Content -LiteralPath $positions -Encoding UTF8
    $ErrorActionPreference = 'Continue'
    $scoreText = & python $scorer --runs-root (Join-Path $temp 'JournalRuns') --positions-csv $positions --output (Join-Path $temp 'scores.json') 2>&1
    $scoreExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if($scoreExit -eq 0 -or ($scoreText -join "`n") -notmatch 'HOLDOUT GUARD') {
        throw "scorer: expected HOLDOUT GUARD rejection, got: $($scoreText -join ' ')"
    }

    Write-Host 'TEST-HOLDOUT-GUARD: PASS'
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
