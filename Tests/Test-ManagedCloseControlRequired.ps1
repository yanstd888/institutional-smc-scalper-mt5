$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$test = Join-Path $PSScriptRoot 'Test-ManagedCloseRegression.ps1'
$fixture = Join-Path $root 'Backtests\YANSTD-LIVE-SELECTION-MODULE\RegressionRuns\REG_MANAGED_CLOSE_20240201_AFTER_FIX'
$ErrorActionPreference = 'Continue'
$text = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test -RunDirectory $fixture 2>&1
$exit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if($exit -eq 0) { throw 'ManagedClose regression accepted a run without mandatory market-close control' }
if(($text -join "`n") -notmatch 'ControlRunDirectory') { throw "Expected missing ControlRunDirectory error, got: $($text -join ' ')" }
Write-Host 'TEST-MANAGED-CLOSE-CONTROL-REQUIRED: PASS'
