# Existing sanitized reports only. No capture, compiler, hardware or profile generation.
[CmdletBinding()]
param([string]$ResourceReport,[string]$DriverReport,[string]$Python='python',[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
if(!$ResourceReport){$ResourceReport=Read-Host 'Existing resource capture report.json path'}
if(!$DriverReport){$DriverReport=Read-Host 'Existing driver-review.json or combined resource-files.json path'}
$command=Resolve-GuPythonApplication $Python
$lines=& $command -I -B (Join-Path $PSScriptRoot 'review-driver-envelope.py') $ResourceReport $DriverReport
if($LASTEXITCODE -ne 0){throw 'Report comparison stopped. Preserve files; no hardware retry.'}
$r=($lines -join [Environment]::NewLine)|ConvertFrom-Json
if($r.test -cne 'reported-driver-envelope-v1' -or $r.write_eligible -or $r.profile_generated){throw 'Unexpected scope.'}
$root=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Driver-Envelope' (Split-Path -Parent ([IO.Path]::GetFullPath($ResourceReport)))
$path=Join-Path $root 'driver-envelope.json';$r|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('Return only reviewed '+$path+' if requested. No new capture, settings change or boot.')
