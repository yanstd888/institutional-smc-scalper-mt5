$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$test=Join-Path $PSScriptRoot 'Test-ManagedCloseRegression.ps1'
$sourceRoot=Join-Path $root 'Backtests\YANSTD-LIVE-SELECTION-MODULE\RegressionRuns'
$temp=Join-Path $env:TEMP ('yanstd-managed-hash-' + [guid]::NewGuid().ToString('N'))
$primary=Join-Path $temp 'primary'; $control=Join-Path $temp 'control'
New-Item -ItemType Directory -Force -Path $primary,$control | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'REG_MANAGED_CLOSE_20240201_HASHED\tester-log-slice.log') -Destination $primary
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'REG_MANAGED_CLOSE_CONTROL_20240709_HASHED\tester-log-slice.log') -Destination $control
    '{"ExpertSHA256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}' | Set-Content -LiteralPath (Join-Path $primary 'run-metadata.json') -Encoding UTF8
    '{"ExpertSHA256":"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"}' | Set-Content -LiteralPath (Join-Path $control 'run-metadata.json') -Encoding UTF8
    $ErrorActionPreference='Continue'
    $text=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test -RunDirectory $primary -ControlRunDirectory $control 2>&1
    $exit=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if($exit -eq 0) { throw 'ManagedClose regression accepted mismatched ExpertSHA256 builds' }
    if(($text -join "`n") -notmatch 'ExpertSHA256|same build') { throw "Expected hash mismatch rejection, got: $($text -join ' ')" }
    Write-Host 'TEST-MANAGED-CLOSE-HASH-REQUIRED: PASS'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
