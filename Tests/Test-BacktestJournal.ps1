param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference='Stop'
$journalWriter = Join-Path $ProjectRoot 'Tools\Write-YANSTDBacktestJournal.ps1'
$fixtureDir = Join-Path $ProjectRoot 'Backtests\Smoke'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('yanstd-journal-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $fixtureDir 'YANSTD_SMOKE_HYBRID.log') -Destination (Join-Path $temp 'tester-log-slice.log')
    Copy-Item -LiteralPath $(Join-Path (if ($env:MT5_DATA_PATH) { $env:MT5_DATA_PATH } else { Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common' }) 'YANSTD_SMOKE_HYBRID.htm') -Destination (Join-Path $temp 'report.htm')
    & $journalWriter -RunDirectory $temp
    if(-not $?) { throw 'journal writer failed' }
    $journal = Get-Content -Raw -LiteralPath (Join-Path $temp 'journal.json') | ConvertFrom-Json
    if($journal.HistoryQuality -ne '100% real ticks') { throw "expected 100% real ticks, got '$($journal.HistoryQuality)'" }
    if([int]$journal.TotalTrades -ne 7) { throw "expected 7 trades, got '$($journal.TotalTrades)'" }
    if(-not $journal.TestCompleted) { throw 'expected test completion marker' }
    if($null -eq $journal.Errors) { throw 'expected an error array even when empty' }
    if(@($journal.Errors).Count -ne 0) { throw 'zero-count report rows such as error 10016=0 must not be classified as errors' }
    Write-Host 'TEST-BACKTEST-JOURNAL: PASS'
} finally {
    Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue
}
