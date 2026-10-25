param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -LiteralPath $Path), [ref]$errors)
if($errors.Count -ne 0) {
    foreach($e in $errors) { Write-Host ("PARSE ERROR: " + $e.Message) }
    throw "parse failed: $Path"
}
Write-Host "PARSE OK: $Path"
