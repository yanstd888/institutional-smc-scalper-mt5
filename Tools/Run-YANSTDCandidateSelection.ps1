param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ManifestFileName = 'candidate-manifest.json',
    [string]$OutputDirName = 'Runs',
    [switch]$AllowHoldout,
    [switch]$AllowDynamicRisk,
    [string]$TerminalDataRoot = $(if ($env:MT5_DATA_PATH) { $env:MT5_DATA_PATH } else { Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common' })
)
$ErrorActionPreference='Stop'
$moduleRoot=Join-Path $ProjectRoot 'Backtests\YANSTD-LIVE-SELECTION-MODULE'
$manifest=Get-Content -Raw -LiteralPath (Join-Path $moduleRoot $ManifestFileName) | ConvertFrom-Json
$runner=Join-Path $ProjectRoot 'Tools\Run-YANSTDBacktestJob.ps1'
foreach($job in $manifest.Jobs) {
    $runDir=Join-Path (Join-Path $moduleRoot $OutputDirName) $job.RunId
    if(Test-Path -LiteralPath (Join-Path $runDir 'report.htm')) {
        # Verify preset hash matches before skipping — stale results from a changed manifest
        # must NOT be silently reused (root-cause fix for schema-drift resume bug)
        $existingMeta = Get-Content -LiteralPath (Join-Path $runDir 'run-metadata.json') -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        $curHash = if(Test-Path -LiteralPath $job.PresetPath) { (Get-FileHash -LiteralPath $job.PresetPath -Algorithm SHA256).Hash } else { '' }
        if($existingMeta -and $existingMeta.PresetSHA256 -eq $curHash) {
            Write-Host "SKIP COMPLETE: $($job.RunId) (preset hash verified)"
            continue
        } else {
            Write-Host "RESUME: $($job.RunId) (preset changed, rerun)"
        }
    }
    try {
        $jobDelay = if($null -ne $job.DelayMs) { [int]$job.DelayMs } else { 0 }
        & $runner -PresetPath $job.PresetPath -RunId $job.RunId -FromDate $job.FromDate -ToDate $job.ToDate -DelayMs $jobDelay -TerminalDataRoot $TerminalDataRoot -OutputRoot (Join-Path $moduleRoot $OutputDirName) -AllowHoldout:$AllowHoldout -AllowDynamicRisk:$AllowDynamicRisk
    } catch {
        throw "Candidate batch stopped at $($job.RunId): $_"
    }
    if(-not (Test-Path -LiteralPath (Join-Path $runDir 'report.htm'))) { throw "Candidate batch stopped at $($job.RunId): report.htm missing after run" }
}
Write-Host 'CANDIDATE SELECTION BATCH: PASS'
