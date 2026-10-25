param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$text=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'Modules\OrderManager.mqh')
foreach($required in @('lastSeenTime >= 0','TimeCurrent() + m_tracks[k].lastSeenTime > 300','The close transaction can arrive after the position vanishes')) {
 if(-not $text.Contains($required)){throw "Missing absent-position grace behavior: $required"}
}
Write-Host 'TEST-TRACK-PURGE-GRACE: PASS'
