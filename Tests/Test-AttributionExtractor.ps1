$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'Tools\extract_backtest_attribution.py'
$tempRoot = Join-Path $env:TEMP ('yanstd-attribution-' + [guid]::NewGuid().ToString('N'))
$runDir = Join-Path $tempRoot 'FIXTURE_M2_SMC_SOFTMSNR_C99_VALIDATE'
$outDir = Join-Path $tempRoot 'out'
New-Item -ItemType Directory -Force -Path $runDir,$outDir | Out-Null
try {
    $report = @'
<html><body><table>
<tr><td>Orders</td></tr>
<tr><td>Open Time</td><td>Order</td><td>Symbol</td><td>Type</td><td>Volume</td><td>Price</td><td>S / L</td><td>T / P</td><td>Time</td><td>State</td><td>Comment</td></tr>
<tr><td>2024.01.02 13:00:00</td><td>10</td><td>XAUUSD.FXSPREAD</td><td>buy limit</td><td>1.00 / 1.00</td><td>2000.000</td><td>1990.000</td><td>2020.000</td><td>2024.01.02 13:01:00</td><td>filled</td><td>SMC_T2G5_B-1_EABC</td></tr>
<tr><td>Deals</td></tr>
<tr><td>Time</td><td>Deal</td><td>Symbol</td><td>Type</td><td>Direction</td><td>Volume</td><td>Price</td><td>Order</td><td>Commission</td><td>Swap</td><td>Profit</td><td>Balance</td><td>Comment</td></tr>
<tr><td>2024.01.01 00:00:00</td><td>1</td><td></td><td>balance</td><td></td><td></td><td></td><td></td><td>0.00</td><td>0.00</td><td>10000.00</td><td>10000.00</td><td></td></tr>
<tr><td>2024.01.02 13:01:00</td><td>20</td><td>XAUUSD.FXSPREAD</td><td>buy</td><td>in</td><td>1.00</td><td>2000.100</td><td>10</td><td>0.00</td><td>0.00</td><td>0.00</td><td>10000.00</td><td>SMC_T2G5_B-1_EABC</td></tr>
<tr><td>2024.01.02 13:10:00</td><td>21</td><td>XAUUSD.FXSPREAD</td><td>sell</td><td>out</td><td>0.50</td><td>2005.000</td><td>11</td><td>0.00</td><td>0.00</td><td>50.00</td><td>10050.00</td><td></td></tr>
<tr><td>2024.01.02 13:20:00</td><td>22</td><td>XAUUSD.FXSPREAD</td><td>sell</td><td>out</td><td>0.50</td><td>1998.000</td><td>12</td><td>0.00</td><td>0.00</td><td>-20.00</td><td>10030.00</td><td>sl 1998.000</td></tr>
</table></body></html>
'@
    Set-Content -LiteralPath (Join-Path $runDir 'report.htm') -Value $report -Encoding Unicode
    @'
AA	0	00:00:00.000	Core 01	2024.01.02 13:00:00   YANSTD Auto Limit: BUY LIMIT Placed [FVG 50% CE] @ 2000.000 | SL:1990.000 (100.0p) | Lot:1.00 | Session=SESSION_NEWYORK | Score:88.5
AA	0	00:00:00.000	Core 01	2024.01.02 13:10:00   [YANSTD] [PartialClose] TP1 50.0% of initial target closed | Ticket=10 ClosedLots=0.50 RemainingLots=0.50
AA	0	00:00:00.000	Core 01	2024.01.02 13:20:00   [YANSTD TRADE_RESULT] position=10 | deal=22 | initialVolume=0.10 | initialRiskPrice=10.000 | initialRiskMoney=1000.00 | NetR=0.03 | MFE=0.50R | MAE=0.20R | maxSpreadPoints=30.0
'@ | Set-Content -LiteralPath (Join-Path $runDir 'tester-log-slice.log') -Encoding UTF8
    '{"Mode":"InpSetupMode=2","FromDate":"2024.01.01","ToDate":"2025.01.01"}' | Set-Content -LiteralPath (Join-Path $runDir 'run-metadata.json') -Encoding UTF8

    & python $tool --runs-root $tempRoot --output-dir $outDir --run-id-prefix 'FIXTURE_'
    if(-not $?) { throw 'Attribution extractor returned failure' }

    $positions = @(Import-Csv -LiteralPath (Join-Path $outDir 'positions.csv'))
    $legs = @(Import-Csv -LiteralPath (Join-Path $outDir 'exit_legs.csv'))
    if($positions.Count -ne 1) { throw "Expected 1 position, found $($positions.Count)" }
    if($legs.Count -ne 2) { throw "Expected 2 exit legs, found $($legs.Count)" }
    if($positions[0].grade -ne 'B') { throw "Expected grade B, found $($positions[0].grade)" }
    if($positions[0].entry_variant -ne 'FVG_50') { throw "Expected FVG_50, found $($positions[0].entry_variant)" }
    if($positions[0].session -ne 'SESSION_NEWYORK') { throw "Expected New York session, found $($positions[0].session)" }
    if([double]$positions[0].net_profit -ne 30.0) { throw "Expected net profit 30, found $($positions[0].net_profit)" }
    if([double]$positions[0].initial_risk_price -ne 10.0) { throw "Expected initial risk price 10, found $($positions[0].initial_risk_price)" }
    if([double]$positions[0].initial_risk_money -ne 1000.0) { throw "Expected initial risk money 1000, found $($positions[0].initial_risk_money)" }
    if([double]$positions[0].initial_volume -ne 0.10) { throw "Expected initial volume 0.10, found $($positions[0].initial_volume)" }
    if([double]$positions[0].net_r -ne 0.03) { throw "Expected NetR 0.03, found $($positions[0].net_r)" }
    if([double]$positions[0].mfe_r -ne 0.50 -or [double]$positions[0].mae_r -ne 0.20) { throw 'Expected MFE/MAE telemetry 0.50R/0.20R' }
    if([double]$positions[0].max_spread_points -ne 30.0) { throw "Expected max spread 30 points, found $($positions[0].max_spread_points)" }
    if($legs[0].exit_reason -ne 'TP1_PARTIAL') { throw "Expected TP1_PARTIAL, found $($legs[0].exit_reason)" }
    if($legs[1].exit_reason -ne 'SL') { throw "Expected SL, found $($legs[1].exit_reason)" }
    Write-Host 'TEST-ATTRIBUTION-EXTRACTOR: PASS'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
