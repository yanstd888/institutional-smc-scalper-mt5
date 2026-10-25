param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
function Assert-True([bool]$c,[string]$m){if(-not $c){throw "ASSERT FAILED: $m"}}
$module=Join-Path $ProjectRoot 'Tools\YANSTDBacktestModule.psm1'
$temp=Join-Path $env:TEMP ('yanstd-gen3-' + [guid]::NewGuid().ToString('N'))
try {
 Import-Module $module -Force
 $candidates=New-YANSTDGeneration3CandidatePresets -ProjectRoot $ProjectRoot -OutputDirectory (Join-Path $temp 'Candidates')
 Assert-True ($candidates.Count -eq 6) 'Gen3 must contain 3 Hybrid + 3 SMC candidates'
 Assert-True (@($candidates|Where-Object Mode -like 'M1_*').Count -eq 0) 'MSNR must be outside main Gen3 universe'
 foreach($c in $candidates){
  $audit=Test-YANSTDSetFile -Path $c.PresetPath -ExpectedInputCount 201
     Assert-True $audit.IsValid "Gen3 preset must retain 201 unique inputs: $($c.PresetPath)"
  $lines=@(Get-Content -LiteralPath $c.PresetPath)
  Assert-True ($lines -contains 'InpFixedLot=0.10') 'fixed lot must be 0.10'
  Assert-True ($lines -contains 'InpUseDynamicRisk=0') 'dynamic risk must be off'
  Assert-True ($lines -contains 'InpUseSmartBrain=0') 'Brain must be off'
  Assert-True ($lines -contains 'InpMaxDailyLossPct=0.0' -and $lines -contains 'InpMaxEquityDDPct=0.0') 'research breakers must be off'
 }
 $config=New-YANSTDBacktestConfig -ProjectRoot $ProjectRoot -OutputRoot $temp
 $manifest=New-YANSTDGeneration3WalkForwardManifest -Config $config -Candidates $candidates
 Assert-True ($manifest.Jobs.Count -eq 36) '6 candidates x 3 folds x FIT/VALIDATE = 36 jobs'
 Assert-True (@($manifest.Jobs|Where-Object {[datetime]::ParseExact($_.ToDate,'yyyy.MM.dd',$null) -gt [datetime]'2023-01-01'}).Count -eq 0) 'Gen3 must never cross 2023.01.01'
 Assert-True (@($manifest.Jobs|Where-Object Stage -like '*VALIDATE').Count -eq 18) 'must have 18 inner-validation jobs'
 Write-Host 'TEST-GENERATION3-WALKFORWARD: PASS'
}
finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
