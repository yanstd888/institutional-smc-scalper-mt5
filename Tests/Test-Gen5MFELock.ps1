param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$ea=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'YANSTD.mq5')
$pc=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'Modules\PartialClose.mqh')
if($ea -match 'InpUseMilestoneLock\s*&&\s*pos\.tp1Done'){throw 'RED: MFE lock still requires TP1'}
if($ea -match 'InpUseMilestoneLock[^\r\n]*!IsStructuralExitMode'){throw 'RED: MFE lock disabled in structural exit'}
if($pc -notmatch 'pos\.maxFavorableR\s*>=\s*triggerR'){throw 'RED: milestone trigger does not use remembered MFE'}
if($pc -notmatch 'lockR\s*\*\s*pos\.initialRiskPrice'){throw 'RED: lock target is not risk-relative'}
Write-Host 'TEST-GEN5-MFE-LOCK: PASS'
