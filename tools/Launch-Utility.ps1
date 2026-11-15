<#
.SYNOPSIS
    Convenience launcher for the Windows GPU UNLOCK Utility.
#>
[CmdletBinding()]
param(
    [switch]$Cli,
    [string]$Action = 'Audit',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$script = Join-Path $PSScriptRoot "gpu_unlock_utility\GpuUnlockUtility.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    Write-Error "Could not find GpuUnlockUtility.ps1 at $script"
    exit 1
}


if ($Cli) {
    if ($RemainingArgs) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Cli -Action $Action @RemainingArgs
    }
    else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Cli -Action $Action
    }
}
else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script
}

