param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$text=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'Modules\OrderManager.mqh')
if(-not $text.Contains('[YANSTD TRACK_PURGED]')){throw 'Missing stale-track purge diagnostic'}
Write-Host 'TEST-TRACK-PURGE-DIAGNOSTIC: PASS'
