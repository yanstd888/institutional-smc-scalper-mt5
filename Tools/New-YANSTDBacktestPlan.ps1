param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $ProjectRoot 'Tools\YANSTDBacktestModule.psm1'
Import-Module $modulePath -Force
if($OutputRoot -eq '') { $OutputRoot = Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE' }

$config = New-YANSTDBacktestConfig -ProjectRoot $ProjectRoot -OutputRoot $OutputRoot
$candidateDir = Join-Path $OutputRoot 'Candidates'
$candidates = New-YANSTDCandidatePresets -ProjectRoot $ProjectRoot -OutputDirectory $candidateDir
$candidateManifest = New-YANSTDCandidateManifest -Config $config -Candidates $candidates
$coreManifest = New-YANSTDRunManifest -Config $config

Save-YANSTDJson -Object $config -Path (Join-Path $OutputRoot 'config.json')
Save-YANSTDJson -Object $candidates -Path (Join-Path $OutputRoot 'candidates.json')
Save-YANSTDJson -Object $candidateManifest -Path (Join-Path $OutputRoot 'candidate-manifest.json')
Save-YANSTDJson -Object $coreManifest -Path (Join-Path $OutputRoot 'core-manifest.json')

$inventory = @($candidates | ForEach-Object {
    $audit = Test-YANSTDSetFile -Path $_.PresetPath -ExpectedInputCount 201
    [pscustomobject]@{ CandidateId=$_.CandidateId; Mode=$_.Mode; File=(Split-Path -Leaf $_.PresetPath); Inputs=$audit.InputCount; UniqueInputs=$audit.UniqueInputCount; SHA256=$_.PresetSHA256 }
})
Save-YANSTDJson -Object $inventory -Path (Join-Path $OutputRoot 'candidate-inventory.json')

Write-Host "PLAN READY: $OutputRoot"
Write-Host "Candidate jobs: $($candidateManifest.Jobs.Count) | Core jobs: $($coreManifest.Jobs.Count)"
Write-Host 'NO Strategy Tester run was launched.'
