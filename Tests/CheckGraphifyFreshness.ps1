$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$verificationPath = Join-Path $root 'graphify-out\verification.json'
if (-not (Test-Path -LiteralPath $verificationPath)) {
    throw 'GRAPHIFY STALE: graphify-out/verification.json is missing'
}

$verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
if (-not $verification.files) {
    throw 'GRAPHIFY STALE: verification.json has no source hash inventory'
}

$changed = New-Object System.Collections.Generic.List[string]
foreach ($entry in $verification.files) {
    $rel = [string]$entry.path
    $expected = [string]$entry.sha256
    $full = Join-Path $root ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full)) {
        $changed.Add("$rel missing")
        continue
    }
    $sha = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.IO.File]::ReadAllBytes($full)
        )
    ).Replace('-', '').ToLowerInvariant()
    if ($sha -ne $expected.ToLowerInvariant()) {
        $changed.Add($rel)
    }
}

$currentMq = @(Get-ChildItem -LiteralPath $root -Recurse |
    Where-Object { -not $_.PSIsContainer -and ($_.Extension -eq '.mq5' -or $_.Extension -eq '.mqh') -and ($_.FullName -notmatch '\\graphify-out\\') } |
    ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
$known = @($verification.files | ForEach-Object { [string]$_.path })
foreach ($path in $currentMq) {
    if ($path -notin $known) { $changed.Add("$path added") }
}

if ($changed.Count) {
    Write-Output ("GRAPHIFY STALE: " + ($changed -join ', ') + " changed")
    exit 1
}

$reportPath = Join-Path $root 'graphify-out\GRAPH_REPORT.md'
if (-not (Test-Path -LiteralPath $reportPath)) {
    Write-Output 'GRAPHIFY STALE: graphify-out/GRAPH_REPORT.md is missing'
    exit 1
}
$report = Get-Content -LiteralPath $reportPath -Raw
$fingerprint = [string]$verification.source_fingerprint
if (-not $fingerprint -or $report -notmatch [regex]::Escape("graphify-source-fingerprint: $fingerprint")) {
    Write-Output 'GRAPHIFY STALE: GRAPH_REPORT.md has not been reviewed for the current source fingerprint'
    exit 1
}

Write-Output 'GRAPHIFY CURRENT'
exit 0
