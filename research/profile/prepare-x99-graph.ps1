# Exact-machine attended graph tests. No automatic boot, format or retry.
[CmdletBinding()]
param([ValidatePattern('^[D-Zd-z]$')][string]$Drive, [switch]$Collect,
      [ValidateSet('issue33','issue109','issue31','issue180','issue19')][string]$Machine='issue33',
      [string]$Clang='clang', [string]$LldLink='lld-link', [string]$Python='python',[string]$OutputRoot)
$ErrorActionPreference='Stop'
# Compatibility entry point. Shared implementation and data live alongside it.
if($MyInvocation.InvocationName -eq '.') {
 . (Join-Path $PSScriptRoot 'prepare-graph.ps1') @PSBoundParameters
} else {
 & (Join-Path $PSScriptRoot 'prepare-graph.ps1') @PSBoundParameters
 if(!$?){exit 1}
}
