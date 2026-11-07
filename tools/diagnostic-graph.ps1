# GPL-2.0-only. Internal graph-only handlers for the single diagnostic launcher.
# Dot sourcing defines functions. It never queries devices, stages media or prompts.
if($MyInvocation.InvocationName -ne '.'){throw 'Internal module. Use Start-Capture.cmd.'}
function Import-GuDiagnosticGraphHelpers {
 # Keep the old script's parameters/preferences out of the launcher's scope.
 . (Join-Path $PSScriptRoot '../research/profile/prepare-graph.ps1')
 . (Join-Path $PSScriptRoot '../research/profile/encryption-state.ps1')
 . (Join-Path $PSScriptRoot '../research/profile/graph-template.ps1')
 foreach($name in @('Get-GraphHash','Assert-GraphUsb','Copy-GraphBoot','Convert-EncryptionStatus','Read-EncryptionStatus','New-PinnedGraphFromTemplate')){
  Set-Item -Path ('function:script:'+$name) -Value (Get-Item -LiteralPath ('function:'+$name)).ScriptBlock
 }
}
Import-GuDiagnosticGraphHelpers

function Get-GuGraphRepository {
 return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}
function Get-GuGraphTextHash([string]$Text) {
 $hash=[Security.Cryptography.SHA256]::Create()
 try {return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}
 finally {$hash.Dispose()}
}
function Assert-GuGraphFile([string]$Path,[long]$Limit=67108864) {
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $Limit){throw 'Graph file is not a bounded regular file.'}
 return $item
}
function Assert-GuGraphSession([string]$SessionRoot) {
 $item=Get-Item -LiteralPath $SessionRoot -Force -ErrorAction Stop
 if(!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.FullName.StartsWith('\\')){throw 'Use an existing local session directory.'}
 return [IO.Path]::GetFullPath($item.FullName)
}
function Get-GuGraphSourceFingerprint {
 $repo=Get-GuGraphRepository
 $metadata=Join-Path $repo 'research/profile/graph-template/template.json'
 [void](Assert-GuGraphFile $metadata 1048576)
 $manifest=Get-Content -LiteralPath $metadata -Raw -ErrorAction Stop|ConvertFrom-Json
 if(@($manifest.Sources).Count -lt 4 -or @($manifest.Sources).Count -gt 2048){throw 'Invalid graph source manifest.'}
 $paths=@{}
 foreach($row in $manifest.Sources){
  if($row.Path -isnot [string] -or $row.Path -cnotmatch '^(internal-boot|deps/edk2/MdePkg/Include)/[A-Za-z0-9_./-]+$' -or
     $row.Path.Contains('..') -or $row.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or $paths.ContainsKey($row.Path)){throw 'Invalid graph source binding.'}
  $path=Join-Path $repo $row.Path
  [void](Assert-GuGraphFile $path)
  $actual=Get-GraphHash $path
  if($actual -cne $row.Sha256){throw 'Graph source changed. Preserve the session; do not stage.'}
  $paths[$row.Path]=$actual
 }
 foreach($relative in @('tools/diagnostic-graph.ps1','research/profile/prepare-graph.ps1','research/profile/encryption-state.ps1',
     'research/profile/collection-host.ps1','research/profile/graph-template.ps1',
     'research/profile/graph-template/template.json','research/profile/graph-template/graph-only.template')){
  $path=Join-Path $repo $relative
  [void](Assert-GuGraphFile $path)
  $paths[$relative]=Get-GraphHash $path
 }
 [string[]]$names=@($paths.Keys)
 [Array]::Sort($names,[StringComparer]::Ordinal)
 $rows=@($names|ForEach-Object {$_+'='+$paths[$_]})
 return Get-GuGraphTextHash ($rows -join [char]10)
}
function Get-GuGraphHostState {
 $state=[ordered]@{Elevated=$false;Architecture='unknown';SecureBootValue=$null;Encryption=$null;
   InventoryStatus='unavailable';Video=@();WindowsEsp=$null;WindowsEspReason='windows-esp-unavailable-or-ambiguous'}
 try {
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $state.Elevated=([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 }catch{}
 try {
  $cpu=@(Get-CimInstance Win32_Processor -ErrorAction Stop)
  if($cpu.Count -gt 0 -and $cpu.Count -le 64){
   if([Environment]::Is64BitOperatingSystem -and @($cpu|Where-Object {$_.Architecture -ne 9}).Count -eq 0){$state.Architecture='x64'}
   elseif(@($cpu|Where-Object {$_.Architecture -ne 12}).Count -eq 0){$state.Architecture='arm64'}
   elseif(@($cpu|Where-Object {$_.Architecture -ne 0}).Count -eq 0){$state.Architecture='x86'}
  }
 }catch{}
 try {$state.SecureBootValue=Confirm-SecureBootUEFI -ErrorAction Stop}catch{}
 $state.Encryption=Read-EncryptionStatus
 try {$state.Video=@(Get-CimInstance Win32_VideoController -ErrorAction Stop);$state.InventoryStatus='observed'}catch{}
 try {
  $parts=@(Get-Partition -ErrorAction Stop|Where-Object {$_.IsSystem})
  if($parts.Count -ne 1){throw 'Ambiguous system partition.'}
  $part=$parts[0];$disks=@(Get-Disk -Number $part.DiskNumber -ErrorAction Stop)
  if($disks.Count -eq 1 -and $disks[0].PartitionStyle -ne 'GPT'){
   $state.WindowsEspReason='windows-system-disk-not-gpt'
  }
  $guid=[guid]::Empty
  if($disks.Count -ne 1 -or !$disks[0].UniqueId -or !$disks[0].BusType -or $disks[0].BusType -eq 'USB' -or
     $disks[0].PartitionStyle -ne 'GPT' -or $disks[0].IsOffline -or
     ([string]$part.GptType).Trim('{}') -ine 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' -or
     ![guid]::TryParse([string]$part.Guid,[ref]$guid) -or $guid -eq [guid]::Empty -or
     $guid -eq [guid]'a2b4c6d8-1357-49ab-bcde-102030405060'){throw 'Unverified internal Windows ESP.'}
  $state.WindowsEsp=[pscustomobject]@{Guid=$guid;DiskNumber=$part.DiskNumber;DiskIdentity=[string]$disks[0].UniqueId;
    PartitionNumber=$part.PartitionNumber;Offset=$part.Offset;Size=$part.Size}
 }catch{}
 return $state
}
function Get-GuGraphEncryptionReport($State) {
 $out=[ordered]@{ReadStatus='unknown';ProtectionState='unknown';ConversionState='unknown';EncryptionPercentage=$null;FullyDecryptedObserved=$false}
 if($State -and $State.ReadStatus -ceq 'observed' -and $State.ProtectionState -cin @('off','on','unknown') -and
    $State.ConversionState -cin @('fully-decrypted','fully-encrypted','encrypting','decrypting','encryption-paused','decryption-paused','unknown') -and
    ($State.EncryptionPercentage -is [int] -or $State.EncryptionPercentage -is [long]) -and $State.EncryptionPercentage -ge 0 -and $State.EncryptionPercentage -le 100 -and
    $State.FullyDecryptedObserved -is [bool]){
  $out.ReadStatus='observed';$out.ProtectionState=$State.ProtectionState;$out.ConversionState=$State.ConversionState
  $out.EncryptionPercentage=[int]$State.EncryptionPercentage
  $out.FullyDecryptedObserved=($State.FullyDecryptedObserved -and $State.ProtectionState -ceq 'off' -and $State.ConversionState -ceq 'fully-decrypted' -and $State.EncryptionPercentage -eq 0)
 }
 return $out
}
function Get-GuGraphInventoryBinding($State,[string]$Salt) {
 if($State.InventoryStatus -cne 'observed' -or @($State.Video).Count -gt 64){throw 'Display inventory unavailable.'}
 $rows=@()
 foreach($adapter in @($State.Video)){
  $id=$adapter.PNPDeviceID
  if($id -isnot [string] -or !$id -or $id.Length -gt 2048 -or $id -match '[\x00-\x1f]'){throw 'Display instance identity unavailable.'}
  $rows+=([ordered]@{Instance=$id.ToUpperInvariant();DriverVersion=[string]$adapter.DriverVersion}|ConvertTo-Json -Compress)
 }
 # The random session salt prevents correlating instance fingerprints across sessions.
 # Raw instance IDs exist only in memory, never in a receipt or returned report.
 [string[]]$orderedRows=@($rows)
 [Array]::Sort($orderedRows,[StringComparer]::Ordinal)
 return Get-GuGraphTextHash ($Salt+[char]10+($orderedRows -join [char]10))
}
function ConvertTo-GuGraphCapabilities($State) {
 $reasons=@();$adapters=@();$nodes=@{}
 $elevated=$State.Elevated -is [bool] -and $State.Elevated
 if(!$elevated){$reasons+='elevation-required-for-efi'}
 $architecture=if($State.Architecture -cin @('x64','arm64','x86')){$State.Architecture}else{'unknown'}
 if($architecture -cne 'x64'){$reasons+='x64-uefi-required'}
 $firmware='unknown';$secure='unknown'
 if($State.SecureBootValue -is [bool]){$firmware='uefi';$secure=if($State.SecureBootValue){'enabled'}else{'disabled'}}
 if($secure -cne 'disabled'){$reasons+='secure-boot-enabled-or-unknown'}
 $encryption=Get-GuGraphEncryptionReport $State.Encryption
 if(!$encryption.FullyDecryptedObserved){$reasons+='system-volume-not-observed-fully-decrypted'}
 $espAvailable=($null -ne $State.WindowsEsp)
 if(!$espAvailable){
  if($State.WindowsEspReason -ceq 'windows-system-disk-not-gpt'){$reasons+='windows-system-disk-not-gpt'}
  else{$reasons+='windows-esp-unavailable-or-ambiguous'}
 }
 $inventory='observed'
 try {[void](Get-GuGraphInventoryBinding $State 'capability-observation')}catch{$inventory='unavailable';$reasons+='display-inventory-unavailable'}
 if(@($State.Video).Count -le 64){
  foreach($adapter in @($State.Video)){
   $id=[string]$adapter.PNPDeviceID;$enumerator='unknown';$pci=$null
   if($id -match '^([A-Za-z][A-Za-z0-9_-]{0,31})\\'){$enumerator=$Matches[1].ToUpperInvariant()}
   if($id -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})&SUBSYS_([0-9A-F]{8})(?:&|\\|$)'){
    $pci=[ordered]@{Vendor=$Matches[1].ToUpperInvariant();Device=$Matches[2].ToUpperInvariant();Subsystem=$Matches[3].ToUpperInvariant()}
   }
   $key=$id.ToUpperInvariant()
   if(!$nodes.ContainsKey($key)){$nodes[$key]=[guid]::NewGuid().ToString('N')}
   $adapters+=[ordered]@{Index=$adapters.Count;NodeId=$nodes[$key];Enumerator=$enumerator;Pci=$pci}
  }
 }
 return [pscustomobject]@{SchemaVersion=1;Available=($reasons.Count -eq 0);Reasons=@($reasons);Elevated=$elevated;
   Architecture=$architecture;Firmware=$firmware;SecureBoot=$secure;SystemVolumeEncryption=$encryption;
   WindowsEspAvailable=$espAvailable;InventoryStatus=$inventory;DisplayAdapters=@($adapters);
   HardwareTested=$false;WriteEligible=$false;RawIdentitiesExported=$false}
}
function Get-GuGraphCapabilities {
 $result=ConvertTo-GuGraphCapabilities (Get-GuGraphHostState)
 try {[void](Get-GuGraphSourceFingerprint)}catch{
  $result.Available=$false;$result.Reasons=@($result.Reasons)+@('packaged-graph-source-unavailable-or-changed')
 }
 return $result
}
function Get-GuGraphEspBinding($State,[string]$Salt) {
 if(!$State.WindowsEsp){throw 'Windows ESP unavailable.'}
 $esp=$State.WindowsEsp
 return Get-GuGraphTextHash ($Salt+[char]10+([ordered]@{Guid=([guid]$esp.Guid).ToString();Disk=[string]$esp.DiskIdentity;
   Partition=$esp.PartitionNumber;Offset=$esp.Offset;Size=$esp.Size}|ConvertTo-Json -Compress))
}
function Get-GuGraphMediaState([ValidatePattern('^[D-Zd-z]$')][string]$Drive) {
 $parts=@(Get-Partition -DriveLetter $Drive -ErrorAction Stop)
 if($parts.Count -ne 1){throw 'USB partition unavailable or ambiguous.'}
 $disks=@(Get-Disk -Number $parts[0].DiskNumber -ErrorAction Stop)
 $volumes=@(Get-Volume -DriveLetter $Drive -ErrorAction Stop)
 if($disks.Count -ne 1 -or $volumes.Count -ne 1){throw 'USB media unavailable or ambiguous.'}
 return [pscustomobject]@{Drive=$Drive.ToUpperInvariant();Root=($Drive.ToUpperInvariant()+':\');
   Partition=$parts[0];Disk=$disks[0];Volume=$volumes[0]}
}
function Get-GuGraphMediaBinding($Media,[string]$Salt) {
 Assert-GraphUsb $Media.Partition $Media.Disk $Media.Volume -CollectOnly
 return Get-GuGraphTextHash ($Salt+[char]10+([ordered]@{Disk=[string]$Media.Disk.UniqueId;Partition=$Media.Partition.PartitionNumber;
   Guid=[string]$Media.Partition.Guid;Offset=$Media.Partition.Offset;Size=$Media.Partition.Size}|ConvertTo-Json -Compress))
}
function Get-GuGraphUsbDriveLetters {
 $disks=@(Get-Disk -ErrorAction Stop|Where-Object {$_.BusType -eq 'USB'})
 if($disks.Count -gt 64){throw 'USB inventory exceeds diagnostic bound.'}
 $letters=@()
 foreach($disk in $disks){
  $parts=@(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop)
  if($parts.Count -gt 128){throw 'USB partition inventory exceeds diagnostic bound.'}
  foreach($part in $parts){if([string]$part.DriveLetter -match '^[D-Zd-z]$'){$letters+=[string]$part.DriveLetter}}
 }
 return @($letters|Sort-Object -Unique)
}
function Resolve-GuGraphCaptureMedia($Receipt,[string]$Drive) {
 if($Drive){
  $media=Get-GuGraphMediaState $Drive
  if((Get-GuGraphMediaBinding $media $Receipt.SessionNonce) -cne $Receipt.MediaSha256){throw 'Selected media does not match the session.'}
  return $media
 }
 try {
  $media=Get-GuGraphMediaState $Receipt.Drive
  if((Get-GuGraphMediaBinding $media $Receipt.SessionNonce) -ceq $Receipt.MediaSha256){return $media}
 }catch{}
 $matchesMedia=@()
 foreach($letter in @(Get-GuGraphUsbDriveLetters)){
  try {
   $candidate=Get-GuGraphMediaState $letter
   if((Get-GuGraphMediaBinding $candidate $Receipt.SessionNonce) -ceq $Receipt.MediaSha256){$matchesMedia+=$candidate}
  }catch{}
 }
 if($matchesMedia.Count -ne 1){throw 'Session media unavailable or ambiguous.'}
 return $matchesMedia[0]
}
function Prepare-GuDiagnosticGraph {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$SessionRoot,[Parameter(Mandatory)][ValidatePattern('^[D-Zd-z]$')][string]$Drive,
       [Parameter(Mandatory)][string]$Confirmation)
 $ErrorActionPreference='Stop'
 if($Confirmation -cne 'PREPARE'){throw 'Graph preparation cancelled. No media was staged.'}
 $session=Assert-GuGraphSession $SessionRoot
 $receiptPath=Join-Path $session 'graph-receipt.json';$attemptPath=Join-Path $session 'graph-preparation.json'
 $built=Join-Path $session 'graph-build'
 if((Test-Path -LiteralPath $receiptPath) -or (Test-Path -LiteralPath $attemptPath) -or (Test-Path -LiteralPath $built)){throw 'This session already attempted graph preparation. Preserve it; no automatic retry.'}
 $before=Get-GuGraphHostState;$capabilities=ConvertTo-GuGraphCapabilities $before
 if(!$capabilities.Available){throw ('Graph preparation unavailable: '+($capabilities.Reasons -join ', ')+'. Keep existing settings.')}
 $source=Get-GuGraphSourceFingerprint;$nonce=[guid]::NewGuid().ToString('N')
 $inventory=Get-GuGraphInventoryBinding $before $nonce;$esp=Get-GuGraphEspBinding $before $nonce
 $media=Get-GuGraphMediaState $Drive
 Assert-GraphUsb $media.Partition $media.Disk $media.Volume
 if($media.Partition.DiskNumber -eq $before.WindowsEsp.DiskNumber){throw 'Capture media cannot contain the Windows ESP.'}
 $mediaRoot=[IO.Path]::GetFullPath($media.Root).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
 if(($session+[IO.Path]::DirectorySeparatorChar).StartsWith($mediaRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Session files must be local, separate from capture media.'}
 $mediaBinding=Get-GuGraphMediaBinding $media $nonce
 $stream=[IO.File]::Open($attemptPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try {$bytes=[Text.Encoding]::UTF8.GetBytes('{"Mode":"graph-only","Attempted":true,"HardwareTested":false,"WriteEligible":false}');$stream.Write($bytes,0,$bytes.Length)}
 finally {$stream.Dispose()}
 [void](New-PinnedGraphFromTemplate (Get-GuGraphRepository) ([guid]$before.WindowsEsp.Guid) $built)
 $manifest=Get-Content -LiteralPath (Join-Path $built 'manifest.json') -Raw -ErrorAction Stop|ConvertFrom-Json
 if($manifest.Mode -cne 'graph-only-build' -or $manifest.EfiSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Unexpected graph image manifest.'}
 foreach($flag in @('FixtureOnly','HardwareTested','CanUnlock','CanDetach','ReadsGpuMmio','DumpsProm','DumpsImages','WritesFirmwareVariables')){
  if($manifest.$flag -isnot [bool] -or $manifest.$flag){throw 'Graph image scope is not observation-only.'}
 }
 $fresh=Get-GuGraphHostState;$freshCapabilities=ConvertTo-GuGraphCapabilities $fresh
 if(!$freshCapabilities.Available -or (Get-GuGraphInventoryBinding $fresh $nonce) -cne $inventory -or
    (Get-GuGraphEspBinding $fresh $nonce) -cne $esp){throw 'Host capabilities or display/ESP identity changed. Do not stage.'}
 $freshMedia=Get-GuGraphMediaState $Drive
 Assert-GraphUsb $freshMedia.Partition $freshMedia.Disk $freshMedia.Volume
 if($freshMedia.Partition.DiskNumber -eq $fresh.WindowsEsp.DiskNumber -or
    (Get-GuGraphMediaBinding $freshMedia $nonce) -cne $mediaBinding){throw 'Selected USB identity changed. Do not stage.'}
 if((Get-GuGraphSourceFingerprint) -cne $source){throw 'Source changed during preparation. Do not stage.'}
 $copy=Copy-GraphBoot $freshMedia.Root (Join-Path $built 'GRAPH-ONLY.EFI') $manifest.EfiSha256 'diagnostic-session'
 $receipt=[ordered]@{SchemaVersion=1;Mode='diagnostic-graph-only';State='prepared';SessionNonce=$nonce;Drive=$Drive.ToUpperInvariant();
   SourceSha256=$source;InventorySha256=$inventory;WindowsEspSha256=$esp;MediaSha256=$mediaBinding;EfiSha256=$manifest.EfiSha256;
   TemplateSha256=$manifest.TemplateSha256;PreviousBootSha256=$copy.PreviousBootSha256;
   HardwareTested=$false;WriteEligible=$false;RawIdentitiesExported=$false}
 $json=$receipt|ConvertTo-Json -Depth 6
 [IO.File]::WriteAllText($receiptPath,$json,(New-Object Text.UTF8Encoding($false)))
 $mediaReceipt=Join-Path $freshMedia.Root 'RTX3090-UNLOCK/graph-stage.json'
 [IO.File]::WriteAllText($mediaReceipt,$json,(New-Object Text.UTF8Encoding($false)))
 if((Get-GraphHash $receiptPath) -cne (Get-GraphHash $mediaReceipt) -or
    (Get-GraphHash (Join-Path $freshMedia.Root 'EFI/BOOT/BOOTX64.EFI')) -cne $receipt.EfiSha256){throw 'Staged receipt/image verification failed. Do not boot.'}
 return [pscustomobject]@{Status='prepared';Reason='one-attended-graph-test-prepared';ReceiptPath=$receiptPath;Drive=$Drive.ToUpperInvariant();
   EfiSha256=$receipt.EfiSha256;HardwareTested=$false;WriteEligible=$false;RawIdentitiesExported=$false}
}
function Read-GuDiagnosticGraphCapture {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$SessionRoot,[ValidatePattern('^(?:[D-Zd-z])?$')][string]$Drive)
 $ErrorActionPreference='Stop'
 $reason='invalid-session';$verified=$false
 try {
  $session=Assert-GuGraphSession $SessionRoot;$receiptPath=Join-Path $session 'graph-receipt.json'
  $reason='invalid-receipt';[void](Assert-GuGraphFile $receiptPath 65536)
  $receipt=Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop|ConvertFrom-Json
  if($receipt.SchemaVersion -ne 1 -or $receipt.Mode -cne 'diagnostic-graph-only' -or $receipt.State -cne 'prepared' -or
     $receipt.SessionNonce -cnotmatch '^[0-9a-f]{32}$' -or $receipt.Drive -cnotmatch '^[D-Z]$'){throw 'Invalid graph receipt.'}
  foreach($field in @('SourceSha256','InventorySha256','WindowsEspSha256','MediaSha256','EfiSha256')){
   if($receipt.$field -isnot [string] -or $receipt.$field -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid receipt binding.'}
  }
  foreach($field in @('HardwareTested','WriteEligible','RawIdentitiesExported')){
   if($receipt.$field -isnot [bool] -or $receipt.$field){throw 'Invalid receipt scope.'}
  }
  $reason='source-changed'
  if((Get-GuGraphSourceFingerprint) -cne $receipt.SourceSha256){throw 'Source changed.'}
  $reason='media-unavailable-changed-or-ambiguous';$media=Resolve-GuGraphCaptureMedia $receipt $Drive
  $reason='staged-image-or-receipt-changed'
  $mediaReceipt=Join-Path $media.Root 'RTX3090-UNLOCK/graph-stage.json';[void](Assert-GuGraphFile $mediaReceipt 65536)
  $image=Join-Path $media.Root 'EFI/BOOT/BOOTX64.EFI';[void](Assert-GuGraphFile $image 1048576)
  $localImage=Join-Path $session 'graph-build/GRAPH-ONLY.EFI';[void](Assert-GuGraphFile $localImage 1048576)
  $receiptHash=Get-GraphHash $receiptPath
  if((Get-GraphHash $mediaReceipt) -cne $receiptHash -or (Get-GraphHash $image) -cne $receipt.EfiSha256 -or
     (Get-GraphHash $localImage) -cne $receipt.EfiSha256){throw 'Receipt or image changed.'}
  $verified=$true;$reason='capture-files-unavailable-or-out-of-bounds'
  $capture=Join-Path $media.Root 'RTX3090-UNLOCK'
  $items=@(Get-ChildItem -LiteralPath $capture -Filter 'DIAG??.TXT' -File -ErrorAction Stop|Sort-Object Name)
  if($items.Count -eq 0){return [pscustomobject]@{Status='awaiting-capture';Reason='no-existing-diag-files';ReceiptVerified=$true;CaptureDirectory=$null;
    CurrentHostVerified=$false;CaptureOriginAttested=$false;HardwareTested=$false;WriteEligible=$false;RawIdentitiesExported=$false}}
  if($items.Count -gt 4){throw 'Too many diagnostic captures.'}
  $snapshots=@();$seen=@{}
  foreach($item in $items){
   if($item.Name -notmatch '^DIAG[0-9]{2}\.TXT$' -or $seen.ContainsKey($item.Name)){throw 'Ambiguous capture name.'}
   $seen[$item.Name]=$true;[void](Assert-GuGraphFile $item.FullName 8388608)
   $stream=[IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
   try {
    if($stream.Length -gt 8388608){throw 'Capture changed size.'}
    $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
    while($offset -lt $bytes.Length){$count=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($count -le 0){throw 'Capture read was short.'};$offset+=$count}
    if($stream.ReadByte() -ne -1){throw 'Capture changed size.'}
   }finally{$stream.Dispose()}
   $hash=[Security.Cryptography.SHA256]::Create()
   try {$sha=([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
   $snapshots+=[pscustomobject]@{Name=$item.Name.ToUpperInvariant();Bytes=$bytes;Sha256=$sha}
  }
  # A removable volume or current source can change while bounded files are read.
  # Bind the copied snapshot, without claiming the collector is the capture host.
  $verified=$false
  $reason='media-unavailable-changed-or-ambiguous'
  $currentMedia=Get-GuGraphMediaState $media.Drive
  if((Get-GuGraphMediaBinding $currentMedia $receipt.SessionNonce) -cne $receipt.MediaSha256){$verified=$false;throw 'Capture media changed during reading.'}
  $reason='source-changed'
  if((Get-GuGraphSourceFingerprint) -cne $receipt.SourceSha256){$verified=$false;throw 'Source changed during collection.'}
  $reason='staged-image-or-receipt-changed'
  if((Get-GraphHash $image) -cne $receipt.EfiSha256 -or (Get-GraphHash $mediaReceipt) -cne $receiptHash){$verified=$false;throw 'Staged image or receipt changed during reading.'}
  $verified=$true
  $destination=Join-Path $session 'graph-captures';$collectionPath=Join-Path $session 'graph-collection.json'
  $rows=@($snapshots|ForEach-Object {[ordered]@{Name=$_.Name;Bytes=$_.Bytes.Length;Sha256=$_.Sha256}})
  $reason='local-collection-changed'
  if(Test-Path -LiteralPath $collectionPath){
   [void](Assert-GuGraphFile $collectionPath 65536)
   $prior=Get-Content -LiteralPath $collectionPath -Raw -ErrorAction Stop|ConvertFrom-Json
   if($prior.ReceiptSha256 -cne $receiptHash -or
      (ConvertTo-Json -InputObject @($prior.Files) -Compress) -cne (ConvertTo-Json -InputObject $rows -Compress)){throw 'Collection inputs changed.'}
   foreach($row in $rows){$cached=Join-Path $destination $row.Name;[void](Assert-GuGraphFile $cached 8388608);if((Get-GraphHash $cached) -cne $row.Sha256){throw 'Cached capture changed.'}}
  }else{
   if(Test-Path -LiteralPath $destination){throw 'An incomplete collection already exists.'}
   New-Item -ItemType Directory -Path $destination -ErrorAction Stop|Out-Null
   foreach($snapshot in $snapshots){[IO.File]::WriteAllBytes((Join-Path $destination $snapshot.Name),$snapshot.Bytes)}
   [ordered]@{SchemaVersion=1;ReceiptSha256=$receiptHash;Files=$rows;HardwareTested=$false;WriteEligible=$false}|
    ConvertTo-Json -Depth 5|Set-Content -LiteralPath $collectionPath -Encoding utf8 -ErrorAction Stop
  }
  return [pscustomobject]@{Status='collected';Reason='existing-files-copied-for-offline-review';ReceiptVerified=$true;CaptureDirectory=$destination;
    CaptureCount=$rows.Count;CurrentHostVerified=$false;CaptureOriginAttested=$false;HardwareTested=$false;WriteEligible=$false;RawIdentitiesExported=$false}
 }catch{
  return [pscustomobject]@{Status='refused';Reason=$reason;ReceiptVerified=$verified;CaptureDirectory=$null;
    CurrentHostVerified=$false;CaptureOriginAttested=$false;HardwareTested=$false;WriteEligible=$false;RawIdentitiesExported=$false}
 }
}
