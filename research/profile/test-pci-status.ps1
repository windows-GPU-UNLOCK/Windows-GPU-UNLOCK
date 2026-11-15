# CPU-only source regression; no private firmware, captures, EFI or hardware.
[CmdletBinding()]
param([string]$Python='python',[string]$Clang='clang',[string]$VcVars,[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'host.ps1')
$pythonApp=(Get-Command $Python -CommandType Application -ErrorAction Stop).Source
if($pythonApp -match '(?i)[\\/]Microsoft[\\/]WindowsApps[\\/]python(?:3)?\.exe$'){throw 'Python alias refused; use an existing interpreter, no installation or PATH change.'}
Import-GuHostCompiler $VcVars
if(!$OutputRoot){$OutputRoot=[Environment]::GetFolderPath('MyDocuments')}
$parent=Get-Item -LiteralPath $OutputRoot
if(!$parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $parent.FullName.StartsWith('\\')){throw 'Use an existing regular local output directory.'}
$out=Join-Path $parent.FullName ('GPU-Unlock-Pci-Status-'+[guid]::NewGuid().ToString('N').Substring(0,8))
& $pythonApp -I -B (Join-Path $PSScriptRoot 'test-pci-status.py') --clang $Clang --output $out
if($LASTEXITCODE -ne 0){throw 'Source comparison test failed; stop without hardware retry, settings changes or dependency installation.'}
Write-Host ('Return only reviewed '+(Join-Path $out 'pci-status.json')+'. No raw logs or hardware rerun required.')
