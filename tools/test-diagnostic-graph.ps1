# GPL-2.0-only. CPU/local temporary-directory tests; never query or stage real media.
$ErrorActionPreference='Stop'
$script:Checks=0
function Check($Condition,[string]$Message){$script:Checks++;if(!$Condition){throw $Message}}
function Refuse([scriptblock]$Action,[string]$Message){
 $failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Message
}
# Any accidental live query fails instead of touching host or USB inventory.
function Get-CimInstance {throw 'Unexpected real inventory query in mocked tests.'}
function Get-Disk {throw 'Unexpected real disk query in mocked tests.'}
function Get-Partition {throw 'Unexpected real partition query in mocked tests.'}
function Get-Volume {throw 'Unexpected real volume query in mocked tests.'}
function Confirm-SecureBootUEFI {throw 'Unexpected real firmware query in mocked tests.'}
$Drive='V';$Python='retained-python';$Offline=$true;$SessionRoot='retained-session'
. (Join-Path $PSScriptRoot 'diagnostic-graph.ps1')
Check ($Drive -ceq 'V' -and $Python -ceq 'retained-python' -and $Offline -and $SessionRoot -ceq 'retained-session') 'Helper import clobbered facade parameters.'
$script:RealCopy=(Get-Item function:Copy-GraphBoot).ScriptBlock
$script:Root=Join-Path ([IO.Path]::GetTempPath()) ('diagnostic-graph-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Root|Out-Null
function New-Case {
 $script:CaseRoot=Join-Path $script:Root ([guid]::NewGuid().ToString('N'))
 $script:Session=Join-Path $script:CaseRoot 'session';$script:Usb=Join-Path $script:CaseRoot 'mock-usb'
 New-Item -ItemType Directory -Path $script:Session,$script:Usb|Out-Null
 $script:HostQueries=0;$script:StageCalls=0;$script:SourceHash='a'*64;$script:BuildHook=$null;$script:BadManifest=$false
 $script:SourceQueries=0;$script:SourceDriftAt=0;$script:MediaQueries=0;$script:MediaDriftAt=0
 $script:HostState=[ordered]@{Elevated=$true;Architecture='x64';SecureBootValue=$false;InventoryStatus='observed';
  Encryption=[pscustomobject]@{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage=0;FullyDecryptedObserved=$true;RecoveryPassword='PRIVATE'};
  Video=@([pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_FFFF&SUBSYS_12345678\PRIVATE-ONE';DriverVersion='1.0'});
  WindowsEsp=[pscustomobject]@{Guid=[guid]'12345678-1234-4abc-9def-0123456789ab';DiskIdentity='PRIVATE-INTERNAL';DiskNumber=1;PartitionNumber=1;Offset=1048576;Size=268435456}}
 $script:Media=[pscustomobject]@{Drive='D';Root=$script:Usb;
  Partition=[pscustomobject]@{DiskNumber=7;PartitionNumber=1;Guid='PRIVATE-PARTITION';Offset=1048576;Size=67108864;IsSystem=$false;IsBoot=$false};
  Disk=[pscustomobject]@{UniqueId='PRIVATE-USB';BusType='USB';IsSystem=$false;IsBoot=$false;IsOffline=$false;IsReadOnly=$false};
  Volume=[pscustomobject]@{FileSystem='FAT32';SizeRemaining=33554432}}
 $script:MediaMap=@{D=$script:Media}
}
function Get-GuGraphHostState {$script:HostQueries++;return $script:HostState}
function Get-GuGraphSourceFingerprint {
 $script:SourceQueries++
 if($script:SourceQueries -eq $script:SourceDriftAt){$script:SourceHash='e'*64}
 return $script:SourceHash
}
function Get-GuGraphMediaState([string]$Drive){
 $script:MediaQueries++
 if($script:MediaQueries -eq $script:MediaDriftAt){$script:Media.Disk.UniqueId='CHANGED-DURING-READ'}
 if(!$script:MediaMap.ContainsKey($Drive)){throw 'No mock drive.'}
 return $script:MediaMap[$Drive]
}
function Get-GuGraphUsbDriveLetters {return @($script:MediaMap.Keys)}
function New-PinnedGraphFromTemplate([string]$Repo,[guid]$WindowsGuid,[string]$Output){
 Check ($WindowsGuid -eq [guid]'12345678-1234-4abc-9def-0123456789ab') 'Wrong Windows handoff GUID supplied.'
 New-Item -ItemType Directory -Path $Output|Out-Null
 $image=Join-Path $Output 'GRAPH-ONLY.EFI'
 [IO.File]::WriteAllText($image,'MOCK ONLY: this is not an EFI image and must never be booted.')
 [ordered]@{Mode='graph-only-build';EfiSha256=(Get-GraphHash $image);TemplateSha256=('b'*64);
   FixtureOnly=$false;HardwareTested=$false;CanUnlock=$false;CanDetach=$false;ReadsGpuMmio=$script:BadManifest;
   DumpsProm=$false;DumpsImages=$false;WritesFirmwareVariables=$false}|
  ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Output 'manifest.json') -Encoding utf8
 if($script:BuildHook){& $script:BuildHook}
 return $Output
}
function Copy-GraphBoot([string]$Root,[string]$Image,[string]$ExpectedHash,[string]$MachineId){
 $script:StageCalls++
 Check ($Root.StartsWith($script:Root,[StringComparison]::OrdinalIgnoreCase)) 'Test attempted writes outside temporary fixture.'
 return & $script:RealCopy $Root $Image $ExpectedHash $MachineId
}
function Prepare {return Prepare-GuDiagnosticGraph -SessionRoot $script:Session -Drive D -Confirmation PREPARE}
function Read-Capture {return Read-GuDiagnosticGraphCapture -SessionRoot $script:Session}
function Add-Log([string]$Name='DIAG00.TXT',[string]$Text='existing mocked graph capture'){
 [IO.File]::WriteAllText((Join-Path $script:Usb ('RTX3090-UNLOCK/'+$Name)),$Text)
}

New-Case
$script:HostState.Video=@(
 [pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_FFFF&SUBSYS_12345678\PRIVATE-ONE';DriverVersion='1.0'},
 [pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_FFFF&SUBSYS_12345678\PRIVATE-TWO';DriverVersion='1.0'},
 [pscustomobject]@{PNPDeviceID='PCI\VEN_8086&DEV_1234&SUBSYS_00000000\PRIVATE-INTEL';DriverVersion='1.0'},
 [pscustomobject]@{PNPDeviceID='PCI\VEN_1002&DEV_9999&SUBSYS_00000000\PRIVATE-AMD';DriverVersion='1.0'},
 [pscustomobject]@{PNPDeviceID='ROOT\PRIVATE-REMOTE';DriverVersion='1.0'},
 [pscustomobject]@{PNPDeviceID='UNFAMILIAR\PRIVATE-OTHER';DriverVersion='1.0'})
$caps=Get-GuGraphCapabilities
Check ($caps.Available -and $caps.DisplayAdapters.Count -eq 6) 'Mixed/unknown/virtual or duplicate-card inventory was rejected.'
Check ($caps.DisplayAdapters[0].NodeId -cne $caps.DisplayAdapters[1].NodeId) 'Identical model IDs collapsed distinct instances.'
Check (($caps|ConvertTo-Json -Depth 8) -notmatch 'PRIVATE|12345678-1234-4abc') 'Capabilities exported private identifiers.'
Check (!$caps.HardwareTested -and !$caps.WriteEligible -and !$caps.RawIdentitiesExported) 'Observation promoted to hardware admission.'
$first=Get-GuGraphInventoryBinding $script:HostState 'one-session'
$script:HostState.Video=@($script:HostState.Video[5..0])
Check ($first -ceq (Get-GuGraphInventoryBinding $script:HostState 'one-session')) 'Inventory ordering changed the binding.'
Check ($first -cne (Get-GuGraphInventoryBinding $script:HostState 'another-session')) 'Inventory binding was not session salted.'
$script:HostState.Video=@()
Check (Get-GuGraphCapabilities).Available 'No-display inventory must still permit generic graph observations.'
$script:HostState.Video=@([pscustomobject]@{PNPDeviceID='PCI\VEN_8086&DEV_1234&SUBSYS_00000000\PRIVATE';DriverVersion='1'})
Check (Get-GuGraphCapabilities).Available 'Intel-only host was rejected.'
$script:HostState.Video=@([pscustomobject]@{PNPDeviceID='PCI\VEN_1002&DEV_9999&SUBSYS_00000000\PRIVATE';DriverVersion='1'})
Check (Get-GuGraphCapabilities).Available 'AMD-only host was rejected.'
 $script:HostState.Encryption.EncryptionPercentage=[long]0
Check (Get-GuGraphCapabilities).Available 'Bounded Int64 encryption percentage was rejected.'
$script:HostState.Encryption.EncryptionPercentage=[double]0
Check (!(Get-GuGraphCapabilities).Available) 'Floating-point encryption state was accepted as a verified integer.'

$blocked=@(
 @{Change={$script:HostState.Elevated=$false};Reason='elevation-required-for-efi'},
 @{Change={$script:HostState.Architecture='arm64'};Reason='x64-uefi-required'},
 @{Change={$script:HostState.SecureBootValue=$true};Reason='secure-boot-enabled-or-unknown'},
 @{Change={$script:HostState.SecureBootValue='false'};Reason='secure-boot-enabled-or-unknown'},
 @{Change={$script:HostState.Encryption.ConversionState='fully-encrypted';$script:HostState.Encryption.EncryptionPercentage=100};Reason='system-volume-not-observed-fully-decrypted'},
 @{Change={$script:HostState.WindowsEsp=$null};Reason='windows-esp-unavailable-or-ambiguous'},
 @{Change={$script:HostState.InventoryStatus='unavailable'};Reason='display-inventory-unavailable'})
foreach($case in $blocked){
 New-Case;& $case.Change;$caps=Get-GuGraphCapabilities
 Check (!$caps.Available -and $caps.Reasons -contains $case.Reason) 'Capability refusal reason missing.'
 Refuse {Prepare} 'Blocked capability staged a graph.'
 Check ($script:StageCalls -eq 0 -and !(Test-Path -LiteralPath (Join-Path $script:Session 'graph-preparation.json'))) 'Unavailable preparation created an attempt or staged.'
}
New-Case
Refuse {Prepare-GuDiagnosticGraph -SessionRoot $script:Session -Drive D -Confirmation NO} 'Cancellation accepted.'
Check ($script:HostQueries -eq 0 -and $script:StageCalls -eq 0) 'Cancelled action queried hardware or staged.'
foreach($change in @(
 {$script:Media.Disk.IsBoot=$true},
 {$script:Media.Volume.FileSystem='NTFS'},
 {$script:Media.Volume.SizeRemaining=0},
 {$script:Media.Partition.DiskNumber=1}
)){
 New-Case;& $change
 Refuse {Prepare} 'Unsafe media passed preparation.'
 Check ($script:StageCalls -eq 0) 'Unsafe media was staged.'
}
$drifts=@(
 {$script:SourceHash='c'*64},
 {$script:HostState.Video[0].PNPDeviceID='PCI\VEN_10DE&DEV_FFFF&SUBSYS_12345678\CHANGED'},
 {$script:HostState.WindowsEsp.Guid=[guid]'22345678-1234-4abc-9def-0123456789ab'},
 {$script:HostState.SecureBootValue=$true},
 {$script:HostState.Encryption.EncryptionPercentage=1},
 {$script:Media.Disk.UniqueId='CHANGED-USB'}
)
foreach($drift in $drifts){
 New-Case;$script:BuildHook=$drift
 Refuse {Prepare} 'Preparation accepted identity/capability/source drift.'
 Check ($script:StageCalls -eq 0) 'Drift was detected after staging.'
 Check (Test-Path -LiteralPath (Join-Path $script:Session 'graph-preparation.json')) 'Failed attempt was not retained.'
 $script:BuildHook=$null
 Refuse {Prepare} 'Failed preparation was automatically retried.'
}
New-Case;$script:BadManifest=$true
Refuse {Prepare} 'A graph image with MMIO capability was accepted.'
Check ($script:StageCalls -eq 0) 'Invalid graph scope was staged.'

New-Case
$prepared=Prepare
Check ($prepared.Status -eq 'prepared' -and $script:StageCalls -eq 1) 'Successful mock preparation did not stage exactly once.'
$receiptText=Get-Content -LiteralPath $prepared.ReceiptPath -Raw
Check ($receiptText -notmatch 'PRIVATE|12345678-1234-4abc') 'Receipt exported raw disk/device/partition identity.'
Refuse {Prepare} 'A prepared session was automatically restaged.'
$queries=$script:HostQueries
$empty=Read-Capture
Check ($empty.Status -eq 'awaiting-capture' -and $empty.ReceiptVerified) 'No-log collection was misclassified.'
Check ($script:HostQueries -eq $queries -and $script:StageCalls -eq 1) 'Read-only collection queried staging prerequisites or restaged.'
Add-Log
$copied=Read-Capture
Check ($copied.Status -eq 'collected' -and $copied.ReceiptVerified -and $copied.CaptureCount -eq 1) 'Existing log was not collected.'
Check (!$copied.CurrentHostVerified -and !$copied.CaptureOriginAttested) 'Receipt agreement was promoted to capture-origin/current-host attestation.'
Check ((Get-Content -LiteralPath (Join-Path $copied.CaptureDirectory 'DIAG00.TXT') -Raw) -ceq 'existing mocked graph capture') 'Collected bytes changed.'
$again=Read-Capture
Check ($again.Status -eq 'collected' -and $again.CaptureDirectory -ceq $copied.CaptureDirectory) 'Unchanged resume did not reuse verified local capture.'
$script:MediaMap.Remove('D');$script:Media.Drive='E';$script:MediaMap.E=$script:Media
$renamed=Read-Capture
Check ($renamed.Status -eq 'collected' -and $renamed.ReceiptVerified) 'Immutable media was not found after a drive-letter change.'
$script:MediaMap.F=$script:Media
# With no original drive and two matching candidates, never choose one implicitly.
$ambiguous=Read-Capture
Check ($ambiguous.Status -eq 'refused' -and $ambiguous.Reason -eq 'media-unavailable-changed-or-ambiguous') 'Ambiguous media was selected.'
$script:MediaMap.Remove('F')
$script:SourceHash='d'*64
$changed=Read-Capture
Check ($changed.Status -eq 'refused' -and $changed.Reason -eq 'source-changed' -and !$changed.CaptureDirectory) 'Source drift associated captures with the prepared session.'
Check (Test-Path -LiteralPath (Join-Path $script:Usb 'RTX3090-UNLOCK/DIAG00.TXT')) 'Refused collection changed original evidence.'
$script:SourceHash='a'*64
[IO.File]::AppendAllText((Join-Path $script:Usb 'EFI/BOOT/BOOTX64.EFI'),'changed')
$changed=Read-Capture
Check ($changed.Status -eq 'refused' -and $changed.Reason -eq 'staged-image-or-receipt-changed') 'Changed EFI accepted for session association.'

New-Case;[void](Prepare)
foreach($i in 0..4){Add-Log ('DIAG{0:d2}.TXT' -f $i)}
$tooMany=Read-Capture
Check ($tooMany.Status -eq 'refused' -and $tooMany.Reason -eq 'capture-files-unavailable-or-out-of-bounds') 'Excess capture count accepted.'
New-Case;[void](Prepare);Add-Log
$log=Join-Path $script:Usb 'RTX3090-UNLOCK/DIAG00.TXT'
$stream=[IO.File]::OpenWrite($log);try{$stream.SetLength(8388609)}finally{$stream.Dispose()}
$tooLarge=Read-Capture
Check ($tooLarge.Status -eq 'refused' -and $tooLarge.Reason -eq 'capture-files-unavailable-or-out-of-bounds') 'Oversized capture accepted.'
New-Case;[void](Prepare);Add-Log;$script:SourceDriftAt=4
$changed=Read-Capture
Check ($changed.Status -eq 'refused' -and $changed.Reason -eq 'source-changed' -and !$changed.ReceiptVerified) 'Source drift during file reading was accepted.'
Check (!(Test-Path -LiteralPath (Join-Path $script:Session 'graph-captures'))) 'Source drift copied an associated collection.'
New-Case;[void](Prepare);Add-Log;$script:MediaDriftAt=4
$changed=Read-Capture
Check ($changed.Status -eq 'refused' -and $changed.Reason -eq 'media-unavailable-changed-or-ambiguous' -and !$changed.ReceiptVerified) 'Media drift during file reading was accepted.'
Check (!(Test-Path -LiteralPath (Join-Path $script:Session 'graph-captures'))) 'Media drift copied an associated collection.'
New-Case;[void](Prepare);Add-Log
$collected=Read-Capture
[IO.File]::WriteAllText((Join-Path $collected.CaptureDirectory 'DIAG00.TXT'),'changed cached data')
$changed=Read-Capture
Check ($changed.Status -eq 'refused' -and $changed.Reason -eq 'local-collection-changed') 'Changed local capture was reused.'
Check (!$changed.HardwareTested -and !$changed.WriteEligible -and !$changed.RawIdentitiesExported) 'Failure report promoted eligibility.'
Write-Host ('PASS: '+$script:Checks+' generic graph capability, identity, staging and collection checks; mocked services/local files only.')
