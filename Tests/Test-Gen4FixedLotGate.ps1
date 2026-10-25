param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$script=Join-Path $ProjectRoot 'Tools\check_gen4_fixed_lot.py'
if(-not(Test-Path -LiteralPath $script)){throw 'Fixed-lot gate script is missing'}
$positions=Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE\Attribution_Gen4_FixedLot\positions.csv'
& python $script --positions-csv $positions
if($LASTEXITCODE -ne 0){throw 'Fixed-lot gate script failed'}
Write-Host 'TEST-GEN4-FIXED-LOT-GATE: PASS'
