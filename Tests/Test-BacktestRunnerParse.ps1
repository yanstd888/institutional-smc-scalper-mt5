param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'Tools\Run-YANSTDBacktestJob.ps1'
$tokens=$null; $errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0) { throw ('Runner parser errors: ' + (($errors | ForEach-Object Message) -join ' | ')) }
$text = Get-Content -Raw -LiteralPath $path
if($text -notmatch 'ExpertSHA256') { throw 'Runner metadata must record exact ExpertSHA256' }
if($text -notmatch 'Fixed-lot research contract violated' -or $text -notmatch 'FixedLot=0\.10') { throw 'Runner must enforce and record fixed lot 0.10' }
if($text -notmatch '\$logOffset\s*=\s*if\s*\(\$afterLog\s*-eq\s*\$todayLog\)') { throw 'Runner must reset log offset across midnight rollover' }
Write-Host 'TEST-BACKTEST-RUNNER-PARSE: PASS'
