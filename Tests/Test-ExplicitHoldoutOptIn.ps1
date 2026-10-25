param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$runner=Get-Content -Raw (Join-Path $ProjectRoot 'Tools\Run-YANSTDBacktestJob.ps1')
$batch=Get-Content -Raw (Join-Path $ProjectRoot 'Tools\Run-YANSTDCandidateSelection.ps1')
$worker=Get-Content -Raw (Join-Path $ProjectRoot 'Tools\Run-YANSTDGen5BatchWorker.ps1')
if($runner-notmatch '\[switch\]\$AllowHoldout' -or $runner-notmatch 'if\s*\(-not \$AllowHoldout') {throw 'RED: runner lacks explicit holdout opt-in'}
if($batch-notmatch '\[switch\]\$AllowHoldout' -or $batch-notmatch '-AllowHoldout:\$AllowHoldout') {throw 'RED: batch does not forward holdout opt-in'}
if($worker-notmatch '-AllowHoldout') {throw 'RED: Gen5 worker does not opt in'}
Write-Host 'TEST-EXPLICIT-HOLDOUT-OPT-IN: PASS'
