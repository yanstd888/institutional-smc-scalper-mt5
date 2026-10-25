param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$text=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'YANSTD.mq5')
foreach($marker in @('[YANSTD TRACK_REGISTER_SKIP]','[YANSTD TRACK_REGISTER_FAIL]')) {
 if(-not $text.Contains($marker)){throw "Missing track-registration diagnostic: $marker"}
}
Write-Host 'TEST-TRACK-REGISTRATION-DIAGNOSTICS: PASS'
