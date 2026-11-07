# Shared launcher; machine IDs select exact reviewed preparation pins only.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{0,63}$')][string]$Machine,
      [ValidatePattern('^[D-Zd-z]$')][string]$Drive,[switch]$Collect,
      [string]$Clang='clang',[string]$LldLink='lld-link',[string]$Python='python',[string]$OutputRoot,[switch]$PackagedGraph)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'prepare-graph.ps1') @PSBoundParameters
if(!$?){exit 1}
