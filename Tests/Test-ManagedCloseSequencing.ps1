$ErrorActionPreference='Stop'
$test = Join-Path $PSScriptRoot 'Test-ManagedCloseRegression.ps1'
$temp = Join-Path $env:TEMP ('yanstd-managed-sequence-' + [guid]::NewGuid().ToString('N'))
$primary = Join-Path $temp 'primary'; $control = Join-Path $temp 'control'
New-Item -ItemType Directory -Force -Path $primary,$control | Out-Null
try {
    $badLog = @'
AA 2024.01.01 00:00:00 expert file added: Experts\YANSTD_AUDIT\YANSTD.ex5. 123 bytes loaded
AA 2024.01.01 00:00:00 [YANSTD CONFIG] version=TEST-BUILD
AA 2024.01.01 00:00:01 market sell 0.10 XAUUSD.FXSPREAD close #42
AA 2024.01.01 00:00:02 [ManagedClose] Closing position | ticket=42 reason=TIME_INVALIDATION
'@
    $badLog | Set-Content -LiteralPath (Join-Path $primary 'tester-log-slice.log') -Encoding UTF8
    $badLog | Set-Content -LiteralPath (Join-Path $control 'tester-log-slice.log') -Encoding UTF8
    $meta = '{"ExpertSHA256":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}'
    $meta | Set-Content -LiteralPath (Join-Path $primary 'run-metadata.json') -Encoding UTF8
    $meta | Set-Content -LiteralPath (Join-Path $control 'run-metadata.json') -Encoding UTF8
    $ErrorActionPreference='Continue'
    $text = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test -RunDirectory $primary -ControlRunDirectory $control 2>&1
    $exit = $LASTEXITCODE
    $ErrorActionPreference='Stop'
    if($exit -eq 0) { throw 'ManagedClose regression accepted close-before-request sequencing' }
    if(($text -join "`n") -notmatch 'after.*request|sequence') { throw "Expected sequence rejection, got: $($text -join ' ')" }
    Write-Host 'TEST-MANAGED-CLOSE-SEQUENCING: PASS'
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
