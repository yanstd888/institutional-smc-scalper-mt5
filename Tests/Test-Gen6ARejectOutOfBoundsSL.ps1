param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$defines=Get-Content -LiteralPath (Join-Path $ProjectRoot 'Modules\Defines.mqh') -Raw
$ea=Get-Content -LiteralPath (Join-Path $ProjectRoot 'YANSTD.mq5') -Raw
$engine=Get-Content -LiteralPath (Join-Path $ProjectRoot 'Modules\SignalEngine.mqh') -Raw
if($defines -notmatch 'bool\s+StopWithinBounds\s*\('){throw 'Shared StopWithinBounds predicate missing'}
if($ea -notmatch 'input bool\s+InpRejectOutOfBoundsSL\s*=\s*false'){throw 'Backward-compatible SL reject input missing/default changed'}
if($ea -notmatch 'bool\s+ApplyBoundSL\s*\('){throw 'EA SL wrapper must return acceptance'}
if(([regex]::Matches($ea,'if\s*\(!ApplyBoundSL\([^;]+\)\)\s*continue;')).Count -ne 2){throw 'Both EA callers must reject out-of-bounds SL'}
if($engine -notmatch 'bool\s+ApplyEngineStopBounds\s*\('){throw 'Engine SL wrapper must return acceptance'}
if(([regex]::Matches($engine,'if\s*\(!ApplyEngineStopBounds\([^;]+\)\)\s*continue;')).Count -ne 3){throw 'All three engine callers must reject out-of-bounds SL'}
Write-Host 'TEST-GEN6A-REJECT-OUT-OF-BOUNDS-SL: PASS'
