# Filesystem/application-resolution regressions only; fake executables are never run.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};if(!$failed){throw 'Expected refusal.'}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('collection-host-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$first=Join-Path $root 'first python.exe';$second=Join-Path $root 'second python.exe'
[IO.File]::WriteAllText($first,'not executable');[IO.File]::WriteAllText($second,'not executable')
$find={param($name) [pscustomobject]@{Source=$first};[pscustomobject]@{Source=$second}}
$chosen=Resolve-GuPythonApplication 'python' $find
if($chosen -isnot [string] -or $chosen -cne $first){throw 'Multiple PATH results did not choose exactly the first application.'}
Reject {Resolve-GuPythonApplication 'python' {param($name) @()}}
Reject {Resolve-GuPythonApplication 'python' {param($name) [pscustomobject]@{Source=@($first,$second)}}}
Reject {Resolve-GuPythonApplication 'python' {param($name) throw 'PRIVATE-ERROR'}}
$alias=Join-Path $root 'Microsoft/WindowsApps/python.exe'
New-Item -ItemType Directory -Path (Split-Path $alias)|Out-Null
[IO.File]::WriteAllText($alias,'alias fixture')
Reject {Resolve-GuPythonApplication 'python' {param($name) [pscustomobject]@{Source=$alias};[pscustomobject]@{Source=$first}}}
$output=New-GuCollectionOutput $root 'GPU-Unlock-Graph' (Join-Path $root 'capture')
if(!(Test-Path -LiteralPath $output -PathType Container)){throw 'Explicit output root failed.'}
Reject {New-GuCollectionOutput $first 'GPU-Unlock-Graph' ''}
Reject {New-GuCollectionOutput (Join-Path $root 'missing') 'GPU-Unlock-Graph' ''}
$capture=Join-Path $root 'capture';New-Item -ItemType Directory -Path $capture|Out-Null
$log=Join-Path $capture 'DIAG00.TXT';[IO.File]::WriteAllText($log,'unchanged original')
$before=(Get-FileHash $log).Hash
Reject {New-GuCollectionOutput $capture 'GPU-Unlock-Graph' $capture}
if((Get-FileHash $log).Hash -cne $before -or @(Get-ChildItem $capture).Count -ne 1){throw 'Refused output touched capture input.'}
# Simulate a blocked Documents write, without changing ACLs or protection settings.
function New-Item {param($ItemType,$Path,$ErrorAction);throw 'PRIVATE-FOLDER-DENIED'}
$failed=$false
try{New-GuCollectionOutput $root 'GPU-Unlock-Graph' ''|Out-Null}catch{$failed=$true;if($_.Exception.Message.Contains('PRIVATE')){throw 'Folder error leaked private path.'}}
if(!$failed){throw 'Blocked output write accepted.'}
Write-Host 'PASS: multiple Python applications, scalar/alias/unknown refusal, explicit local output, blocked write, capture preservation and error privacy. No fake executable run.'
