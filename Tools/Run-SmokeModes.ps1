param(
    [string]$Symbol = 'XAUUSD.FXSPREAD',
    [string]$FromDate = '2022.10.03',
    [string]$ToDate = '2022.10.07',
    [long]$Login = $(if ($env:MT5_LOGIN) { [long]$env:MT5_LOGIN } else { 0 }),
    [string]$Server = $(if ($env:MT5_SERVER) { $env:MT5_SERVER } else { '' })
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$terminal = if ($env:MT5_TERMINAL_PATH) { $env:MT5_TERMINAL_PATH } else { 'C:\Program Files\MetaTrader 5\terminal64.exe' }
$data = if ($env:MT5_DATA_PATH) { $env:MT5_DATA_PATH } else { Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common' }
$profiles=Join-Path $data 'MQL5\Profiles\Tester'
$configDir=Join-Path $data 'config'
$reportDir=Join-Path $root 'Backtests\Smoke'
New-Item -ItemType Directory -Force -Path $profiles,$configDir,$reportDir | Out-Null
$modes=@(
 @{Name='HYBRID';Preset='YANSTD_RT_01_SMOKE_2022Q4.set';Source='SET - GROK 4.6';Mode='0'},
 @{Name='MSNR_PRIMARY';Preset='YANSTD_MSNR_SOFTSMC_BACKTEST.set';Source='SET - CLAUDE SONNET 5 HIGH';Mode='1'},
 @{Name='SMC_PRIMARY';Preset='YANSTD_SMC_SOFTMSNR_BACKTEST.set';Source='SET - CLAUDE SONNET 5 HIGH';Mode='2'}
)
foreach($m in $modes) {
 $presetSource=Join-Path $root "Presets\$($m.Source)\$($m.Preset)"
 $modeLine = Get-Content -LiteralPath $presetSource | Where-Object { $_ -match '^InpSetupMode=' } | Select-Object -First 1
 if($modeLine -ne "InpSetupMode=$($m.Mode)") { throw "$($m.Name): preset setup mode mismatch (found '$modeLine')" }
 Copy-Item -LiteralPath $presetSource -Destination (Join-Path $profiles $m.Preset) -Force
 $reportBase="YANSTD_SMOKE_$($m.Name)"
 $finalReport=Join-Path $reportDir ("YANSTD_SMOKE_"+$m.Name+".log")
 Remove-Item $finalReport -Force -ErrorAction SilentlyContinue
 $testerLog=Join-Path $data ("Tester\logs\"+(Get-Date -Format 'yyyyMMdd')+".log")
 $beforeLines=if(Test-Path -LiteralPath $testerLog){@(Get-Content -LiteralPath $testerLog).Count}else{0}
 $ini=Join-Path $configDir ("YANSTD_SMOKE_"+$m.Name+".ini")
 @"
[Common]
Login=$Login
Server=$Server
ProxyEnable=0
NewsEnable=0

[Tester]
Expert=YANSTD_AUDIT\YANSTD.ex5
ExpertParameters=$($m.Preset)
Symbol=$Symbol
Period=M3
Deposit=10000
Currency=USD
Leverage=2000
Model=4
ExecutionMode=0
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
"@ | Set-Content -LiteralPath $ini -Encoding ASCII
 $p=Start-Process -FilePath $terminal -ArgumentList "/config:$ini" -PassThru -Wait
 $allLines=@(Get-Content -LiteralPath $testerLog)
 $runLines=@($allLines | Select-Object -Skip $beforeLines)
 $runText=$runLines -join "`n"
 if($runText -notmatch "InpSetupMode=$($m.Mode)") { throw "$($m.Name): tester log did not use expected mode" }
 if($runText -notmatch 'Test passed in') { throw "$($m.Name): tester did not finish successfully" }
 if($runText -notmatch 'version=4\.47\.16-HYBRID') { throw "$($m.Name): wrong EA version in tester log" }
 $runLines | Set-Content -LiteralPath $finalReport -Encoding UTF8
 Write-Host "[SMOKE PASS] $($m.Name) mode=$($m.Mode) report=$finalReport"
}
Write-Host 'THREE-MODE SMOKE: PASS'
