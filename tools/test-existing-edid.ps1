# Read existing DIAG text only; no supplied code, images, GPU or firmware execution.
[CmdletBinding()]
param([string]$Captures,[string]$Python='python')
$ErrorActionPreference='Stop'
if(!$Captures){$Captures=Read-Host 'Existing folder containing saved DIAG00.TXT / DIAG01.TXT'}
$commands=@(Get-Command $Python -CommandType Application -All -ErrorAction Stop)
if(!$commands.Count){throw 'Existing Python application required; do not install or edit PATH.'}
$command=$commands[0].Source
if($command -match '(?i)[\\/]Microsoft[\\/]WindowsApps[\\/]python(?:3)?\.exe$'){throw 'Python app alias refused; use -Python with an existing known-good interpreter.'}
$root=Split-Path -Parent $PSScriptRoot
$json=& $command -I -B (Join-Path $root 'research/profile/review-edid-bindings.py') $Captures
if($LASTEXITCODE -ne 0){throw 'EDID review stopped. Preserve files; no capture/profile flag/hardware changes.'}
$r=$json|ConvertFrom-Json
if($r.test -cne 'existing-edid-review-v1' -or $r.write_eligible -ne $false){throw 'Unexpected review scope.'}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents unavailable.'}
$out=Join-Path $docs ('GPU-Unlock-Edid-Review-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $out|Out-Null
$path=Join-Path $out 'edid-review.json'
[IO.File]::WriteAllText($path,($json -join [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Host ('Return only reviewed '+$path+'. No raw images or new hardware run requested.')
