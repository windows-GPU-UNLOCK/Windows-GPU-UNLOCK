# GPL-2.0-only. Host test for the BitLocker guard in stage-usb.ps1; mocks only, no USB/disk access.
# Loads Get-BitLockerProtection from the script's AST without running the script itself.
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'stage-usb.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$null,[ref]$null)
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-BitLockerProtection'},$true)
if(-not $fn){throw 'Get-BitLockerProtection not found in stage-usb.ps1'}
. ([scriptblock]::Create($fn.Extent.Text))

# Mocks shadow the real cmdlets inside this script scope.
$script:Volume=$null;$script:VolumeThrows=$true;$script:Shell=$null;$script:ShellThrows=$false
function Get-BitLockerVolume {
 if($script:VolumeThrows){throw 'Access denied (mock)'}
 [pscustomobject]@{ProtectionStatus=$script:Volume}
}
function New-Object {
 if($script:ShellThrows){throw 'COM unavailable (mock)'}
 $self=[pscustomobject]@{};$self|Add-Member ScriptMethod ExtendedProperty {param($n) $script:Shell}
 $ns=[pscustomobject]@{Self=$self}
 $app=[pscustomobject]@{};$app|Add-Member ScriptMethod NameSpace {param($p) $ns}.GetNewClosure()
 $app
}
$checks=0
function Check([string]$Label,[object]$Expected) {
 $got=Get-BitLockerProtection
 if($got -ne $Expected){throw "BitLocker guard failed: $Label (expected '$Expected', got '$got')"}
 $script:checks++
}

# Elevated path: only the explicit enum names are trusted.
$script:VolumeThrows=$false
$script:Shell=2 # must not be consulted when the cmdlet answers
$script:Volume='Off';Check 'elevated Off' 'Off'
$script:Volume='On';Check 'elevated On' 'On'
$script:Volume='Unknown';Check 'elevated Unknown (locked)' $null
$script:Volume=$null;Check 'elevated null status' $null
$script:Volume=0;Check 'elevated numeric 0' $null
$script:Volume='';Check 'elevated empty status' $null

# Cmdlet unavailable or failing: shell property fallback.
$script:VolumeThrows=$true
foreach($v in 2,4,5,'2'){$script:Shell=$v;Check "shell $v unprotected" 'Off'}
foreach($v in 1,3,6){$script:Shell=$v;Check "shell $v protected" 'On'}
foreach($v in @($null,0,7,-1,'','on','2x',[uint32]::MaxValue)){$script:Shell=$v;Check "shell '$v' unrecognized" $null}
$script:ShellThrows=$true;$script:Shell=2;Check 'shell COM failure' $null
"stage-usb BitLocker guard: $checks checks passed"
