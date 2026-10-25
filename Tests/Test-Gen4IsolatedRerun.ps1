param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$worker=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'Tools\Run-YANSTDGen4BatchWorker.ps1')
$starter=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'Tools\Start-YANSTDGen4Batch.ps1')
if($worker -notmatch '\[string\]\$OutputDir'){ throw 'RED: worker cannot isolate a replacement matrix output root' }
if($worker -match "\$outputDir='Runs_Gen4_FixedLot'"){ throw 'RED: worker still hardcodes the old matrix root' }
if($starter -notmatch '\[string\]\$OutputDir' -or $starter -notmatch '-OutputDir'){ throw 'RED: launcher does not forward isolated output root' }
Write-Output 'TEST-GEN4-ISOLATED-RERUN: PASS'
