param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$ea=Get-Content -LiteralPath (Join-Path $ProjectRoot 'YANSTD.mq5') -Raw
$engine=Get-Content -LiteralPath (Join-Path $ProjectRoot 'Modules\SignalEngine.mqh') -Raw

# M0 (Gen-6C): M3 confirmation is a SOFT score bonus, not a hard fallback gate.
# (Gen-6B hard-rejected fallback POIs; the annual run showed that starved M0 to
# 14 trades at PF 0.335, so the decision is now soft bonus +8.)
if($ea -match 'SETUP_HYBRID[\s\S]{0,200}_FALLBACK[\s\S]{0,200}!useM3RefinementContext[\s\S]{0,200}continue;')
  {throw 'M0 fallback is still hard-rejected without M3 confirmation'}
if($ea -notmatch 'm3ConfirmedContext\)\s*smcScore\s*\+=\s*M3_CONFIRMED_SOFT_BONUS')
  {throw 'M0 soft M3-confirmation bonus missing'}

# M1: OTE/Fibonacci remain bonuses, never a PARTIAL-zone hard dependency.
if($engine -match 'if\s*\(!hasMap\s*\|\|\s*!map\.isInOTE\)')
  {throw 'M1 PARTIAL zone still hard-requires OTE'}
if($engine -notmatch 'if\(map\.isInOTE\)\s+smcScore\s*\+=\s*8\.0')
  {throw 'M1 OTE soft bonus missing'}
if($engine -notmatch 'FIB_LEVEL_705\)\s+smcScore\s*\+=\s*6\.0')
  {throw 'M1 Fibonacci soft bonus missing'}

# M2 telemetry: caller-owned path plus winning POI freshness, no comment-format change.
foreach($label in @('CONFIRMED','FALLBACK','DIRECT','MANUAL'))
  {if($ea -notmatch ('ManageAutoLimitOrders\([^;]*"'+$label+'"')){throw "Missing entry path $label"}}
if($ea -notmatch 'Freshness=') {throw 'Placement freshness telemetry missing'}
if($ea -notmatch 'Path=') {throw 'Placement path telemetry missing'}
Write-Host 'TEST-GEN6B-MODE-CONTRACTS: PASS'
