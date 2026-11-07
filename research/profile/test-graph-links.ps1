# Read an existing sanitized graph summary only; no firmware or GPU access.
[CmdletBinding()]
param([string]$Summary,[string]$Python='python',[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
if(!$Summary){$Summary=Read-Host 'Existing graph-summary.json path'}
$command=Resolve-GuPythonApplication $Python
$lines=& $command -I -B (Join-Path $PSScriptRoot 'review-graph-links.py') $Summary
if($LASTEXITCODE -ne 0){throw 'Graph relationship review stopped. Preserve files; no new boot or settings changes.'}
$r=($lines -join [Environment]::NewLine)|ConvertFrom-Json
if($r.test -cne 'graph-links-v1' -or $r.write_eligible -or $r.release_verified){throw 'Unexpected scope.'}
$root=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Graph-Links' (Split-Path -Parent ([IO.Path]::GetFullPath($Summary)))
$path=Join-Path $root 'graph-links.json'
$r|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('Return only reviewed '+$path+'. Keep original files unchanged; no new EFI run.')
