# Existing plain-text logs only; never supplied scripts/binaries or GPU access.
[CmdletBinding()]
param([string]$Logs,[string]$Python='python',[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
if(!$Logs){$Logs=Read-Host 'Existing folder containing RUN0002-fail.TXT, RUN0004-ok.TXT, RUN0005-ok.TXT'}
$command=Resolve-GuPythonApplication $Python
$root=(Get-Item -LiteralPath $Logs).FullName
$out=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Command-Review' $root
$json=& $command -I -B (Join-Path $PSScriptRoot 'review-command-log.py') $root
if($LASTEXITCODE -ne 0){throw 'Log review stopped. Preserve source/logs; no new boot or settings change.'}
$report=$json|ConvertFrom-Json
if($report.test -cne 'existing-command-boundaries-v1' -or $report.write_eligible -ne $false){throw 'Unexpected report.'}
$path=Join-Path $out 'command-review.json'
[IO.File]::WriteAllText($path,($json -join [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Host ('Return only reviewed '+$path+'. No raw log, rebuild or hardware repeat required.')
