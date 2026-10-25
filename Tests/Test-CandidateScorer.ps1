$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tool=Join-Path $root 'Tools\score_backtest_candidates.py'
$temp=Join-Path $env:TEMP ('yanstd-score-' + [guid]::NewGuid().ToString('N'))
$runs=Join-Path $temp 'Runs'; $out=Join-Path $temp 'scores.json'; $csv=Join-Path $temp 'positions.csv'
New-Item -ItemType Directory -Force -Path $runs | Out-Null
try {
    function New-Journal([string]$run,[double]$pf,[double]$payoff,[double]$recovery,[string]$dd,[object[]]$errors) {
        $dir=Join-Path $runs $run; New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [ordered]@{TestCompleted=$true;ProfitFactor="$pf";ExpectedPayoff="$payoff";RecoveryFactor="$recovery";EquityDrawdownMax=$dd;Errors=$errors} |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dir 'journal.json') -Encoding UTF8
    }
    New-Journal 'M0_HYBRID_GOOD_SELECT_DEV' 1.10 1.0 1.2 '100.00 (10.00%)' @()
    New-Journal 'M0_HYBRID_GOOD_SELECT_VALIDATE' 1.15 2.0 1.5 '150.00 (15.00%)' @()
    New-Journal 'M1_MSNR_BAD_SELECT_DEV' 1.20 2.0 2.0 '100.00 (10.00%)' @()
    New-Journal 'M1_MSNR_BAD_SELECT_VALIDATE' 1.30 3.0 2.0 '100.00 (10.00%)' @('tester agent error')
    @'
run_id,split,mode,position_id,entry_year,net_profit
M0_HYBRID_GOOD_SELECT_DEV,DEV,HYBRID,d1,2022,10
M0_HYBRID_GOOD_SELECT_VALIDATE,VALIDATE,HYBRID,v1,2023,10
M0_HYBRID_GOOD_SELECT_VALIDATE,VALIDATE,HYBRID,v2,2024,20
M1_MSNR_BAD_SELECT_DEV,DEV,MSNR_SOFTSMC,d2,2022,10
M1_MSNR_BAD_SELECT_VALIDATE,VALIDATE,MSNR_SOFTSMC,v3,2023,10
M1_MSNR_BAD_SELECT_VALIDATE,VALIDATE,MSNR_SOFTSMC,v4,2024,10
'@ | Set-Content -LiteralPath $csv -Encoding UTF8
    & python $tool --runs-root $runs --positions-csv $csv --output $out --min-validation-positions 2
    if(-not $?) { throw 'Candidate scorer returned failure' }
    $result=Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
    $good=@($result.candidates | Where-Object candidate_id -eq 'M0_HYBRID_GOOD')[0]
    $bad=@($result.candidates | Where-Object candidate_id -eq 'M1_MSNR_BAD')[0]
    if(-not $good.passed) { throw "Expected GOOD to pass: $($good.fail_reasons -join '; ')" }
    if($bad.passed) { throw 'Expected BAD to fail on material execution error' }
    if('validation:material_execution_error' -notin @($bad.fail_reasons)) { throw 'Missing material-error rejection reason' }
    Write-Host 'TEST-CANDIDATE-SCORER: PASS'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
