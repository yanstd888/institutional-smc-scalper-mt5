param(
    [Parameter(Mandatory)][string]$PresetPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$FromDate,
    [Parameter(Mandatory)][string]$ToDate,
    [int]$DelayMs = 0,
    [switch]$AllowHoldout,
    [switch]$AllowDynamicRisk,
    [string]$Symbol = 'XAUUSD.FXSPREAD',
    [string]$TerminalExe = $(if ($env:MT5_TERMINAL_PATH) { $env:MT5_TERMINAL_PATH } else { 'C:\Program Files\MetaTrader 5\terminal64.exe' }),
    [string]$TerminalDataRoot = $(if ($env:MT5_DATA_PATH) { $env:MT5_DATA_PATH } else { Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common' }),
    [string]$OutputRoot = $(Join-Path (Split-Path -Parent $PSScriptRoot) 'Runs'),
    [string]$ProjectRoot = $(Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
if($DelayMs -notin @(0,100,300,500)) { throw "DelayMs must be one of 0/100/300/500 ms, got: $DelayMs" }
$fromDateValue = [datetime]::ParseExact($FromDate, 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
$toDateValue = [datetime]::ParseExact($ToDate, 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
$holdoutBoundary = [datetime]::ParseExact('2025.01.01', 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
if($fromDateValue -ge $toDateValue) { throw "Invalid tester date range: $FromDate .. $ToDate" }
if(-not $AllowHoldout -and ($fromDateValue -ge $holdoutBoundary -or $toDateValue -gt $holdoutBoundary)) {
    throw "HOLDOUT GUARD: backtest dates must remain before 2025.01.01 (exclusive end may equal boundary); requested $FromDate .. $ToDate"
}
if(-not (Test-Path -LiteralPath $TerminalExe)) { throw "MT5 terminal is missing: $TerminalExe" }
if(-not (Test-Path -LiteralPath $PresetPath)) { throw "Preset is missing: $PresetPath" }
$expertPath = Join-Path $TerminalDataRoot 'MQL5\Experts\YANSTD_AUDIT\YANSTD.ex5'
if(-not (Test-Path -LiteralPath $expertPath)) { throw "Staged EA is missing: $expertPath" }
$expertSHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $expertPath).Hash
$profileDir = Join-Path $TerminalDataRoot 'MQL5\Profiles\Tester'
$configDir = Join-Path $TerminalDataRoot 'config'
$runDir = Join-Path $OutputRoot $RunId
New-Item -ItemType Directory -Force -Path $profileDir,$configDir,$runDir | Out-Null

$modeLine = @(Get-Content -LiteralPath $PresetPath | Where-Object { $_ -match '^InpSetupMode=' } | Select-Object -First 1)[0]
$utcLine = @(Get-Content -LiteralPath $PresetPath | Where-Object { $_ -match '^InpTesterUTCOffsetWinter=' } | Select-Object -First 1)[0]
$dstLine = @(Get-Content -LiteralPath $PresetPath | Where-Object { $_ -match '^InpTesterUseEuropeanDST=' } | Select-Object -First 1)[0]
if($modeLine -notmatch '^InpSetupMode=[012]$') { throw "Invalid setup mode: $modeLine" }
if($utcLine -ne 'InpTesterUTCOffsetWinter=0' -or $dstLine -notin @('InpTesterUseEuropeanDST=0','InpTesterUseEuropeanDST=false')) { throw "Tester clock contract violated: $utcLine / $dstLine" }
$fixedLotLine = @(Get-Content -LiteralPath $PresetPath | Where-Object { $_ -match '^InpFixedLot=' } | Select-Object -First 1)[0]
$dynamicRiskLine = @(Get-Content -LiteralPath $PresetPath | Where-Object { $_ -match '^InpUseDynamicRisk=' } | Select-Object -First 1)[0]
if($AllowDynamicRisk) {
    if($fixedLotLine -ne 'InpFixedLot=0.0') { throw "Dynamic-risk research contract violated: expected InpFixedLot=0.0, got $fixedLotLine" }
} elseif($fixedLotLine -ne 'InpFixedLot=0.10' -or $dynamicRiskLine -notin @('InpUseDynamicRisk=0','InpUseDynamicRisk=false')) {
    throw "Fixed-lot research contract violated: $fixedLotLine / $dynamicRiskLine"
}
$keys = @((Get-Content -LiteralPath $PresetPath | Where-Object { $_ -match '^([A-Za-z_][A-Za-z0-9_]*)=' } | ForEach-Object { ($_ -split '=',2)[0] }))
$eaInputs = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'YANSTD.mq5') | Where-Object { $_ -match '^\s*input\s+' } | ForEach-Object { if ($_ -match 'input\s+(?:[\w\[\]*]+\s+)?(\w+)\s*=') { $matches[1] } })
$expectedCount = ($eaInputs | Sort-Object -Unique).Count
if($keys.Count -ne $expectedCount -or @($keys | Sort-Object -Unique).Count -ne $expectedCount) {
    throw "Preset schema mismatch (preset $($keys.Count) != EA $($expectedCount)); check new inputs"
}

$presetName = "$RunId.set"
Copy-Item -LiteralPath $PresetPath -Destination (Join-Path $profileDir $presetName) -Force
Copy-Item -LiteralPath $PresetPath -Destination (Join-Path $runDir 'preset.set') -Force
$reportBase = "YANSTD_$RunId"
$reportPath = Join-Path $TerminalDataRoot "$reportBase.htm"
Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
$todayLog = Join-Path $TerminalDataRoot ("Tester\logs\" + (Get-Date -Format 'yyyyMMdd') + '.log')
$beforeLines = if(Test-Path -LiteralPath $todayLog) { @(Get-Content -LiteralPath $todayLog).Count } else { 0 }
$iniPath = Join-Path $configDir "$RunId.ini"
@"
[Common]
ProxyEnable=0
NewsEnable=0

[Tester]
Expert=YANSTD_AUDIT\YANSTD.ex5
ExpertParameters=$presetName
Symbol=$Symbol
Period=M3
Deposit=10000
Currency=USD
Leverage=2000
Model=4
ExecutionMode=$DelayMs
Optimization=0
FromDate=$FromDate
ToDate=$ToDate
ForwardMode=0
Report=$reportBase
ReplaceReport=1
ShutdownTerminal=1
Visual=0
UseLocal=1
UseRemote=0
UseCloud=0
"@ | Set-Content -LiteralPath $iniPath -Encoding ASCII
Copy-Item -LiteralPath $iniPath -Destination (Join-Path $runDir 'tester.ini') -Force
$meta = [ordered]@{ RunId=$RunId; ExpertPath=$expertPath; ExpertSHA256=$expertSHA256; Preset=(Resolve-Path $PresetPath).Path; PresetSHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $PresetPath).Hash; Symbol=$Symbol; Period='M3'; Model=4; DelayMs=$DelayMs; ExecutionMode=$DelayMs; FromDate=$FromDate; ToDate=$ToDate; Mode=$modeLine; FixedLot=0.10; DynamicRiskEnabled=$false; UTCOffset=$utcLine; DST=$dstLine; StartedUtc=(Get-Date).ToUniversalTime().ToString('o') }
$meta | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'run-metadata.json') -Encoding UTF8

$p = Start-Process -FilePath $TerminalExe -ArgumentList "/config:$iniPath" -PassThru -Wait
$afterLog = Join-Path $TerminalDataRoot ("Tester\logs\" + (Get-Date -Format 'yyyyMMdd') + '.log')
if(-not (Test-Path -LiteralPath $afterLog)) { throw "${RunId}: tester log not created" }
$logOffset = if($afterLog -eq $todayLog) { $beforeLines } else { 0 }
$runLines = @((Get-Content -LiteralPath $afterLog) | Select-Object -Skip $logOffset)
$runLines | Set-Content -LiteralPath (Join-Path $runDir 'tester-log-slice.log') -Encoding UTF8
$runText = $runLines -join "`n"
if($runText -notmatch [regex]::Escape($modeLine)) { throw "${RunId}: tester log does not confirm requested mode" }
if($runText -notmatch 'Test passed in') { throw "${RunId}: tester did not report successful completion" }
if(-not (Test-Path -LiteralPath $reportPath)) { throw "${RunId}: MT5 report missing: $reportPath" }
Copy-Item -LiteralPath $reportPath -Destination (Join-Path $runDir 'report.htm') -Force
$journalWriter = Join-Path $PSScriptRoot 'Write-YANSTDBacktestJournal.ps1'
& $journalWriter -RunDirectory $runDir
if(-not $?) { throw "${RunId}: journal writer failed" }
$meta.FinishedUtc=(Get-Date).ToUniversalTime().ToString('o'); $meta.ExitCode=$p.ExitCode; $meta.ReportSHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $reportPath).Hash
$meta | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'run-metadata.json') -Encoding UTF8
Write-Host "RUN PASS: $RunId -> $runDir"
