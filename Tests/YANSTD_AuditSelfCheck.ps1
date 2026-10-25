$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$metaEditor = 'C:\Program Files\MetaTrader 5\MetaEditor64.exe'
$failures = [System.Collections.Generic.List[string]]::new()

function Fail([string]$message) { $script:failures.Add($message); Write-Host "[FAIL] $message" -ForegroundColor Red }
function Pass([string]$message) { Write-Host "[PASS] $message" -ForegroundColor Green }
function Assert-Text([string]$name,[string]$text,[string]$pattern) {
    if ($text -notmatch $pattern) { Fail "$name (pattern missing: $pattern)" } else { Pass $name }
}

if (-not (Test-Path -LiteralPath $metaEditor)) { throw "MetaEditor not found: $metaEditor" }

# Compile exact staged copies from the terminal data tree. MetaEditor command-line
# mode is unreliable when /compile or /log itself contains spaces, so the audit
# uses an isolated no-space folder while preserving the project's relative layout.
$terminalRoot = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'MetaQuotes\Terminal') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'MQL5\Include\Trade\Trade.mqh') } |
    Select-Object -First 1
if (-not $terminalRoot) { throw 'MT5 terminal data root not found' }
$stage = Join-Path $terminalRoot.FullName 'MQL5\Experts\YANSTD_AUDIT'
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'Modules'),(Join-Path $stage 'GUI'),(Join-Path $stage 'Tests') | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'YANSTD.mq5') -Destination (Join-Path $stage 'YANSTD.mq5') -Force
Copy-Item -Path (Join-Path $root 'Modules\*.mqh') -Destination (Join-Path $stage 'Modules') -Force
Copy-Item -Path (Join-Path $root 'GUI\*.mqh') -Destination (Join-Path $stage 'GUI') -Force
Copy-Item -LiteralPath (Join-Path $root 'Tests\RunUnitTests.mq5'),(Join-Path $root 'Tests\Test_SetupGradeLotMultiplier.mq5') -Destination (Join-Path $stage 'Tests') -Force
$compileTargets = @(
    @{ Name='EA'; Path=(Join-Path $stage 'YANSTD.mq5'); Log=(Join-Path $stage 'compile_EA.log'); Save=(Join-Path $root 'compile_current.log') },
    @{ Name='RunUnitTests'; Path=(Join-Path $stage 'Tests\RunUnitTests.mq5'); Log=(Join-Path $stage 'compile_RunUnitTests.log'); Save=(Join-Path $root 'Tests\compile_RunUnitTests.log') },
    @{ Name='GradeTest'; Path=(Join-Path $stage 'Tests\Test_SetupGradeLotMultiplier.mq5'); Log=(Join-Path $stage 'compile_GradeTest.log'); Save=(Join-Path $root 'Tests\compile_GradeTest.log') }
)
foreach ($target in $compileTargets) {
    Remove-Item -LiteralPath $target.Log -Force -ErrorAction SilentlyContinue
    $args = @("/compile:$($target.Path)", "/log:$($target.Log)")
    $p = Start-Process -FilePath $metaEditor -ArgumentList $args -PassThru -Wait
    for ($i=0; $i -lt 100 -and -not (Test-Path -LiteralPath $target.Log); $i++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $target.Log)) { Fail "$($target.Name) compile log missing"; continue }
    Copy-Item -LiteralPath $target.Log -Destination $target.Save -Force
    $log = Get-Content -LiteralPath $target.Log -Raw
    if ($log -match 'Result:\s+0 errors,\s+0 warnings') { Pass "$($target.Name) compile: 0 errors, 0 warnings" }
    else { Fail "$($target.Name) compile failed; inspect $($target.Save)" }
}

