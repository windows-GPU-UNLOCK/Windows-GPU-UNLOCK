# GPL-2.0-only. Capture-free EDID/no-EDID release matrix; no GPU/firmware access.
param([string]$Clang='clang',[string]$Python='python',[string]$VcVars,
 [string]$Card,[Nullable[int]]$Children,[switch]$Mutations)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'host.ps1')
Import-GuHostCompiler $VcVars
$output=Join-Path $PSScriptRoot ('build/local-release-'+[Guid]::NewGuid().ToString('N'))
$selection=@()
if($Card){$selection+=@('--card',$Card)}
if($null -ne $Children){$selection+=@('--children',[string]$Children)}
if($Mutations){$selection+='--mutations'}
& $Python -I (Join-Path $PSScriptRoot 'test_local_release.py') --clang $Clang --output $output @selection
if($LASTEXITCODE -ne 0){throw 'Synthetic local release matrix failed'}
Write-Host ('Return only reviewed '+(Join-Path $output 'summary.json')+'. RAM fixtures only; no firmware, capture or hardware repeat.')
