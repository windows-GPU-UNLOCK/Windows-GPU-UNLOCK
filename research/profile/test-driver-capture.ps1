# Existing-file observations only. No profile generation, GPU access, staging or boot.
[CmdletBinding()]
param([string]$CaptureFolder,[string]$Python='python',[string]$OutputRoot)
$ErrorActionPreference='Stop'
if(!$CaptureFolder){$CaptureFolder=Read-Host 'Existing folder containing DIAGnn.TXT and IMGnn.BIN'}
. (Join-Path $PSScriptRoot 'collection-host.ps1')
$pythonCommand=Resolve-GuPythonApplication $Python
$lines=& $pythonCommand -I -B (Join-Path $PSScriptRoot 'review-driver-capture.py') $CaptureFolder
if($LASTEXITCODE -ne 0){throw 'Offline review failed. Preserve original files; no hardware retry.'}
$result=($lines -join [Environment]::NewLine)|ConvertFrom-Json
if($result.test -cne 'captured-driver-review-v1' -or $result.write_eligible -or $result.profile_generated){throw 'Unexpected review scope.'}
$folder=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Driver-Review' $CaptureFolder
$path=Join-Path $folder 'driver-review.json'
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('Return only reviewed '+$path+'. Keep captures local; no settings changes or boot.')