$eaPath = Join-Path $root 'YANSTD.mq5'
$ea = Get-Content -LiteralPath $eaPath -Raw
$defines = Get-Content -LiteralPath (Join-Path $root 'Modules\Defines.mqh') -Raw
$fvg = Get-Content -LiteralPath (Join-Path $root 'Modules\FVGValidator.mqh') -Raw
$m15 = Get-Content -LiteralPath (Join-Path $root 'Modules\SMCLayerM15.mqh') -Raw
$signal = Get-Content -LiteralPath (Join-Path $root 'Modules\SignalEngine.mqh') -Raw
$risk = Get-Content -LiteralPath (Join-Path $root 'Modules\RiskCalculator.mqh') -Raw
$session = Get-Content -LiteralPath (Join-Path $root 'Modules\SessionManager.mqh') -Raw

# Behavioral-contract regression guards for fixes 1-8. The MQL harness exercises
# pure helpers; these guards ensure orchestration paths still call those helpers.
Assert-Text 'H2 grade max derives from table' $defines 'double\s+MaxSetupGradeLotMultiplier\s*\('
Assert-Text 'H2 startup reports effective max risk' $ea 'MaxSetupGradeLotMultiplier\s*\(\)'
Assert-Text 'H3 M5+ rejects disqualified FVG' $signal 'disqualified FVG[\s\S]{0,500}IsFVGValidWithStructureFromRates'
Assert-Text 'H3 OB_ONLY restricted to M3 by contract' $defines 'POI_PROFILE_OB_ONLY may only be reached from the M3'
Assert-Text 'M1 validator stops eligibility at CE' $fvg 'fillRatio\s*>=\s*0\.50'
Assert-Text 'M1 M15 bull stops eligibility at CE' $m15 'fillRatio\s*<\s*0\.50[\s\S]{0,300}SMCM15_FVG_BULL'
Assert-Text 'M1 M15 bear stops eligibility at CE' $m15 'fillRatio\s*<\s*0\.50[\s\S]{0,300}SMCM15_FVG_BEAR'
Assert-Text 'H1 formation ATR helper exists' $defines 'double\s+ReadATRAtShift\s*\('
Assert-Text 'H4 exit recovery dispatches structural' $ea 'InpExitMode\s*==\s*EXIT_STRUCTURAL_POI'
Assert-Text 'H4 exit recovery dispatches fixed RR' $ea 'InpExitMode\s*==\s*EXIT_FIXED_RR'
Assert-Text 'H4 exit recovery dispatches staged' $ea 'RecoverStagedTargets\s*\(\s*\)'
Assert-Text 'M2 single parser exists' $ea 'void\s+ParseEntryComment\s*\('
if (([regex]::Matches($ea,'StringFind\s*\([^\r\n]*"_T"')).Count -gt 0) { Fail 'M2 legacy _T parser returned' } else { Pass 'M2 no legacy _T parser' }
Assert-Text 'M6 proximity is execution input' $ea 'InpMaxEntryDistanceATR'
Assert-Text 'M4 incremental deal hot path exists' $ea 'void\s+OnStatsDealArrived\s*\('
Assert-Text 'M5 historical timestamp controls DST offset' $session 'IsEuropeanDST\(serverTime\)'
Assert-Text 'Minimum-lot reject is wired into calculator' $ea 'SetRejectBelowMinLot\(InpRejectBelowMinLot\)'
Assert-Text 'Minimum-lot reject returns zero' $risk 'm_rejectBelowMinLot[\s\S]{0,500}return\s+0\.0\s*;'

# Presets: exact 1:1 key mapping, primitive types, enums, runtime ranges and key
# cross-fields. Parse declarations rather than maintaining a second 199-name list.
$declMatches = [regex]::Matches($ea,'(?m)^\s*input\s+(?!group\b)(?<type>[A-Za-z_][A-Za-z0-9_]*)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=')
$inputs = [ordered]@{}
foreach ($m in $declMatches) {
    $name = $m.Groups['name'].Value
    if ($inputs.Contains($name)) { Fail "duplicate input declaration: $name" }
    $inputs[$name] = $m.Groups['type'].Value
}
if ($inputs.Count -eq 201) { Pass 'EA input declarations: 201/201 unique' } else { Fail "EA input declarations: expected 201, got $($inputs.Count)" }

