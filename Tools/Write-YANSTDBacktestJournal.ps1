param(
    [Parameter(Mandatory)][string]$RunDirectory
)
$ErrorActionPreference='Stop'
$logPath=Join-Path $RunDirectory 'tester-log-slice.log'
$reportPath=Join-Path $RunDirectory 'report.htm'
if(-not (Test-Path -LiteralPath $logPath)) { throw "Missing tester journal: $logPath" }
if(-not (Test-Path -LiteralPath $reportPath)) { throw "Missing tester report: $reportPath" }

$log=Get-Content -Raw -LiteralPath $logPath
$html=Get-Content -Raw -LiteralPath $reportPath
$text=([System.Net.WebUtility]::HtmlDecode(($html -replace '<[^>]+>',' ')) -replace '\s+',' ').Trim()
function Metric([string]$Pattern) {
    $m=[regex]::Match($text,$Pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}
$patterns=@(
    '(?i)\[YANSTD ERROR\].*$',
    '(?i)\b(?:fatal error|tester agent error|initialization failed)\b.*$'
)
$errors=@()
foreach($pattern in $patterns) {
    foreach($m in [regex]::Matches($log,$pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)) {
        $value=$m.Value.Trim()
        if($value -and $errors -notcontains $value) { $errors += $value }
    }
}
$diagnostics=@{}
foreach($m in [regex]::Matches($log,'\[YANSTD DIAGNOSTIC\]\s+([A-Z0-9_]+)=([0-9]+)\s+\(([0-9.]+)%\)')) {
    $diagnostics[$m.Groups[1].Value]=[ordered]@{ Count=[int64]$m.Groups[2].Value; Percent=[double]$m.Groups[3].Value }
}
$journal=[ordered]@{
    GeneratedUtc=(Get-Date).ToUniversalTime().ToString('o')
    TestCompleted=($log -match 'Test passed in')
    HistoryQuality=(Metric 'History Quality:\s*([^\r\n]+?)\s+Bars:')
    Bars=(Metric 'Bars:\s*([0-9 ]+)\s+Ticks:')
    Ticks=(Metric 'Ticks:\s*([0-9 ]+)\s+Symbols:')
    NetProfit=(Metric 'Total Net Profit:\s*([-0-9 .]+?)\s+Balance Drawdown')
    ProfitFactor=(Metric 'Profit Factor:\s*([-0-9.]+)')
    ExpectedPayoff=(Metric 'Expected Payoff:\s*([-0-9.]+)')
    RecoveryFactor=(Metric 'Recovery Factor:\s*([-0-9.]+)')
    SharpeRatio=(Metric 'Sharpe Ratio:\s*([-0-9.]+)')
    EquityDrawdownMax=(Metric 'Equity Drawdown Maximal:\s*([0-9 .]+\s+\([0-9.]+%\))')
    TotalTrades=(Metric 'Total Trades:\s*([0-9 ]+)\s+Short Trades')
    TotalDeals=(Metric 'Total Deals:\s*([0-9 ]+)\s+Profit Trades')
    Errors=@($errors)
    Diagnostics=$diagnostics
    TesterLogSHA256=(Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash
    ReportSHA256=(Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
}
$journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RunDirectory 'journal.json') -Encoding UTF8
Write-Host "JOURNAL WRITTEN: $RunDirectory"
