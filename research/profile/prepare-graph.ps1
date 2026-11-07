# Exact-machine attended graph tests. No automatic boot, format or retry.
[CmdletBinding()]
param([ValidatePattern('^[D-Zd-z]$')][string]$Drive, [switch]$Collect,
      [ValidatePattern('^[a-z][a-z0-9-]{0,63}$')][string]$Machine='issue33',
      [string]$Clang='clang', [string]$LldLink='lld-link', [string]$Python='python',[string]$OutputRoot,[switch]$PackagedGraph)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
function Assert-GraphUnsignedBootPolicy($State) {
 # A false-like string/integer is not a verified firmware policy result.
 if($State -isnot [bool] -or $State){throw 'Secure Boot is enabled or unknown; do not prepare/stage or change settings.'}
}
function Get-GraphHash([string]$Path) {
 $h=[Security.Cryptography.SHA256]::Create();$f=[IO.File]::OpenRead($Path)
 try {([BitConverter]::ToString($h.ComputeHash($f))).Replace('-','').ToLowerInvariant()}
 finally {$f.Dispose();$h.Dispose()}
}
function Read-GraphConfiguration([string]$Id,[string]$Directory=(Join-Path $PSScriptRoot 'graph-configurations')) {
 if($Id -cnotmatch '^[a-z][a-z0-9-]{0,63}$'){throw 'Invalid configuration ID.'}
 $p=Get-Content -LiteralPath (Join-Path $Directory ($Id+'.json')) -Raw | ConvertFrom-Json
 $keys=@('SchemaVersion','Id','Scope','Board','ManufacturerPrefix','ManufacturerMatch','Bios','CpuToken','Adapters')
 $optional=@('KnownNonPciAdapters')
 if(@($p.PSObject.Properties | Where-Object {$_.Name -cnotin ($keys+$optional)}).Count -or
    @($keys | Where-Object {$_ -cnotin @($p.PSObject.Properties.Name)}).Count){throw 'Unexpected graph configuration fields.'}
 if($p.PSObject.Properties.Name -contains 'KnownNonPciAdapters'){
  if($p.KnownNonPciAdapters -isnot [array] -or $p.KnownNonPciAdapters.Count -gt 4){throw 'Invalid non-PCI adapter list.'}
  $enumSeen=@{}
  foreach($a in $p.KnownNonPciAdapters){
   $fields=@('Enumerator','Provider','Version')
   if(@($a.PSObject.Properties).Count -ne 3 -or @($a.PSObject.Properties | Where-Object {$_.Name -cnotin $fields}).Count -or
      $a.Enumerator -isnot [string] -or $a.Enumerator -cnotmatch '^[A-Z][A-Z0-9_-]{0,31}$' -or $a.Enumerator -cin @('PCI','ROOT','SWD') -or
      $a.Provider -isnot [string] -or $a.Provider -notmatch '^[A-Za-z0-9 .,-]{1,128}$' -or
      $a.Version -isnot [string] -or $a.Version -notmatch '^[0-9]+(?:\.[0-9]+){1,5}$' -or $enumSeen.ContainsKey($a.Enumerator)){throw 'Invalid non-PCI adapter pin.'}
   $enumSeen[$a.Enumerator]=$true
  }
 }

 if($p.SchemaVersion -isnot [int] -or $p.SchemaVersion -ne 1 -or $p.Id -cne $Id -or $p.Scope -cne 'graph-only'){throw 'Invalid graph configuration identity or scope.'}
 foreach($key in @('Board','ManufacturerPrefix','Bios','CpuToken')) {
  if($p.$key -isnot [string] -or [string]::IsNullOrWhiteSpace($p.$key) -or $p.$key.Length -gt 128 -or $p.$key -match '[\x00-\x1f]'){throw 'Invalid graph identity field.'}
 }
 if($p.ManufacturerMatch -cnotin @('exact','prefix')){throw 'Invalid manufacturer match rule.'}
 if($p.Adapters -isnot [array] -or $p.Adapters.Count -lt 1 -or $p.Adapters.Count -gt 8){throw 'Invalid graph adapter list.'}
 $seen=@{}
 foreach($adapter in $p.Adapters){
  $fields=@('Vendor','Device','Subsystem')
  if(@($adapter.PSObject.Properties).Count -ne 3 -or @($adapter.PSObject.Properties | Where-Object {$_.Name -cnotin $fields}).Count){throw 'Invalid adapter fields.'}
  if($adapter.Vendor -isnot [string] -or $adapter.Device -isnot [string] -or $adapter.Subsystem -isnot [string] -or
     $adapter.Vendor -cnotmatch '^[0-9A-F]{4}$' -or $adapter.Device -cnotmatch '^[0-9A-F]{4}$' -or $adapter.Subsystem -cnotmatch '^[0-9A-F]{8}$'){throw 'Invalid adapter tuple.'}
  $tuple=$adapter.Vendor+':'+$adapter.Device+':'+$adapter.Subsystem
  if($seen.ContainsKey($tuple)){throw 'Duplicate adapter tuple is ambiguous.'};$seen[$tuple]=$true
 }
 return $p
}
function Assert-GraphMachine([string]$Id,$Board,$Bios,$Cpu,$Video,$Drivers=@()) {
 $p=Read-GraphConfiguration $Id
 # Software adapters do not establish firmware ownership. Unknown identity
 # formats remain a refusal, rather than being silently discarded.
 $pciVideo=@($Video | Where-Object {$_.PNPDeviceID -match '^PCI\\'})
 $other=@($Video | Where-Object {$_.PNPDeviceID -notmatch '^PCI\\'})
 $expectedOther=@($p.KnownNonPciAdapters | Where-Object {$_})
 if($other.Count -ne $expectedOther.Count){throw 'Ambiguous display inventory; stop and report.'}
 foreach($a in $expectedOther){
  $matchesAdapter=@($other | Where-Object {$_.PNPDeviceID -cmatch ('^'+[regex]::Escape($a.Enumerator)+'\\')})
  if($matchesAdapter.Count -ne 1){throw 'Non-PCI display enumerator mismatch; stop and report.'}
  $driver=@($Drivers | Where-Object {$_.DeviceID -and $_.DeviceID -ceq $matchesAdapter[0].PNPDeviceID})
  if($driver.Count -ne 1 -or $driver[0].DriverProviderName -cne $a.Provider -or
     $driver[0].DriverVersion -cne $a.Version -or $driver[0].IsSigned -ne $true){throw 'Non-PCI display driver metadata mismatch; stop and report.'}
 }

 $displayOk=$pciVideo.Count -eq $p.Adapters.Count
 foreach($adapter in $p.Adapters){
  $identity='^PCI\\VEN_'+$adapter.Vendor+'&DEV_'+$adapter.Device+'&SUBSYS_'+$adapter.Subsystem+'(?:&|\\|$)'
  if(@($pciVideo | Where-Object {$_.PNPDeviceID -match $identity}).Count -ne 1){$displayOk=$false}
 }
 $manufacturerOk=$false
 if(@($Board).Count -eq 1 -and $Board.Manufacturer -is [string]){
  if($p.ManufacturerMatch -ceq 'exact'){$manufacturerOk=$Board.Manufacturer -ieq $p.ManufacturerPrefix}
  else {$manufacturerOk=$Board.Manufacturer.StartsWith($p.ManufacturerPrefix,[StringComparison]::OrdinalIgnoreCase)}
 }
 if(@($Board).Count -ne 1 -or $Board.Product.Trim() -cne $p.Board -or
    !$manufacturerOk -or @($Bios).Count -ne 1 -or
    $Bios.SMBIOSBIOSVersion.Trim() -cne $p.Bios -or @($Cpu).Count -ne 1 -or
    $Cpu.Name -notmatch ('\b'+[regex]::Escape($p.CpuToken)+'\b') -or !$displayOk) {
  throw "Machine does not match $Id's exact board/BIOS/CPU/display-adapter pins. Stop and report the mismatch."
 }
}
function Assert-X99GraphMachine($Board,$Bios,$Cpu,$Video){Assert-GraphMachine 'issue33' $Board $Bios $Cpu $Video}
function Assert-GraphUsb($Partition,$Disk,$Volume,[switch]$CollectOnly) {
 if(@($Partition).Count -ne 1 -or @($Disk).Count -ne 1 -or @($Volume).Count -ne 1 -or
    $Disk.BusType -ne 'USB' -or $Volume.FileSystem -ne 'FAT32' -or
    $Partition.IsSystem -or $Partition.IsBoot -or $Disk.IsBoot -or $Disk.IsSystem -or
    $Disk.IsOffline -or !$Disk.UniqueId -or
    (!$CollectOnly -and ($Disk.IsReadOnly -or $Volume.SizeRemaining -lt 16MB))) {throw 'Preparation needs a writable FAT32 USB data stick with at least 16 MB free; collection only reads it. No formatting is performed.'}
}
function Copy-GraphBoot([string]$Root,[string]$Image,[string]$ExpectedHash,[string]$MachineId='issue33') {
 if((Get-GraphHash $Image) -cne $ExpectedHash){throw 'Built EFI hash mismatch.'}
 $capture=Join-Path $Root 'RTX3090-UNLOCK'
 if((Test-Path -LiteralPath $capture) -and @(Get-ChildItem -LiteralPath $capture -Force).Count){throw 'Capture folder is not empty. Preserve it; do not mix or repeat tests.'}
 $boot=Join-Path $Root 'EFI/BOOT/BOOTX64.EFI';$temp=Join-Path $Root 'EFI/BOOT/GRAPH-NEW.EFI'
 if(Test-Path -LiteralPath $temp){throw 'A previous staging file exists. Stop; no automatic retry.'}
 $oldHash=$null;$backup=$null
 if(Test-Path -LiteralPath $boot){
  $oldHash=Get-GraphHash $boot
  $backup=Join-Path $Root ('EFI/BOOT/BEFORE-GRAPH-'+$oldHash+'.EFI')
  if(!(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $boot -Destination $backup}
  if((Get-GraphHash $backup) -cne $oldHash){throw 'Previous boot loader backup verification failed.'}
 }
 New-Item -ItemType Directory -Path (Split-Path $boot),$capture -Force | Out-Null
 Copy-Item -LiteralPath $Image -Destination $temp
 if((Get-GraphHash $temp) -cne $ExpectedHash){throw 'Staged EFI readback failed; original boot file is retained.'}
 if($oldHash -and (Get-GraphHash $boot) -cne $oldHash){throw 'Existing USB boot file changed; stop.'}
 Move-Item -LiteralPath $temp -Destination $boot -Force
 if((Get-GraphHash $boot) -cne $ExpectedHash){throw 'Final USB readback failed. Do not boot.'}
 [ordered]@{Mode='machine-graph-only';Machine=$MachineId;EfiSha256=$ExpectedHash;PreviousBootSha256=$oldHash}
}
# Dot sourcing exposes only the pure validation/staging functions to host tests.
if($MyInvocation.InvocationName -eq '.'){return}
if($OutputRoot -and !$Collect){throw '-OutputRoot is collection-only.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(!$Drive){$Drive=Read-Host 'FAT32 USB drive letter (for example D)'}
if($Drive -notmatch '^[D-Zd-z]$'){throw 'Enter one drive letter from D through Z.'}
$part=Get-Partition -DriveLetter $Drive
$disk=Get-Disk -Number $part.DiskNumber
$volume=Get-Volume -DriveLetter $Drive
Assert-GraphUsb $part $disk $volume -CollectOnly:$Collect
$usb=$Drive.ToUpperInvariant()+':\'
if($Collect){
 $output=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Graph' $usb
 $pythonApplication=Resolve-GuPythonApplication $Python
 & $pythonApplication -I (Join-Path $PSScriptRoot 'summarize-graph.py') (Join-Path $usb 'RTX3090-UNLOCK') (Join-Path $output 'graph-summary.json')
 if($LASTEXITCODE -ne 0){throw 'Collection summary failed. Keep the USB unchanged and report the short error.'}
 Write-Host ('Return graph-summary.json from '+$output+' and say whether Windows started directly or needed manual recovery.')
 exit 0
}
$configurationPath=Join-Path $PSScriptRoot ('graph-configurations/'+$Machine+'.json')
$configurationHash=Get-GraphHash $configurationPath
$configuration=Read-GraphConfiguration $Machine
$drivers=@()
if(@($configuration.KnownNonPciAdapters | Where-Object {$_}).Count){$drivers=@(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'")}
Assert-GraphMachine $Machine (Get-CimInstance Win32_BaseBoard) (Get-CimInstance Win32_BIOS) (Get-CimInstance Win32_Processor) @(Get-CimInstance Win32_VideoController) $drivers
. (Join-Path $PSScriptRoot 'encryption-state.ps1')
Assert-GuDecryptedVolume
try {$secure=Confirm-SecureBootUEFI} catch {throw 'Secure Boot state could not be verified. Stop and report; do not change settings.'}
Assert-GraphUnsignedBootPolicy $secure
$windows=@(Get-Partition | Where-Object {$_.IsSystem -and $_.Guid})
if($windows.Count -ne 1 -or $windows[0].DiskNumber -eq $part.DiskNumber){throw 'Cannot uniquely pin the current internal Windows ESP.'}
Write-Host 'ONE attended EFI graph test: firmware protocol/GOP metadata and PCI-header reads, USB log, then attempted Windows boot.'
Write-Host 'No GPU MMIO/PROM, driver release, unlock or firmware-variable writes. Firmware/display/input may hang; Windows may fail to start.'
Write-Host 'Recovery is unproven: power off, remove this USB, and choose your normal Windows Boot Manager. No automatic retry or rollback.'
if((Read-Host 'If you accept this boundary, type PREPARE (anything else stops)') -cne 'PREPARE'){throw 'Stopped without staging.'}
if($PackagedGraph){
 . (Join-Path $PSScriptRoot 'graph-template.ps1')
 $built=New-PinnedGraphFromTemplate $repo ([guid]$windows[0].Guid) (Join-Path $repo ('internal-boot/boot/build/graph-pinned-'+[guid]::NewGuid().ToString('N')))
}else{
 & (Join-Path $PSScriptRoot 'build-graph-only.ps1') -WindowsEspGuid ([guid]$windows[0].Guid) -Clang $Clang -LldLink $LldLink -Python $Python
 if(!$?){throw 'Graph build failed; do not boot.'}
 $built=Join-Path $repo 'internal-boot/boot/build/graph-only'
}
$manifest=Get-Content -LiteralPath (Join-Path $built 'manifest.json') -Raw | ConvertFrom-Json
if($manifest.FixtureOnly -ne $false -or $manifest.Mode -cne 'graph-only-build' -or
   $manifest.CanUnlock -ne $false -or $manifest.CanDetach -ne $false -or $manifest.ReadsGpuMmio -ne $false){throw 'Unexpected graph build manifest.'}
# Recheck the target after compilation before any USB write.
$fresh=Get-Partition -DriveLetter $Drive
$freshDisk=Get-Disk -Number $fresh.DiskNumber
Assert-GraphUsb $fresh $freshDisk (Get-Volume -DriveLetter $Drive)
if($fresh.DiskNumber -ne $part.DiskNumber -or $fresh.Offset -ne $part.Offset -or $fresh.Size -ne $part.Size -or
   $freshDisk.UniqueId -cne $disk.UniqueId){throw 'USB partition changed; do not stage.'}
if((Get-GraphHash $configurationPath) -cne $configurationHash){throw 'Configuration changed during preparation; do not stage.'}
# Driver metadata can change while building. Do not retain stale exceptions.
if(@($configuration.KnownNonPciAdapters | Where-Object {$_}).Count){
 Assert-GraphMachine $Machine (Get-CimInstance Win32_BaseBoard) (Get-CimInstance Win32_BIOS) (Get-CimInstance Win32_Processor) @(Get-CimInstance Win32_VideoController) @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'")
}
Assert-GuDecryptedVolume
try {$freshSecure=Confirm-SecureBootUEFI} catch {throw 'Secure Boot recheck failed; do not stage.'}
Assert-GraphUnsignedBootPolicy $freshSecure
$receipt=Copy-GraphBoot $usb (Join-Path $built 'GRAPH-ONLY.EFI') $manifest.EfiSha256 $Machine
$receipt['ConfigurationSha256']=$configurationHash
$receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $usb 'RTX3090-UNLOCK/graph-stage.json') -Encoding utf8
Write-Host 'READY: fully shut down, then manually select this USB once from the firmware boot menu. No keys are required in the test.'
Write-Host 'If Windows has not started after two minutes, power off, remove the USB and use normal Windows Boot Manager. Do not repeat this run.'
Write-Host 'After Windows returns, run this same script with -Collect and the same USB drive letter. Keep raw DIAG logs local.'
