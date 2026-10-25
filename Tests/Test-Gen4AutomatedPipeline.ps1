param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'Tools\Run-YANSTDGen4BatchWorker.ps1'
$text=Get-Content -Raw -LiteralPath $path
foreach($required in @('OutputDir','AttributionDir','extract_backtest_attribution.py','apply_cost_stress.py','score_backtest_candidates.py','check_gen4_fixed_lot.py','PythonExe','Postprocess')) {
 if(-not $text.Contains($required)){throw "Gen4 automated pipeline missing: $required"}
}
Write-Host 'TEST-GEN4-AUTOMATED-PIPELINE: PASS'
