$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root 'Tools\Run-YANSTDGen5BatchWorker.ps1'
$launcher=Join-Path $root 'Tools\Start-YANSTDGen5Batch.ps1'
if(-not(Test-Path $worker)){throw 'RED: Gen5 worker missing'}
if(-not(Test-Path $launcher)){throw 'RED: Gen5 launcher missing'}
$wText=Get-Content -Raw $worker
$lText=Get-Content -Raw $launcher
foreach($token in @('candidate-manifest-gen5.json','Runs_Gen5_Annual','Attribution_Gen5_Annual','GEN5_BATCH_STATUS.json','GEN5_BATCH_TASK.log','--allow-holdout','YANSTD_Gen5_Backtest')){
  if(-not $wText.Contains($token)){throw "Gen5 worker missing $token"}
}
foreach($token in @('YANSTD_Gen5_Backtest','candidate-manifest-gen5.json','Runs_Gen5_Annual','Attribution_Gen5_Annual','GEN5_BATCH_STATUS.json')){
  if(-not $lText.Contains($token)){throw "Gen5 launcher missing $token"}
}
Write-Host 'TEST-GEN5-AUTOMATED-PIPELINE: PASS'
