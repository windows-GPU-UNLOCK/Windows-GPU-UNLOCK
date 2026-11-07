# Existing inventory file only. No Windows/GPU/firmware queries or profile selection.
[CmdletBinding()]
param([string]$Inventory,[string]$Python='python',[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
if(!$Inventory){$Inventory=Read-Host 'Existing collector inventory.json path (do not recollect)'}
$command=Resolve-GuPythonApplication $Python
$lines=& $command -I -B (Join-Path $PSScriptRoot 'review-inventory-source-scope.py') $Inventory
if($LASTEXITCODE -ne 0){throw 'Existing inventory comparison stopped. No settings changes or EFI run.'}
$r=($lines -join [Environment]::NewLine)|ConvertFrom-Json
if($r.test -cne 'inventory-source-scope-v1' -or $r.write_eligible -or $r.efi_run_authorized){throw 'Unexpected scope.'}
$out=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Source-Scope' (Split-Path -Parent ([IO.Path]::GetFullPath($Inventory)))
$path=Join-Path $out 'source-scope.json';$r|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('Return only reviewed '+$path+' if requested. No new inventory or hardware run needed.')
