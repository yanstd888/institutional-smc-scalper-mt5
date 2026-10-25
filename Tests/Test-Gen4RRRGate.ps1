$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$ea=Get-Content -Raw -LiteralPath (Join-Path $root 'YANSTD.mq5')
$auto=@([regex]::Matches($ea,'if\(InpUseMinimumRRRGate\)'))
if($auto.Count -lt 3){throw "Expected RRR enforcement in manual + BUY + SELL paths, found $($auto.Count)"}
if($ea -match 'InpUseMinimumRRRGate\s*&&\s*!IsStructuralExitMode\(\)'){throw 'RRR gate must not be bypassed for structural exits'}
foreach($anchor in @('double structuralTarget = GetStructuralTarget(limitP, ZONE_DEMAND);','double structuralTarget = GetStructuralTarget(limitP, ZONE_SUPPLY);')){
 if(-not $ea.Contains($anchor)){throw "Missing auto-limit RRR target path: $anchor"}
}
Write-Host 'TEST-GEN4-RRR-GATE: PASS'
