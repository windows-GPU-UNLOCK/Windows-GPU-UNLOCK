# Trusted shared RAM-only host model. No GPU/EFI execution or staging.
[CmdletBinding()]
param([string]$Python='python',[string]$Clang='clang',[string]$VcVars,[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../profile/host.ps1')
$commands=@(Get-Command $Python -CommandType Application -All -ErrorAction Stop)
if(!$commands.Count){throw 'Existing Python application required; do not install or change PATH.'}
$command=$commands[0].Source
if($command -match '(?i)[\\/]Microsoft[\\/]WindowsApps[\\/]python(?:3)?\.exe$'){throw 'Python app alias refused; use -Python with your existing interpreter.'}
Import-GuHostCompiler $VcVars
$parentPath=$OutputRoot
if(!$parentPath){$parentPath=[Environment]::GetFolderPath('MyDocuments')}
$parent=Get-Item -LiteralPath $parentPath
if(!$parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $parent.FullName.StartsWith('\\')){throw 'Use an existing regular local output folder.'}
$out=Join-Path $parent.FullName ('GPU-Unlock-Decode-Host-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $out|Out-Null
# The Python runner requires its output directory to not exist.
$run=Join-Path $out 'run'
$family=Join-Path $PSScriptRoot '../profile/test_family_admission.py'
& $command -I -B $family
if($LASTEXITCODE -ne 0){throw 'Exact device/family/driver admission tests failed. No hardware run.'}
& $command -I -B (Join-Path $PSScriptRoot 'test-decode-sync.py') --clang $Clang --output $run --mutations
if($LASTEXITCODE -ne 0){throw 'RAM-only host validation failed. Stop; no install, policy change or hardware boot.'}
$summaryPath=Join-Path $run 'summary.json'
$summary=Get-Content -LiteralPath $summaryPath -Raw|ConvertFrom-Json
$summary|Add-Member -NotePropertyName exact_family_admission_tests_passed -NotePropertyValue $true
$summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host ('Return only reviewed '+(Join-Path $run 'summary.json')+'. No raw logs, capture or hardware repeat requested.')
