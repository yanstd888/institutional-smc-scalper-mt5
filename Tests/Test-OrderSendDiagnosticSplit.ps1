$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$defines=Get-Content -Raw -LiteralPath (Join-Path $root 'Modules\Defines.mqh')
$diag=Get-Content -Raw -LiteralPath (Join-Path $root 'Modules\SignalDiagnostics.mqh')
$om=Get-Content -Raw -LiteralPath (Join-Path $root 'Modules\OrderManager.mqh')
$ea=Get-Content -Raw -LiteralPath (Join-Path $root 'YANSTD.mq5')

# 1) New diagnostic enum + label for the preflight stops-distance guard.
if(-not $defines.Contains('REJECT_ENTRY_STOPS_DISTANCE')){throw 'missing enum REJECT_ENTRY_STOPS_DISTANCE in Defines.mqh'}
if(-not $diag.Contains('case REJECT_ENTRY_STOPS_DISTANCE')){throw 'missing label case for REJECT_ENTRY_STOPS_DISTANCE'}
if(-not $diag.Contains('ENTRY_STOPS_DISTANCE')){throw 'missing rendered label ENTRY_STOPS_DISTANCE'}

# 2) The guard itself records the new enum (root-cause site, all callers route through it).
if(-not $om.Contains('Record(REJECT_ENTRY_STOPS_DISTANCE')){throw 'RejectIfEntryStopsTooClose does not record ENTRY_STOPS_DISTANCE'}
if(-not $om.Contains('LastRejectWasEntryStopsTooClose')){throw 'missing OrderManager flag getter LastRejectWasEntryStopsTooClose'}

# 3) EA: ORDER_SEND is reserved for post-send failures; guard-tripped entries must not reach it.
if($ea -match 'else\s+g_diagnostics\.Record\(REJECT_ORDER_SEND'){throw 'bare REJECT_ORDER_SEND else-branch still present in YANSTD.mq5'}
if(-not $ea.Contains('LastRejectWasEntryStopsTooClose')){throw 'EA does not consult the guard flag before recording ORDER_SEND'}

# 4) Internal lot-sizing failures are lot diagnostics, not order-send failures.
if(-not $ea.Contains('if(fillLots <= 0.0)')){throw 'market-fill sizing guard not found'}
if(-not $ea.Contains('Record(REJECT_LOT_TOO_SMALL, key)')){throw 'fillLots<=0 must record REJECT_LOT_TOO_SMALL'}

# 5) Version header must stay in sync with Modules\Defines.mqh (regression lock).
$m=[regex]::Match($defines,'YANSTD_VERSION\s+"([^"]+)"')
if(-not $m.Success){throw 'YANSTD_VERSION not found in Defines.mqh'}
if(-not $ea.Contains($m.Groups[1].Value)){throw ('YANSTD.mq5 header out of sync with Defines.mqh: ' + $m.Groups[1].Value)}

Write-Host 'TEST-ORDER-SEND-DIAGNOSTIC-SPLIT: PASS'
