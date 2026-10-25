param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$terminal = if ($env:MT5_TERMINAL_PATH) { $env:MT5_TERMINAL_PATH } else { 'C:\Program Files\MetaTrader 5\terminal64.exe' }
$data = if ($env:MT5_DATA_PATH) { $env:MT5_DATA_PATH } else { Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common' }
$common=Join-Path $data '..\Common\Files'
$profiles=Join-Path $data 'MQL5\Profiles\Tester'
$configDir=Join-Path $data 'config'
New-Item -ItemType Directory -Force -Path $profiles,$configDir | Out-Null

# Delete prior marker so a leftover PASS cannot fake success.
$marker=Join-Path $common 'YANSTD_RunUnitTests.result'
Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

$ini=Join-Path $profiles 'YANSTD_UNITTEST.ini'
@"
[Tester]
Expert=YANSTD_AUDIT\Tests\RunUnitTests.ex5
Symbol=XAUUSD.FXSPREAD
Period=M3
Deposit=10000
Currency=USD
Leverage=2000
Model=4
ExecutionMode=0
Optimization=0
FromDate=2022.10.03
ToDate=2022.10.07
ForwardMode=0
Report=YANSTD_UNITTEST
ReplaceReport=1
ShutdownTerminal=1
Visual=0
UseLocal=1
UseRemote=0
UseCloud=0
"@ | Set-Content -LiteralPath $ini -Encoding ASCII

$testerLog=Join-Path $data ("Tester\logs\"+(Get-Date -Format 'yyyyMMdd')+".log")
$beforeLines=if(Test-Path -LiteralPath $testerLog){@(Get-Content -LiteralPath $testerLog).Count}else{0}

& $terminal ("/config:"+$ini) | Out-Null

for($i=0;$i -lt 300 -and -not (Test-Path -LiteralPath $marker);$i++){ Start-Sleep -Seconds 1 }
if(-not (Test-Path -LiteralPath $marker)){ throw "unit-test marker not written" }
$txt=Get-Content -LiteralPath $marker -Raw
Write-Host $txt
if($txt -notmatch 'PASS'){ throw "unit tests FAILED" }
Write-Host "UNIT-TEST: PASS"
