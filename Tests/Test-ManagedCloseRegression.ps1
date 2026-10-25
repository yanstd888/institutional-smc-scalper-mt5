param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$ControlRunDirectory
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $RunDirectory 'tester-log-slice.log'
if(-not (Test-Path -LiteralPath $logPath)) { throw "ManagedClose regression log is missing: $logPath" }

$lines = @(Get-Content -LiteralPath $logPath)
$start = @($lines | Where-Object { $_ -match '\[ManagedClose\] Closing position \| ticket=(\d+) reason=TIME_INVALIDATION' })
if($start.Count -lt 1) { throw 'ManagedClose regression fixture did not trigger TIME_INVALIDATION' }

$h3 = @($lines | Where-Object { $_ -match 'position could NOT be closed after escalation' })
if($h3.Count -gt 0) {
    $tickets = @($h3 | ForEach-Object {
        if($_ -match 'ticket=(\d+)') { $Matches[1] }
    } | Sort-Object -Unique)
    throw "ManagedClose abandoned open position(s): $($tickets -join ',')"
}

# A successful regression run must show that each request remains managed until
# either the EA can send a market close or server-side SL/TP closes it. During a
# session break there may be no intervening tick on which the EA can retry.
$requestedTickets = @($start | ForEach-Object {
    if($_ -match 'ticket=(\d+)') { $Matches[1] }
} | Sort-Object -Unique)
$confirmed = @()
$unresolved = @()
foreach($ticket in $requestedTickets) {
    $requestIndex = -1
    for($i=0; $i -lt $lines.Count; $i++) {
        if($lines[$i] -match "\[ManagedClose\] Closing position \| ticket=$ticket reason=TIME_INVALIDATION") {
            $requestIndex = $i; break
        }
    }
    $closeAfterRequest = $false
    if($requestIndex -ge 0) {
        for($i=$requestIndex + 1; $i -lt $lines.Count; $i++) {
            if($lines[$i] -match "market (buy|sell) .* close #$ticket(\D|$)" -or
               $lines[$i] -match "(stop loss|take profit) triggered #$ticket(\D|$)") {
                $closeAfterRequest = $true; break
            }
        }
    }
    if($closeAfterRequest) { $confirmed += $ticket } else { $unresolved += $ticket }
}
if($unresolved.Count -gt 0) { throw "TIME_INVALIDATION sequence failure: close must occur after request for ticket(s): $($unresolved -join ',')" }

# The narrow closed-session fixture may have no intervening tick before server
# TP/SL. A separate same-build control must prove the ordinary path still emits
# an EA market-close deal for a TIME_INVALIDATION request.
$marketConfirmed = @()
if($ControlRunDirectory) {
    $controlLog = Join-Path $ControlRunDirectory 'tester-log-slice.log'
    if(-not (Test-Path -LiteralPath $controlLog)) { throw "ManagedClose control log is missing: $controlLog" }
    $controlLines = @(Get-Content -LiteralPath $controlLog)

    $fixtureMetadataPath = Join-Path $RunDirectory 'run-metadata.json'
    $controlMetadataPath = Join-Path $ControlRunDirectory 'run-metadata.json'
    if(-not (Test-Path -LiteralPath $fixtureMetadataPath) -or -not (Test-Path -LiteralPath $controlMetadataPath)) {
        throw 'ManagedClose same-build identity requires run-metadata.json on fixture and control'
    }
    $fixtureMetadata = Get-Content -Raw -LiteralPath $fixtureMetadataPath | ConvertFrom-Json
    $controlMetadata = Get-Content -Raw -LiteralPath $controlMetadataPath | ConvertFrom-Json
    $fixtureHash = [string]$fixtureMetadata.ExpertSHA256
    $controlHash = [string]$controlMetadata.ExpertSHA256
    if($fixtureHash -notmatch '^[A-Fa-f0-9]{64}$' -or $controlHash -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'ManagedClose same-build identity requires a valid 64-hex ExpertSHA256 on fixture and control'
    }
    if($fixtureHash -ne $controlHash) {
        throw "ManagedClose control is not the same build: ExpertSHA256 fixture=$fixtureHash control=$controlHash"
    }

    if(@($controlLines | Where-Object { $_ -match 'position could NOT be closed after escalation' }).Count -gt 0) {
        throw 'ManagedClose control run contains an abandoned position'
    }
    $controlRequests = @($controlLines | ForEach-Object {
        if($_ -match '\[ManagedClose\] Closing position \| ticket=(\d+) reason=TIME_INVALIDATION') { $Matches[1] }
    } | Sort-Object -Unique)
    $marketConfirmed = @()
    foreach($ticket in $controlRequests) {
        $requestIndex = -1
        for($i=0; $i -lt $controlLines.Count; $i++) {
            if($controlLines[$i] -match "\[ManagedClose\] Closing position \| ticket=$ticket reason=TIME_INVALIDATION") {
                $requestIndex = $i; break
            }
        }
        if($requestIndex -lt 0) { continue }
        for($i=$requestIndex + 1; $i -lt $controlLines.Count; $i++) {
            if($controlLines[$i] -match "market (buy|sell) .* close #$ticket(\D|$)") {
                $marketConfirmed += $ticket; break
            }
        }
    }
    if($marketConfirmed.Count -lt 1) { throw 'Control sequence did not prove an EA market-close deal after TIME_INVALIDATION request' }
}

Write-Host "TEST-MANAGED-CLOSE-REGRESSION: PASS ($($confirmed.Count)/$($requestedTickets.Count) protected; $($marketConfirmed.Count) EA market-close control)"
