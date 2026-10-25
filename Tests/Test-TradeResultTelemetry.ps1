$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Get-Content -Raw -LiteralPath (Join-Path $root 'YANSTD.mq5')
foreach($required in @('[YANSTD TRADE_RESULT]','initialVolume=','initialRiskPrice=','initialRiskMoney=','NetR=','MFE=','MAE=','maxSpreadPoints=')) {
    if(-not $source.Contains($required)) { throw "Missing unconditional trade telemetry field: $required" }
}
Write-Host 'TEST-TRADE-RESULT-TELEMETRY: PASS'
