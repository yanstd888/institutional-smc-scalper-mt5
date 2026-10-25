param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'Tools\Start-YANSTDGen4Batch.ps1'
if(-not(Test-Path -LiteralPath $path)){throw 'Detached Gen4 batch launcher is missing'}
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ('Launcher parser errors: '+(($errors|ForEach-Object Message)-join ' | '))}
$text=Get-Content -Raw -LiteralPath $path
foreach($required in @('schtasks.exe','/Create','/Run','YANSTDGen4Worker.cmd','candidate-manifest-gen4.json','Runs_Gen4','GEN4_BATCH_STATUS.json')){
 if($text -notmatch [regex]::Escape($required)){throw "Detached launcher missing: $required"}
}
Write-Host 'TEST-DETACHED-CANDIDATE-BATCH: PASS'
