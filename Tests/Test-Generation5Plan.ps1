param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$tool=Join-Path $ProjectRoot 'Tools\New-YANSTDGen5Plan.ps1'
if(-not(Test-Path $tool)){throw 'RED: Gen5 plan tool missing'}
& $tool -ProjectRoot $ProjectRoot
$root=Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE'
$m=Get-Content -Raw (Join-Path $root 'candidate-manifest-gen5.json')|ConvertFrom-Json
$c=@(Get-Content -Raw (Join-Path $root 'candidates-gen5.json')|ConvertFrom-Json|ForEach-Object{$_})
$jobs=@($m.Jobs|ForEach-Object{$_})
if($c.Count -ne 6 -or $jobs.Count -ne 120){throw 'Gen5 requires 3 strategies x 2 candidates x 20 annual windows'}
$modes=@($c.Mode|Sort-Object -Unique)
if(($modes-join ',') -ne 'M0_HYBRID,M1_MSNR_SOFTSMC,M2_SMC_SOFTMSNR'){throw 'Gen5 must cover all 3 strategy modes'}
foreach($x in $c){$p=Get-Content $x.PresetPath;if(@($p|?{$_-match '^[A-Za-z_]\w*='}).Count-ne 201){throw 'preset schema != 200'};foreach($v in @('InpFixedLot=0.10','InpUseDynamicRisk=0','InpUseSmartBrain=0')){if($p-notcontains$v){throw "missing $v"}}}
$control=$c|? CandidateId -eq 'G5S00_CONTROL';$mfe=$c|? CandidateId -eq 'G5S01_MFE100_LOCK025'
if((Get-Content $control.PresetPath)-notcontains'InpUseMilestoneLock=0'){throw 'control changed'}
$p=Get-Content $mfe.PresetPath;foreach($v in @('InpUseMilestoneLock=1','InpMilestoneTriggerR=1.00','InpMilestoneLockR=0.25')){if($p-notcontains$v){throw "MFE candidate missing $v"}}
$years=@($m.Jobs|%{[int]$_.FromDate.Substring(0,4)}|Sort-Object -Unique);if(($years-join',')-ne((2007..2026)-join',')){throw 'annual windows incomplete'}
Write-Host 'TEST-GENERATION5-PLAN: PASS'