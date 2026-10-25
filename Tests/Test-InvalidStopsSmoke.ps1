param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$log=Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE\Runs_Gen4_InvalidStopsSmoke\G4S02_INVALID_STOPS_SMOKE_2022Q4\tester-log-slice.log'
if(-not(Test-Path -LiteralPath $log)){ throw "Smoke log missing: $log" }
$n=@([regex]::Matches((Get-Content -Raw -LiteralPath $log),'failed modify .*\[Invalid stops\]','IgnoreCase')).Count
if($n -ne 0){ throw "Invalid-stop modify attempts: $n (expected 0)" }
Write-Output 'TEST-INVALID-STOPS-SMOKE: PASS (0 invalid-stop modify attempts)'
