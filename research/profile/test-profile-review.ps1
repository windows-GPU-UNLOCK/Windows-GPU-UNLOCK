# Read existing local profile evidence with this pinned source's gates. Never execute
# source/scripts/binaries from ExistingRepo, rebuild, stage or access GPU/firmware.
[CmdletBinding()]
param([string]$ExistingRepo,[string]$OutputRoot,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$trustedRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $trustedRepo 'internal-boot/unlock/local-profile.ps1')
. (Join-Path $PSScriptRoot 'collection-host.ps1')
function Get-ReviewPins([string]$Text){
 $specs=[ordered]@{
  TargetBus=@('GU_TARGET_BUS','0x([0-9a-f]{1,2})U')
  Bar0Base=@('GU_BAR0_BASE','0x([0-9a-f]{1,16})ULL')
  Bar0End=@('GU_BAR0_END','0x([0-9a-f]{1,16})ULL')
  RootPortDevice=@('GU_ROOT_PORT_DEVICE','([0-9]{1,2})U')
  RootPortFunction=@('GU_ROOT_PORT_FUNCTION','([0-9])U')
 }
 $r=[ordered]@{}
 foreach($name in $specs.Keys){
  $macro=$specs[$name][0];$pattern=$specs[$name][1]
  $rows=@([regex]::Matches($Text,('(?m)^#define '+$macro+' '+$pattern+'\r?$')))
  if($rows.Count -ne 1){throw 'Missing or ambiguous numeric profile pin.'}
  $r[$name]=$rows[0].Groups[1].Value
 }
 return $r
}
function Get-DriverEnvelopeRows($Envelope){
 $rows=@()
 $lists=@([pscustomobject]@{Scope='global';Items=$Envelope.nvgop})
 foreach($chip in $Envelope.chips){
  if($chip.family -cnotmatch '^[A-Za-z0-9_-]{1,32}$'){throw 'Invalid family.'}
  $lists+= [pscustomobject]@{Scope=('family/'+$chip.family);Items=$chip.nvgop}
  if($chip.pci_nvgop){foreach($p in $chip.pci_nvgop.PSObject.Properties){
   if($p.Name -cnotmatch '^[0-9a-f]{8}$'){throw 'Invalid card pin.'}
   $lists+= [pscustomobject]@{Scope=('card/'+$chip.family+'/'+$p.Name);Items=$p.Value}
  }}
 }
 foreach($list in $lists){foreach($v in $list.Items){
  if($v.version -cnotmatch '^[0-9a-f]{1,8}$' -or $v.text_sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid driver identity.'}
  $rows+=($list.Scope+' '+$v.version+' '+$v.text_sha256)
 }}
 if($rows.Count -gt 256 -or @($rows|Select-Object -Unique).Count -ne $rows.Count){throw 'Ambiguous driver list.'}
 return $rows
}
function Compare-DriverEnvelopes($Existing,$Reviewer){
 $a=@(Get-DriverEnvelopeRows $Existing);$b=@(Get-DriverEnvelopeRows $Reviewer)
 return [ordered]@{Compared=$true;AddedRelativeToReviewer=@($a|Where-Object {$_ -cnotin $b});RemovedRelativeToReviewer=@($b|Where-Object {$_ -cnotin $a});AdmissionGranted=$false}
}
function New-ProfileReviewSummary($Hardware,$Evidence,$Pins){
 $jobs=Get-LocalExpectedJobs $Hardware.NoEdidDriver $Hardware.ConsoleAggregate
 return [ordered]@{
  Test='existing-profile-evidence-review-v1';HostEvidenceBindingsMatch=$true
  ProfileName=$Hardware.Name;TargetPci=$Hardware.TargetPci;Subsystem=$Hardware.Subsystem
  Chip=$Hardware.Chip;Memory=$Hardware.Memory;Segment=$Hardware.Segment
  NoEdidDriver=$Hardware.NoEdidDriver;ConsoleAggregate=$Hardware.ConsoleAggregate;ChildCount=$Hardware.ChildCount
  NumericHeaderPins=$Pins;HeaderSha256=$Hardware.HeaderSha256;PromSha256=$Hardware.Prom
  ProfileReportSha256=$Evidence.ProfileReportSha256;SourceTreeSha256=$Evidence.TreeSha256
  SourceInputCount=@($Evidence.Inputs).Count;ExpectedHostJobCount=$jobs.Count
  ExistingRepoCodeExecuted=$false;HostTestsRerun=$false;CaptureFilesChanged=$false
  HardwareIndependentlyVerified=$false;RecoveryVerified=$false;WriteEligible=$false
 }
}
if($SelfTest){
 $dir=Join-Path ([IO.Path]::GetTempPath()) ('profile-review-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path (Join-Path $dir 'internal-boot/unlock')|Out-Null
 $text=@(
 '#define GU_LOCAL_PROFILE_GENERATOR 1',
 '#define GU_PROFILE_NAME "LOCAL-220410de-87b31043-aaaaaaaa"',
 '#define GU_BOARD_ID 0x220410deU','#define GU_BOARD_SUBSYSTEM 0x87b31043U',
 '#define GU_CHIP_ID 0xb72000a1U','#define GU_DEVICE_MEMORY_SIZE 0x6000U',
 ('#define GU_PROM_SHA256 "'+('a'*64)+'"'),
 '#define GU_NO_EDID_DRIVER 0','#define GU_TARGET_SEGMENT 0x0U',
 '#define GU_LOCAL_CONSOLE_AGGREGATE 0','#define GU_LOCAL_CHILD_COUNT 1',
 '#define GU_TARGET_BUS 0x1U','#define GU_BAR0_BASE 0xf4000000ULL',
 '#define GU_BAR0_END 0xf4ffffffULL','#define GU_ROOT_PORT_DEVICE 1U',
 '#define GU_ROOT_PORT_FUNCTION 0U','/* PRIVATE-LOCAL-PATH */') -join ([string][char]10)
 [IO.File]::WriteAllText((Join-Path $dir 'internal-boot/unlock/profile-local.h'),$text)
 $hw=Get-LocalProfile $dir;$pins=Get-ReviewPins $text
 $e=[pscustomobject]@{ProfileReportSha256=('b'*64);TreeSha256=('c'*64);Inputs=@(1,2)}
 $r=New-ProfileReviewSummary $hw $e $pins
 if($r.ExpectedHostJobCount -ne 22 -or $r.TargetPci -cne '220410de' -or $r.WriteEligible -or $r.ExistingRepoCodeExecuted -or ($r|ConvertTo-Json -Depth 6).Contains('PRIVATE')){throw 'Profile review scope/privacy regression.'}
 $ti=$text.Replace('220410de','220310de').Replace('87b31043','161810de').Replace('0x6000U','0x5ff4U')
 [IO.File]::WriteAllText((Join-Path $dir 'internal-boot/unlock/profile-local.h'),$ti)
 $tiHardware=Get-LocalProfile $dir
 $tiSummary=New-ProfileReviewSummary $tiHardware $e (Get-ReviewPins $ti)
 if($tiSummary.TargetPci -cne '220310de' -or $tiSummary.Subsystem -cne '161810de' -or $tiSummary.Memory -cne '0x5ff4' -or $tiSummary.WriteEligible){throw '3090Ti partial-memory profile parse regression.'}
 $ga=$text.Replace('220410de','250410de').Replace('87b31043','153610de').Replace('0xb72000a1U','0xb76000a1U').Replace('0x6000U','0x3000U').Replace('0x1U','0x4U')
 [IO.File]::WriteAllText((Join-Path $dir 'internal-boot/unlock/profile-local.h'),$ga)
 $gaHardware=Get-LocalProfile $dir
 if($gaHardware.TargetPci -cne '250410de' -or $gaHardware.Memory -cne '0x3000' -or (Get-ReviewPins $ga).TargetBus -cne '4'){throw 'Issue165 profile regression.'}
 $original='{"nvgop":[],"chips":[{"family":"GA106","nvgop":[]}]}'|ConvertFrom-Json
 $changed='{"nvgop":[{"version":"60014","text_sha256":"1226b2cbb92f70db93cc6d7b00f2fbf52a90cccfc3048279bc4d166ef7cfcf5b","evidence":"PRIVATE"}],"chips":[{"family":"GA106","nvgop":[{"version":"60014","text_sha256":"1226b2cbb92f70db93cc6d7b00f2fbf52a90cccfc3048279bc4d166ef7cfcf5b"}]}]}'|ConvertFrom-Json
 $delta=Compare-DriverEnvelopes $changed $original
 if($delta.AddedRelativeToReviewer.Count -ne 2 -or $delta.RemovedRelativeToReviewer.Count -ne 0 -or $delta.AdmissionGranted -or ($delta|ConvertTo-Json).Contains('PRIVATE')){throw 'Override scope/privacy regression.'}
 $reverse=Compare-DriverEnvelopes $original $changed
 if($reverse.RemovedRelativeToReviewer.Count -ne 2 -or $reverse.AddedRelativeToReviewer.Count){throw 'Removed driver regression.'}
 $changed.nvgop[0].text_sha256='PRIVATE';$refused=$false
 try{Compare-DriverEnvelopes $changed $original|Out-Null}catch{$refused=$true}
 if(!$refused){throw 'Malformed driver digest accepted.'}
 [IO.File]::WriteAllText((Join-Path $dir 'internal-boot/unlock/profile-local.h'),$text)
 foreach($bad in @($text+[Environment]::NewLine+'#define GU_TARGET_BUS 0x2U',$text.Replace('0xf4000000ULL','PRIVATE'))){
  $refused=$false;try{Get-ReviewPins $bad|Out-Null}catch{$refused=$true};if(!$refused){throw 'Malformed/duplicate pin accepted.'}
 }
 $refused=$false;try{Assert-LocalProfileEvidence $dir|Out-Null}catch{$refused=$true}
 if(!$refused){throw 'Missing real evidence passed trusted gate.'}
 Write-Host 'PASS: 3090/3090Ti/issue165 GA106 headers, numeric pins, 22-job shape, missing evidence, driver additions/removals, malformed hashes and privacy. No supplied code or firmware executed.';exit
}
try{
 if(!$ExistingRepo){$ExistingRepo=Read-Host 'Existing tested source folder containing your local profile and receipts (do not copy new files into it)'}
 $root=Get-Item -LiteralPath $ExistingRepo
 if(!$root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $root.FullName.StartsWith('\\')){throw 'Existing source must be a regular local directory.'}
 $header=Get-Item -LiteralPath (Join-Path $root.FullName 'internal-boot/unlock/profile-local.h')
 if($header.Length -gt 64KB -or ($header.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid profile header.'}
 $hw=Get-LocalProfile $root.FullName
 $e=Assert-LocalProfileEvidence $root.FullName
 $pins=Get-ReviewPins ([IO.File]::ReadAllText($header.FullName))
 $r=New-ProfileReviewSummary $hw $e $pins
 $envelopePath=Get-Item -LiteralPath (Join-Path $root.FullName 'research/profile/proven.json')
 if($envelopePath.Length -gt 1MB -or ($envelopePath.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid existing envelope.'}
 $existingEnvelope=[IO.File]::ReadAllText($envelopePath.FullName)|ConvertFrom-Json
 $reviewerEnvelope=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'proven.json') -Raw|ConvertFrom-Json
 $r.DriverEnvelopeComparison=Compare-DriverEnvelopes $existingEnvelope $reviewerEnvelope
 $r.DriverEnvelopeComparison.ExistingFileSha256=(Get-FileHash -LiteralPath $envelopePath.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
 $r.DriverEnvelopeComparison.ReviewerFileSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'proven.json') -Algorithm SHA256).Hash.ToLowerInvariant()
 $out=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Profile-Review' $root.FullName
 $path=Join-Path $out 'profile-review.json';$r|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding utf8
 Write-Host ('Return only reviewed '+$path+'. Original source/profile/captures unchanged. No rebuild, tests, staging or boot requested.')
}catch{Write-Error 'Existing profile evidence review stopped. Keep original files unchanged; do not rerun a boot, regenerate the profile or repair source to make this pass. Report a short sanitized failure only.';exit 1}
