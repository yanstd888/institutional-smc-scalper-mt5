param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$p=Join-Path $ProjectRoot 'Modules\OrderManager.mqh'
$s=Get-Content -Raw -LiteralPath $p
$start=$s.IndexOf('bool COrderManager::ApplyServerTP')
$end=$s.IndexOf('bool COrderManager::UpdateTrackTarget', $start)
if($start -lt 0 -or $end -lt 0){ throw 'ApplyServerTP not found' }
$body=$s.Substring($start,$end-$start)
if($body -notmatch 'POSITION_TP'){ throw 'RED: ApplyServerTP does not inspect the existing server TP' }
if($body -notmatch 'MathAbs\(.*tp.*existingTP|MathAbs\(.*existingTP.*tp'){ throw 'RED: same-TP no-op guard absent' }
if($body -notmatch 'targetValid' -or $body -notmatch 'stopStillValid'){ throw 'RED: TP modify does not validate both requested TP and preserved SL' }
Write-Output 'TEST-APPLY-SERVER-TP-SAFETY: PASS'
