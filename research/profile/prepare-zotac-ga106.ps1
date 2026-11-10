# Issue114 only. Prepare one attended generic probe; never unlock or reboot.
[CmdletBinding()]
param([ValidatePattern('^[D-Zd-z]$')][string]$Drive,[switch]$Collect,
 [string]$Clang='clang',[string]$LldLink='lld-link',[string]$Python='python',[string]$OutputRoot)
$ErrorActionPreference='Stop'
if($MyInvocation.InvocationName -eq '.') {
 . (Join-Path $PSScriptRoot 'prepare-resource-capture.ps1') -Machine issue114 @PSBoundParameters
} else {
 & (Join-Path $PSScriptRoot 'prepare-resource-capture.ps1') -Machine issue114 @PSBoundParameters
 if(!$?){exit 1}
}
