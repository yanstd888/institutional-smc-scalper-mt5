param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$ea=Get-Content -LiteralPath (Join-Path $ProjectRoot 'YANSTD.mq5') -Raw

# --- M0: M3 confirmation is a SOFT bonus, never a hard reject -------------
# The old hard reject (SETUP_HYBRID + _FALLBACK + !useM3RefinementContext -> continue)
# must be gone: a fallback POI without M3 confirmation stays a candidate.
if($ea -match 'SETUP_HYBRID[\s\S]{0,200}_FALLBACK[\s\S]{0,200}!useM3RefinementContext[\s\S]{0,200}continue;')
  {throw 'M0 still hard-rejects fallback POIs without M3 confirmation'}
# A confirmed M3 context must award a bounded score bonus instead.
if($ea -notmatch 'M3_CONFIRMED_SOFT_BONUS')
  {throw 'M0 soft M3-confirmation bonus constant missing'}
if($ea -notmatch 'm3ConfirmedContext\)\s*smcScore\s*\+=\s*M3_CONFIRMED_SOFT_BONUS')
  {throw 'M0 soft M3-confirmation bonus is not applied to the score'}

# --- M1: same-direction re-entry cooldown (not per-zone) ------------------
if($ea -notmatch 'SAME_DIRECTION_REENTRY_COOLDOWN_BARS')
  {throw 'M1 same-direction re-entry cooldown constant missing'}
if($ea -notmatch 'g_lastEntryBarTime')
  {throw 'M1 cooldown state (last entry bar time) missing'}
# Cooldown must gate the fallback scan path that caused the churn.
if($ea -notmatch 'SameDirectionReentryBlocked\(')
  {throw 'M1 cooldown guard helper missing'}

# --- M2: variant whitelist widened so OB/FVG paths are actually exercised --
foreach($v in @('FIB_618','FIB_705','FIB_790','OB_15','OB_45','FVG_50'))
  {if($ea -notmatch [regex]::Escape($v)){throw "Variant $v not referenced"}}

Write-Host 'TEST-GEN6C-REFINEMENTS: PASS'
