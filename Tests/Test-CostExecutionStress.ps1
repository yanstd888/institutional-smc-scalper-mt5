param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$runnerPath = Join-Path $ProjectRoot 'Tools\Run-YANSTDBacktestJob.ps1'
$costTool = Join-Path $ProjectRoot 'Tools\apply_cost_stress.py'

# 1. Runner must wire DelayMs into tester ExecutionMode (no hardcoded 0).
$runnerText = Get-Content -LiteralPath $runnerPath -Raw
Assert-True ($runnerText -match '\$DelayMs') 'runner must accept a DelayMs parameter'
Assert-True ($runnerText -match 'ExecutionMode=\$DelayMs') 'runner must write ExecutionMode from DelayMs'

# 2. Cost-stress tool must exist.
Assert-True (Test-Path -LiteralPath $costTool) 'Tools/apply_cost_stress.py must exist'

# 3. Deterministic fixture: swap triple-Wednesday + round-turn slippage.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('YANSTD_CostStress_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    $positionsCsv = Join-Path $temp 'positions.csv'
    @(
        'run_id,split,mode,position_id,direction,entry_volume,entry_price,entry_time,exit_time,net_profit',
        'FIX_DEV,DEV,HYBRID,FIX:A,SELL,1.0,2000.000,2024.01.01 10:00:00,2024.01.02 10:00:00,50.0',
        'FIX_DEV,DEV,HYBRID,FIX:B,BUY,2.0,2000.000,2024.01.03 10:00:00,2024.01.04 10:00:00,200.0'
    ) | Set-Content -LiteralPath $positionsCsv -Encoding UTF8
    $outCsv = Join-Path $temp 'stressed.csv'
    $summaryJson = Join-Path $temp 'summary.json'
    & python $costTool --positions-csv $positionsCsv --output-csv $outCsv --summary-json $summaryJson
    if($LASTEXITCODE -ne 0) { throw 'apply_cost_stress.py failed on fixture' }
    $rows = @(Import-Csv -LiteralPath $outCsv)
    Assert-True ($rows.Count -eq 2) 'fixture must yield 2 stressed positions'
    $a = @($rows | Where-Object { $_.position_id -eq 'FIX:A' })[0]
    $b = @($rows | Where-Object { $_.position_id -eq 'FIX:B' })[0]
    Assert-True ([double]$a.swap_cost_usd -eq -15.0) ('A swap must be -15, got ' + $a.swap_cost_usd)
    Assert-True ([double]$a.net_after_swap -eq 35.0) ('A net_after_swap must be 35, got ' + $a.net_after_swap)
    Assert-True ([double]$a.net_after_swap_slip100 -eq 15.0) ('A slip100 must be 15, got ' + $a.net_after_swap_slip100)
    Assert-True ([double]$a.net_after_swap_slip200 -eq -5.0) ('A slip200 must be -5, got ' + $a.net_after_swap_slip200)
    Assert-True ([double]$b.swap_cost_usd -eq -180.0) ('B swap must be -180 triple Wednesday, got ' + $b.swap_cost_usd)
    Assert-True ([double]$b.net_after_swap -eq 20.0) ('B net_after_swap must be 20, got ' + $b.net_after_swap)
    Assert-True ([double]$b.net_after_swap_slip100 -eq -20.0) ('B slip100 must be -20, got ' + $b.net_after_swap_slip100)
    Assert-True ([double]$b.net_after_swap_slip200 -eq -60.0) ('B slip200 must be -60, got ' + $b.net_after_swap_slip200)
    Write-Host 'TEST-COST-EXECUTION-STRESS: PASS'
}
finally {
    Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue
}
