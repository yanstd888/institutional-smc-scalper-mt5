$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot; $tool=Join-Path $root 'Tools\score_backtest_candidates.py'
$temp=Join-Path $env:TEMP ('yanstd-g4-score-'+[guid]::NewGuid().ToString('N')); $runs=Join-Path $temp 'Runs'; $csv=Join-Path $temp 'positions.csv';$out=Join-Path $temp 'out.json'
New-Item -ItemType Directory -Force $runs|Out-Null
try {
 foreach($stage in @('FIT','VALIDATE')) { $id="M2_SMC_G4_WF1_$stage";$d=Join-Path $runs $id;New-Item -ItemType Directory -Force $d|Out-Null; @{TestCompleted=$true;ProfitFactor='1.2';ExpectedPayoff='1';RecoveryFactor='1.1';EquityDrawdownMax='10 (1.0%)';Errors=@();TotalTrades='3'}|ConvertTo-Json|Set-Content (Join-Path $d 'journal.json'); @{FromDate='2007.01.01';ToDate='2013.01.01'}|ConvertTo-Json|Set-Content (Join-Path $d 'run-metadata.json') }
 @'
run_id,entry_year,net_profit,direction
M2_SMC_G4_WF1_FIT,2010,10,BUY
M2_SMC_G4_WF1_FIT,2010,-5,SELL
M2_SMC_G4_WF1_VALIDATE,2014,10,BUY
M2_SMC_G4_WF1_VALIDATE,2014,-5,SELL
'@|Set-Content $csv
 & python $tool --runs-root $runs --positions-csv $csv --output $out --min-validation-positions 1
 if(-not $?) {throw 'scorer failed'};$r=Get-Content $out -Raw|ConvertFrom-Json;$w=$r.candidates[0].windows.WF1
 if($w.FIT.trade_count -ne 3 -or $w.FIT.buy_count -ne 1 -or $w.FIT.sell_count -ne 1 -or $w.FIT.from_date -ne '2007.01.01'){throw 'RED: missing per-window report'}
 Write-Host 'TEST-GEN4-SCORER-REPORTING: PASS'
}finally{Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue}