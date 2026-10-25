param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$tool=Join-Path $ProjectRoot 'Tools\New-YANSTDGen4Plan.ps1'
if(-not (Test-Path -LiteralPath $tool)){throw 'Gen4 plan tool missing'}
& $tool -ProjectRoot $ProjectRoot -TestMode
if(-not $?) {throw 'Gen4 plan tool failed'}
$root=Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE'
$manifestPath=Join-Path $root 'candidate-manifest-gen4.json'
$candidatesPath=Join-Path $root 'candidates-gen4.json'
foreach($path in @($manifestPath,$candidatesPath)){if(-not (Test-Path -LiteralPath $path)){throw "Missing output: $path"}}
$manifest=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$candidatePayload=Get-Content -Raw -LiteralPath $candidatesPath | ConvertFrom-Json
$candidates=@($candidatePayload | ForEach-Object { $_ })
if($candidates.Count -ne 4){throw "Expected 4 candidates, got $($candidates.Count)"}
if(@($manifest.Jobs).Count -ne 24){throw "Expected 24 jobs, got $(@($manifest.Jobs).Count)"}
foreach($candidate in $candidates){
  $lines=Get-Content -LiteralPath $candidate.PresetPath
  foreach($required in @('InpFixedLot=0.10','InpUseDynamicRisk=0','InpUseSmartBrain=0','InpMaxDailyLossPct=0.0','InpMaxEquityDDPct=0.0','InpRequireKillzone=0')){
    if($lines -notcontains $required){throw "$($candidate.CandidateId): missing $required"}
  }
  $keyCount=@($lines|Where-Object {$_ -match '^([A-Za-z_][A-Za-z0-9_]*)='}).Count
  if($keyCount -ne 201){throw "$($candidate.CandidateId): expected 201 inputs, got $keyCount"}
}
if(@($manifest.Jobs | Where-Object {$_.ToDate -gt '2023.01.01'}).Count){throw 'Holdout/protocol breach in Gen4 manifest'}
Write-Host 'TEST-GENERATION4-PLAN: PASS'