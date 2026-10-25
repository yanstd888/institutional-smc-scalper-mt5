param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$tool=Join-Path $ProjectRoot 'Tools\New-YANSTDGen6APlan.ps1'
if(-not(Test-Path $tool)){throw 'Gen6A plan tool missing'}
& $tool -ProjectRoot $ProjectRoot
$root=Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE'
$m=Get-Content -Raw (Join-Path $root 'candidate-manifest-gen6a-smoke.json')|ConvertFrom-Json
$annual=Get-Content -Raw (Join-Path $root 'candidate-manifest-gen6a-annual.json')|ConvertFrom-Json
$c=@(Get-Content -Raw (Join-Path $root 'candidates-gen6a.json')|ConvertFrom-Json|ForEach-Object{$_})
if($c.Count-ne 6-or @($m.Jobs).Count-ne 6){throw 'Gen6A smoke requires 3 modes x clamp/reject'}
if(@($annual.Jobs).Count-ne 120){throw 'Gen6A annual requires 6 candidates x 20 years'}
if((@($annual.Jobs|%{[int]$_.FromDate.Substring(0,4)}|Sort-Object -Unique)-join ',')-ne((2007..2026)-join ',')){throw 'Gen6A annual windows incomplete'}
if((@($c.Mode|Sort-Object -Unique)-join ',')-ne'M0_HYBRID,M1_MSNR_SOFTSMC,M2_SMC_SOFTMSNR'){throw 'All modes required'}
foreach($x in $c){$p=@(Get-Content $x.PresetPath);if(@($p|?{$_-match'^[A-Za-z_]\w*='}).Count-ne 201){throw 'preset schema != 201'};if($p-notcontains'InpFixedLot=0.10'){throw 'fixed lot missing'}}
if(@($c|?{$_.Policy-eq'CLAMP'}|?{(Get-Content $_.PresetPath)-contains'InpRejectOutOfBoundsSL=0'}).Count-ne 3){throw 'CLAMP controls invalid'}
if(@($c|?{$_.Policy-eq'REJECT'}|?{(Get-Content $_.PresetPath)-contains'InpRejectOutOfBoundsSL=1'}).Count-ne 3){throw 'REJECT candidates invalid'}
Write-Host 'TEST-GENERATION6A-PLAN: PASS'
