param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$tool=Join-Path $ProjectRoot 'Tools\New-YANSTDGen6BPlan.ps1'
if(-not(Test-Path $tool)){throw 'Gen6B plan tool missing'}
& $tool -ProjectRoot $ProjectRoot
$root=Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE'
$m=Get-Content -Raw (Join-Path $root 'candidate-manifest-gen6b-smoke.json')|ConvertFrom-Json
$a=Get-Content -Raw (Join-Path $root 'candidate-manifest-gen6b-annual.json')|ConvertFrom-Json
$c=@(Get-Content -Raw (Join-Path $root 'candidates-gen6b.json')|ConvertFrom-Json|%{$_})
if($c.Count-ne 3-or @($m.Jobs).Count-ne 3-or @($a.Jobs).Count-ne 60){throw 'Gen6B requires 3 modes, 3 smoke, 60 annual jobs'}
if((@($c.Mode|Sort-Object -Unique)-join ',')-ne'M0_HYBRID,M1_MSNR_SOFTSMC,M2_SMC_SOFTMSNR'){throw 'All modes required'}
foreach($x in $c){$p=@(Get-Content $x.PresetPath);if(@($p|?{$_-match'^[A-Za-z_]\w*='}).Count-ne 201){throw 'preset schema != 201'};if($p-notcontains'InpFixedLot=0.10'){throw 'fixed lot missing'}}
$m0=$c|Where-Object{$_.Mode -eq 'M0_HYBRID'}
$m1=$c|Where-Object{$_.Mode -eq 'M1_MSNR_SOFTSMC'}
$m2=$c|Where-Object{$_.Mode -eq 'M2_SMC_SOFTMSNR'}
if((Get-Content $m0.PresetPath)-notcontains'InpRejectOutOfBoundsSL=1'){throw 'M0 must REJECT'}
if((Get-Content $m1.PresetPath)-notcontains'InpRejectOutOfBoundsSL=1'){throw 'M1 must REJECT'}
if((Get-Content $m1.PresetPath)-notcontains'InpRequireZoneOTE=0'){throw 'M1 OTE must be soft'}
if((Get-Content $m2.PresetPath)-notcontains'InpRejectOutOfBoundsSL=0'){throw 'M2 must CLAMP'}
$worker=Get-Content -Raw (Join-Path $ProjectRoot 'Tools\Run-YANSTDGen6BBatchWorker.ps1')
foreach($gate in @('extract_backtest_attribution.py','check_gen4_fixed_lot.py','apply_cost_stress.py','score_backtest_candidates.py','PostprocessCompleted'))
  {if($worker -notmatch [regex]::Escape($gate)){throw "Gen6B worker missing postprocess gate: $gate"}}
Write-Host 'TEST-GENERATION6B-PLAN: PASS'
