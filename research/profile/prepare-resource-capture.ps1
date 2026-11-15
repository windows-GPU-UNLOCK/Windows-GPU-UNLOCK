# Shared exact-target resource capture; never unlock or reboot.
[CmdletBinding()]
param([ValidatePattern('^[a-z][a-z0-9-]{0,63}$')][string]$Machine='issue114',
 [ValidatePattern('^[D-Zd-z]$')][string]$Drive,[switch]$Collect,
 [string]$Clang='clang',[string]$LldLink='lld-link',[string]$Python='python',[string]$OutputRoot,[switch]$PackagedProbe)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
function ProbeHash([string]$Path){
 $sha=[Security.Cryptography.SHA256]::Create();$f=[IO.File]::OpenRead($Path)
 try {([BitConverter]::ToString($sha.ComputeHash($f))).Replace('-','').ToLowerInvariant()}
 finally {$f.Dispose();$sha.Dispose()}
}
function Read-ProbeConfiguration([string]$Id,[string]$Directory=(Join-Path $PSScriptRoot 'probe-configurations')){
 if($Id -cnotmatch '^[a-z][a-z0-9-]{0,63}$'){throw 'Invalid probe configuration ID.'}
 $p=Get-Content -LiteralPath (Join-Path $Directory ($Id+'.json')) -Raw|ConvertFrom-Json
 $keys=@('SchemaVersion','Id','Scope','Board','ManufacturerPrefix','ManufacturerMatch','Bios','CpuToken','TargetBus','TargetDevice','TargetSubsystem','OtherPciVendor','OtherPciDevice','OtherPciSubsystem','NonPci')
 if(@($p.PSObject.Properties).Count -ne $keys.Count -or @($p.PSObject.Properties|Where-Object {$_.Name -cnotin $keys}).Count -or
    $p.SchemaVersion -isnot [int] -or $p.SchemaVersion -ne 2 -or $p.Id -cne $Id -or $p.Scope -cne 'pinned-read-only-resource-capture') {throw 'Invalid probe configuration schema/scope.'}
 foreach($key in @('Board','ManufacturerPrefix','ManufacturerMatch','Bios','CpuToken')){
  if($p.$key -isnot [string] -or [string]::IsNullOrWhiteSpace($p.$key) -or $p.$key.Length -gt 128 -or $p.$key -match '[\x00-\x1f]'){throw 'Invalid machine pin.'}
 }
 if($p.ManufacturerMatch -cnotin @('exact','prefix')){throw 'Invalid manufacturer rule.'}
 if($p.TargetBus -isnot [int] -or $p.TargetBus -lt 1 -or $p.TargetBus -gt 255 -or
    $p.TargetDevice -isnot [string] -or $p.TargetDevice -cnotmatch '^[0-9a-f]{4}10de$' -or
    $p.TargetSubsystem -isnot [string] -or $p.TargetSubsystem -cnotmatch '^[0-9a-f]{8}$' -or
    ($null -ne $p.OtherPciVendor -and ($p.OtherPciVendor -isnot [string] -or $p.OtherPciVendor -cnotmatch '^[0-9A-F]{4}$')) -or
    $p.NonPci -isnot [array] -or $p.NonPci.Count -gt 4){throw 'Invalid device/bus pin.'}
 $seen=@{}
 foreach($a in $p.NonPci){
  if(@($a.PSObject.Properties).Count -ne 3 -or @($a.PSObject.Properties|Where-Object {$_.Name -cnotin @('Enumerator','Provider','Version')}).Count -or
     $a.Enumerator -isnot [string] -or $a.Enumerator -cnotmatch '^[A-Z][A-Z0-9_-]{0,31}$' -or $a.Enumerator -cin @('PCI','ROOT','SWD') -or
     $a.Provider -isnot [string] -or $a.Provider -notmatch '^[A-Za-z0-9 .,-]{1,128}$' -or $a.Version -isnot [string] -or
     $a.Version -notmatch '^[0-9]+(?:\.[0-9]+){1,5}$' -or $seen.ContainsKey($a.Enumerator)){throw 'Invalid non-PCI pin.'}
  $seen[$a.Enumerator]=$true
 }
 if($p.OtherPciVendor){
  if($p.OtherPciDevice -isnot [string] -or $p.OtherPciDevice -cnotmatch '^[0-9A-F]{4}$' -or
     $p.OtherPciSubsystem -isnot [string] -or $p.OtherPciSubsystem -cnotmatch '^[0-9A-F]{8}$'){throw 'Incomplete exact PCI companion pin.'}
 }elseif($null -ne $p.OtherPciDevice -or $null -ne $p.OtherPciSubsystem){throw 'Unexpected PCI companion pin.'}
 return $p
}
function Assert-PinnedProbe($p,$Board,$Bios,$Cpu,$Video,$Drivers=@()){
 $pci=@($Video|Where-Object {$_.PNPDeviceID -match '^PCI\\'})
 $pattern='^PCI\\VEN_10DE&DEV_'+$p.TargetDevice.Substring(0,4)+'&SUBSYS_'+$p.TargetSubsystem+'(?:&|\\|$)'
 $target=@($pci|Where-Object {$_.PNPDeviceID -match $pattern})
 $expectedCount=1;if($p.OtherPciVendor){$expectedCount=2}
 if($target.Count -ne 1 -or $pci.Count -ne $expectedCount){throw 'Exact PCI display inventory mismatch.'}
 if($p.OtherPciVendor -and @($pci|Where-Object {$_.PNPDeviceID -match ('^PCI\\VEN_'+$p.OtherPciVendor+'&DEV_'+$p.OtherPciDevice+'&SUBSYS_'+$p.OtherPciSubsystem+'(?:&|\\|$)')}).Count -ne 1){throw 'Exact PCI companion mismatch.'}
 $other=@($Video|Where-Object {$_.PNPDeviceID -notmatch '^PCI\\'})
 if($other.Count -ne $p.NonPci.Count){throw 'Unknown display identity; stop.'}
 foreach($a in $p.NonPci){
  $v=@($other|Where-Object {$_.PNPDeviceID -cmatch ('^'+[regex]::Escape($a.Enumerator)+'\\')})
  if($v.Count -ne 1){throw 'Non-PCI enumerator mismatch.'}
  $driver=@($Drivers|Where-Object {$_.DeviceID -and $_.DeviceID -ceq $v[0].PNPDeviceID})
  if($driver.Count -ne 1 -or $driver[0].DriverProviderName -cne $a.Provider -or $driver[0].DriverVersion -cne $a.Version -or $driver[0].IsSigned -ne $true){throw 'Non-PCI driver metadata mismatch.'}
 }
 $maker=$false
 if(@($Board).Count -eq 1 -and $Board.Manufacturer -is [string]){
  if($p.ManufacturerMatch -ceq 'exact'){$maker=$Board.Manufacturer -ieq $p.ManufacturerPrefix}
  else{$maker=$Board.Manufacturer.StartsWith($p.ManufacturerPrefix,[StringComparison]::OrdinalIgnoreCase)}
 }
 if(@($Board).Count -ne 1 -or !$maker -or $Board.Product.Trim() -cne $p.Board -or
    @($Bios).Count -ne 1 -or $Bios.SMBIOSBIOSVersion.Trim() -cne $p.Bios -or @($Cpu).Count -ne 1 -or
    $Cpu.Name -notmatch ('\b'+[regex]::Escape($p.CpuToken)+'\b')){throw 'Exact board/BIOS/CPU mismatch; stop without changing settings.'}
}
function Assert-Zotac114($Board,$Bios,$Cpu,$Video){Assert-PinnedProbe (Read-ProbeConfiguration 'issue114') $Board $Bios $Cpu $Video}
function Assert-ProbeUsb($Part,$Disk,$Volume,[switch]$ReadOnly){
 if(@($Part).Count -ne 1 -or @($Disk).Count -ne 1 -or @($Volume).Count -ne 1 -or
    $Disk.BusType -ne 'USB' -or $Volume.FileSystem -ne 'FAT32' -or $Part.IsSystem -or $Part.IsBoot -or
    $Disk.IsBoot -or $Disk.IsSystem -or $Disk.IsOffline -or !$Disk.UniqueId -or
    (!$ReadOnly -and ($Disk.IsReadOnly -or $Volume.SizeRemaining -lt 256MB))){throw 'Need a FAT32 USB data stick, 256 MB free for preparation. No format is performed.'}
}
function Archive-ProbeCaptures([string]$Root){
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 $folder=[IO.Path]::GetFullPath((Join-Path $Root 'RTX3090-UNLOCK'))
 if(!$folder.StartsWith($rootPath,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($folder) -cne 'RTX3090-UNLOCK'){throw 'Invalid archive boundary.'}
 if(Test-Path -LiteralPath $folder){
  $name='RTX3090-UNLOCK.before-probe-'+[guid]::NewGuid().ToString('N')
  $archive=[IO.Path]::GetFullPath((Join-Path $Root $name))
  if(!$archive.StartsWith($rootPath,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $archive)){throw 'Invalid archive destination.'}
  Rename-Item -LiteralPath $folder -NewName $name
  if((Test-Path -LiteralPath $folder) -or !(Test-Path -LiteralPath $archive)){throw 'Archive rename failed. Do not boot.'}
 }
 New-Item -ItemType Directory -Path $folder -Force | Out-Null
}
function Stage-Probe([string]$Root,[string]$Image,[string]$Hash,[string]$Case='issue114',[string]$ConfigurationHash){
 if((ProbeHash $Image) -cne $Hash){throw 'Built image hash mismatch.'}
 if((Test-Path -LiteralPath (Join-Path $Root 'RTX3090-UNLOCK/probe114-stage.json')) -or (Test-Path -LiteralPath (Join-Path $Root 'RTX3090-UNLOCK/pinned-probe-stage.json'))){throw 'This attended run is already staged. Collect/review its files; do not restage or repeat automatically.'}
 $boot=Join-Path $Root 'EFI/BOOT/BOOTX64.EFI';$temp=Join-Path $Root 'EFI/BOOT/PROBE-NEW.EFI'
 if(Test-Path -LiteralPath $temp){throw 'Partial staging exists; stop rather than retry.'}
 $old=$null
 if(Test-Path -LiteralPath $boot){
  $old=ProbeHash $boot;$backup=Join-Path $Root ('EFI/BOOT/BEFORE-PROBE-'+$old+'.EFI')
  if(!(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $boot -Destination $backup}
  if((ProbeHash $backup) -cne $old){throw 'Original boot loader backup failed verification.'}
 }
 Archive-ProbeCaptures $Root
 New-Item -ItemType Directory -Path (Split-Path $boot) -Force | Out-Null
 Copy-Item -LiteralPath $Image -Destination $temp
 if((ProbeHash $temp) -cne $Hash){throw 'Copy readback failed; old boot loader retained.'}
 if($old -and (ProbeHash $boot) -cne $old){throw 'USB boot file changed; stop.'}
 Move-Item -LiteralPath $temp -Destination $boot -Force
 if((ProbeHash $boot) -cne $Hash){throw 'Final copy verification failed. Do not boot.'}
 $stage=if($Case -ceq 'issue114'){'probe114-stage.json'}else{'pinned-probe-stage.json'}
 [IO.File]::WriteAllText((Join-Path $Root ('RTX3090-UNLOCK/'+$stage)),
  (@{Mode='pinned-read-only-probe';Machine=$Case;ConfigurationSha256=$ConfigurationHash;EfiSha256=$Hash} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
function Export-ProbeReport([string]$Repo,[string]$Folder,[string]$Output,[string]$Python,[string]$Case='issue114'){
 $p=New-Object System.Diagnostics.Process
 try {
  $p.StartInfo.FileName=Resolve-GuPythonApplication $Python
  $p.StartInfo.Arguments='-I research/profile/check-compatibility.py "'+(Join-Path $folder '.')+'" --json'
  $p.StartInfo.WorkingDirectory=$repo;$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
  $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  $p.StartInfo.StandardOutputEncoding=New-Object System.Text.UTF8Encoding($false)
  $p.Start() | Out-Null;$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  if(!$p.WaitForExit(120000)){$p.Kill();throw 'Offline report timed out.'}
  if($p.ExitCode -notin @(0,2,3)){throw 'Offline report failed; keep original USB files local.'}
  $report=$stdout.Result | ConvertFrom-Json
  if($report.write_eligible -ne $false -or $report.hardware_tested -ne $false -or $report.route -cne 'automatic_local_profile'){throw 'Unexpected report.'}
  $report.next_step='Await review of this attended capture. Do not repeat the boot, generate a profile or stage unlock yet.'
  $paths=@(Get-ChildItem -LiteralPath $folder -Filter 'DIAG??.TXT' -File | Where-Object {$_.Name -match '^DIAG[0-9]{2}\.TXT$'})
  if($paths.Count -gt 4){throw 'Too many captures for this one-run review; preserve them and stop.'}
  $markers=@($paths | ForEach-Object {
   if($_.Length -gt 8MB){throw 'Capture exceeds the summary limit.'}
   $text=[IO.File]::ReadAllText($_.FullName)
   [ordered]@{Capture=$_.Name;Sha256=(ProbeHash $_.FullName)
    CompleteMarkers=@([regex]::Matches($text,'(?m)^capture-complete=([01])\r?$') | ForEach-Object {$_.Groups[1].Value})
    EnvelopeRefusalRecorded=$text.Contains('incomplete reason=probe-unreviewed-envelope status=0x8000000000000003')
    FailedMmioReads=@([regex]::Matches($text,'(?m)^mmio off=0x[0-9a-f]{8} status=(0x[0-9a-f]{16}) value=0x[0-9a-f]{8}\r?$') | Where-Object {$_.Groups[1].Value -cne '0x0000000000000000'}).Count}
  })
  $public=[ordered]@{Test=($Case+'-pinned-probe-review');HardwareVerified=$false;WriteEligible=$false;Compatibility=$report;CaptureMarkers=$markers}
  [IO.File]::WriteAllText((Join-Path $output 'report.json'),($public | ConvertTo-Json -Depth 18),[Text.UTF8Encoding]::new($false))
 } finally {$p.Dispose()}
}
if($MyInvocation.InvocationName -eq '.'){return}
if($OutputRoot -and !$Collect){throw '-OutputRoot is collection-only.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$configurationPath=Join-Path $PSScriptRoot ('probe-configurations/'+$Machine+'.json')
$configurationHash=ProbeHash $configurationPath
$configuration=Read-ProbeConfiguration $Machine
if(!$Drive){$Drive=Read-Host 'FAT32 USB drive letter'}
if($Drive -notmatch '^[D-Zd-z]$'){throw 'Enter one drive letter D through Z.'}
$part=Get-Partition -DriveLetter $Drive;$disk=Get-Disk -Number $part.DiskNumber;$volume=Get-Volume -DriveLetter $Drive
Assert-ProbeUsb $part $disk $volume -ReadOnly:$Collect
$usb=$Drive.ToUpperInvariant()+':\'
if($Collect){
 $folder=Join-Path $usb 'RTX3090-UNLOCK'
 $output=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Resource-Review' $usb
 Export-ProbeReport $repo $folder $output $Python $Machine
 Write-Host ('Return reviewed report.json from '+$output+' and say whether Windows started directly or manual recovery was needed. Keep all PROM/IMG/DIAG files local.')
 exit 0
}
$drivers=@();if($configuration.NonPci.Count){$drivers=@(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'")}
Assert-PinnedProbe $configuration (Get-CimInstance Win32_BaseBoard) (Get-CimInstance Win32_BIOS) (Get-CimInstance Win32_Processor) @(Get-CimInstance Win32_VideoController) $drivers
. (Join-Path $PSScriptRoot 'encryption-state.ps1')
Assert-GuDecryptedVolume
try {$secure=Confirm-SecureBootUEFI}catch{throw 'Secure Boot state cannot be verified. Stop; do not change settings.'}
if($secure -isnot [bool] -or $secure -ne $false){throw 'Secure Boot must already be off. Do not change it for this test.'}
$windows=@(Get-Partition | Where-Object {$_.IsSystem -and $_.Guid})
if($windows.Count -ne 1 -or $windows[0].DiskNumber -eq $part.DiskNumber){throw 'Cannot uniquely pin current internal Windows ESP.'}
Write-Host 'NEW boundary: PCI resource/attribute/parent reads, 16 fixed target BAR0 DWORDs and full 1 MiB PROM (up to 262160 direct MMIO reads), plus loaded firmware-driver image copies from CPU memory.'
Write-Host 'No GPU/PCI writes, driver detach, reset, GPU firmware execution/upload or unlock. Reads may have side effects; display/input/firmware or Windows may hang. Recovery is unproven.'
Write-Host 'Manual power-off/USB removal and normal Windows Boot Manager may be needed. No automatic retry or rollback. Existing USB captures are renamed to a preserved archive.'
if($PackagedProbe){
 if($Machine -cne 'issue172' -or (Read-Host 'Only if the reviewed graph run returned directly to Windows without manual recovery, type GRAPH-DIRECT; otherwise stop and report') -cne 'GRAPH-DIRECT'){throw 'Previous graph return is not confirmed direct. No new hardware preparation.'}
}
if((Read-Host 'Accept ONE attended capture? Type ACCEPT-MMIO to prepare; anything else stops') -cne 'ACCEPT-MMIO'){throw 'Stopped without staging.'}
if($PackagedProbe){
 . (Join-Path $PSScriptRoot 'resource-template.ps1')
 $built=New-GuResourceTemplate $repo ([guid]$windows[0].Guid) $Machine (Join-Path $repo ('internal-boot/boot/build/probe-pinned-'+[guid]::NewGuid().ToString('N')))
}else{
 & (Join-Path $PSScriptRoot 'build-probe.ps1') -WindowsEspGuid ([guid]$windows[0].Guid) -TargetBus $configuration.TargetBus -ExpectedDevice $configuration.TargetDevice -ExpectedSubsystem $configuration.TargetSubsystem -Clang $Clang -LldLink $LldLink -Python $Python
 if(!$?){throw 'Probe build failed.'}
 $built=Join-Path $repo 'internal-boot/boot/build/probe-generic'
}
. (Join-Path $PSScriptRoot 'probe-manifest.ps1')
$image=Join-Path $built 'BOOTX64.EFI'
$manifest=Get-Content -LiteralPath (Join-Path $built 'manifest.json') -Raw | ConvertFrom-Json
Assert-GuGenericProbeManifest $repo $manifest $image
if($manifest.ExpectedDevice -cne $configuration.TargetDevice -or $manifest.ExpectedSubsystem -cne $configuration.TargetSubsystem -or $manifest.ExpectedSegment -ne 0 -or $manifest.TargetBus -ne $configuration.TargetBus){throw 'Probe pins do not match the selected configuration.'}
$pe=Get-Content -LiteralPath (Join-Path $built 'pe-verification.json') -Raw | ConvertFrom-Json
if($pe.machine -cne 'AMD64' -or $pe.subsystem -ne 10 -or $pe.imports -ne 0 -or $pe.sha256 -cne $manifest.EfiSha256){throw 'Missing or mismatched PE verification.'}
$fresh=Get-Partition -DriveLetter $Drive;$freshDisk=Get-Disk -Number $fresh.DiskNumber
Assert-ProbeUsb $fresh $freshDisk (Get-Volume -DriveLetter $Drive)
if($freshDisk.UniqueId -cne $disk.UniqueId -or $fresh.DiskNumber -ne $part.DiskNumber -or $fresh.Offset -ne $part.Offset -or $fresh.Size -ne $part.Size){throw 'USB identity changed; stop.'}
if((ProbeHash $configurationPath) -cne $configurationHash){throw 'Configuration changed; do not stage.'}
$drivers=@();if($configuration.NonPci.Count){$drivers=@(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'")}
Assert-PinnedProbe $configuration (Get-CimInstance Win32_BaseBoard) (Get-CimInstance Win32_BIOS) (Get-CimInstance Win32_Processor) @(Get-CimInstance Win32_VideoController) $drivers
Assert-GuDecryptedVolume
try{$freshSecure=Confirm-SecureBootUEFI}catch{throw 'Secure Boot recheck failed; do not stage.'}
if($freshSecure -isnot [bool] -or $freshSecure -ne $false){throw 'Secure Boot is not verified disabled; keep policy unchanged and stop.'}
Stage-Probe $usb $image $manifest.EfiSha256 $Machine $configurationHash
Write-Host 'READY. Fully shut down and manually select this USB once. No Shift keys. Expect capture then Windows.'
Write-Host 'If Windows has not started within two minutes, power off, remove USB and use normal Windows Boot Manager. Do not repeat.'
Write-Host 'In Windows run this same script with -Collect. Return only report.json and the Windows outcome; remove USB afterward.'