$customEnumRanges = @{
    InpSetupMode=@(0,2); InpTesterExecutionMode=@(0,2); InpTesterBrainSource=@(0,1)
    InpLogLevel=@(0,3); InpNewsLivePositionAction=@(0,2); InpTimeFilterMode=@(0,1); InpExitMode=@(0,2)
}
$timeframeValues = @(0,1,2,3,4,5,6,10,12,15,20,30,16385,16386,16388,16392,16396,16408,32769,32770,32771,32772,32774,32780,32792,49153,49154,49155,49156,49158,49164,49176)
$allowedVariants = @('OB_15','OB_45','FVG_50','FIB_618','FIB_705','FIB_790')
$presetFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'Presets') -Filter '*.set' -File -Recurse)
foreach ($file in $presetFiles) {
    $values = [ordered]@{}; $duplicates = @()
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        if ($line -match '^\s*[;#]' -or $line -notmatch '=') { continue }
        $parts = $line -split '=',2; $key=$parts[0].Trim(); $value=($parts[1] -split '\|\|',2)[0].Trim()
        if ($values.Contains($key)) { $duplicates += $key } else { $values[$key]=$value }
    }
    $missing = @($inputs.Keys | Where-Object { -not $values.Contains($_) })
    $extra = @($values.Keys | Where-Object { -not $inputs.Contains($_) })
    if ($values.Count -ne 201 -or $missing.Count -or $extra.Count -or $duplicates.Count) {
        Fail "$($file.Name): keys=$($values.Count), missing=$($missing.Count), extra=$($extra.Count), duplicate=$($duplicates.Count)"; continue
    }
    $bad=$false
    foreach ($key in $customEnumRanges.Keys) {
        $v=[int]$values[$key]; $r=$customEnumRanges[$key]; if ($v -lt $r[0] -or $v -gt $r[1]) { Fail "$($file.Name): $key enum out of range ($v)"; $bad=$true }
    }
    foreach ($key in $inputs.Keys) {
        $type=$inputs[$key]; $value=$values[$key]
        if ($type -eq 'bool' -and $value -notin @('true','false','0','1')) { Fail "$($file.Name): $key invalid bool '$value'"; $bad=$true }
        if ($type -eq 'ENUM_TIMEFRAMES' -and [int]$value -notin $timeframeValues) { Fail "$($file.Name): $key invalid timeframe '$value'"; $bad=$true }
    }
    $variants=@(($values.InpEntryVariants -split ',') | ForEach-Object {$_.Trim()} | Where-Object {$_})
    if (-not $variants.Count -or (@($variants | Where-Object {$_ -notin $allowedVariants -and $_ -ne 'ALL'}).Count)) { Fail "$($file.Name): invalid InpEntryVariants"; $bad=$true }
    if ([double]$values.InpMSNROTEFibMin -ge [double]$values.InpMSNROTEFibMax) { Fail "$($file.Name): MSNR OTE min/max invalid"; $bad=$true }
    if ([double]$values.InpSLMinATRMult -ge [double]$values.InpSLMaxATRMult) { Fail "$($file.Name): ATR SL min/max invalid"; $bad=$true }
    foreach ($prefix in @('inp_m15','inp_m5','inp_m3')) {
        if ([int]$values["${prefix}_back"] -ge [int]$values["${prefix}_depth"]) { Fail "$($file.Name): $prefix backstep/depth invalid"; $bad=$true }
    }
    if ([double]$values.InpRiskPercent -le 0 -or [double]$values.InpMaxAggregateRiskPct -lt 0 -or [double]$values.InpMaxAggregateRiskPct -gt 10) { Fail "$($file.Name): risk range invalid"; $bad=$true }
    if (-not $bad) { Pass "$($file.Name): 201/201 + enum/range/cross-field" }
}
if ($presetFiles.Count -eq 63) { Pass 'Preset inventory: 63 files (27 Grok + 6 Claude + 30 Recommended/Protocol)' } else { Fail "Preset inventory: expected 63, got $($presetFiles.Count)" }

if ($failures.Count) {
    Write-Host "AUDIT SELF-CHECK: FAIL ($($failures.Count) issue(s))" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host 'AUDIT SELF-CHECK: PASS' -ForegroundColor Green
exit 0
