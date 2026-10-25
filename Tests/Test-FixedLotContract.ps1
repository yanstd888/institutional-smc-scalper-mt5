param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$files=@(
 (Join-Path $ProjectRoot 'YANSTD.mq5'),
 (Join-Path $ProjectRoot 'Modules\SignalEngine.mqh')
)
$text=($files|ForEach-Object {Get-Content -Raw -LiteralPath $_})-join "`n"
foreach($forbidden in @('InpFixedLot * lotMult','fixedLot * gradeMult')) {
 if($text.Contains($forbidden)){throw "Fixed-lot contract violated: $forbidden"}
}
if(-not $text.Contains('? InpFixedLot') -or ([regex]::Matches($text,'m_rc\.RoundLotToStep\(fixedLot\)')).Count -ne 3) {
 throw 'Fixed-lot sizing must bypass grade multipliers in auto and all market entry paths'
}
Write-Host 'TEST-FIXED-LOT-CONTRACT: PASS'
