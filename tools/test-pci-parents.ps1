# Read Windows PnP parent associations; no PCI config, MMIO or device changes.
[CmdletBinding()]
param([Alias('SelfTest')][switch]$PciParentsSelfTest,[Alias('Case')][ValidateSet('108','17','167')][string]$PciParentsCase='108')
if($MyInvocation.InvocationName -ne '.'){$ErrorActionPreference='Stop'}

function Get-PciParentTargets($Devices,[ValidateSet('108','17','167')][string]$CaseId){
 if($Devices.Count -gt 16){throw 'Too many display adapters.'}
 $pins=if($CaseId -ceq '17'){@('10DE/2204/40411458','10DE/1E04/12FA10DE')}
       elseif($CaseId -ceq '167'){@('10DE/2504/263019DA','8086/9BC8/B44019DA')}
       else{@('10DE/2208/40811458')}
 $selected=@()
 foreach($pin in $pins){
  $parts=$pin.Split('/')
  $pattern='^PCI\\VEN_'+$parts[0]+'&DEV_'+$parts[1]+'&SUBSYS_'+$parts[2]+'(?:&|\\)'
  $found=@($Devices|Where-Object {$_.InstanceId -match $pattern})
  if($found.Count -ne 1){throw 'Target missing or not unique.'}
  $selected+=$found[0]
 }
 return $selected
}

function New-PciParentContext {
 # The dictionary stays in memory. Random IDs cannot be correlated across runs.
 return [pscustomobject]@{
  RunId=[guid]::NewGuid().ToString('N')
  NodeIds=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
 }
}
function Get-PciParentNodeId($Context,[string]$Identity){
 if(!$Context.NodeIds.ContainsKey($Identity)){
  $Context.NodeIds.Add($Identity,[guid]::NewGuid().ToString('N'))
 }
 return $Context.NodeIds[$Identity]
}
function Get-PciParentNodeKind([string]$Identity){
 if($Identity -ieq 'HTREE\ROOT\0'){return 'device-tree-root'}
 if($Identity -match '^(PCI|ACPI|ROOT|SWD|USB)\\'){return $Matches[1].ToLowerInvariant()}
 return 'other'
}
function Get-PciParentChain([string]$Start,[scriptblock]$ReadParent,$Context){
 if($null -eq $Context){$Context=New-PciParentContext}
 $rows=@();$seen=@{};$current=$Start
 $state='partial';$termination='depth-limit';$stopNode=$null;$cycleTo=$null
 for($hop=0;$hop -lt 16;$hop++){
  if(!$current -or $current.Length -gt 2048 -or $current -match '[\x00-\x1f\x7f]' -or !$current.Trim()){
   $state=if($rows.Count){'partial'}else{'error'}
   $termination='invalid-instance-id';break
  }
  $nodeId=Get-PciParentNodeId $Context $current
  if($seen.ContainsKey($current)){$termination='cycle';$cycleTo=$nodeId;break}
  $seen[$current]=$true;$stopNode=$nodeId
  $pci=$null
  if($current -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})(?:&SUBSYS_([0-9A-F]{8}))?(?:&|\\|$)'){
   $pci=[ordered]@{Vendor=$Matches[1].ToUpperInvariant();Device=$Matches[2].ToUpperInvariant();Subsystem=$(if($Matches[3]){$Matches[3].ToUpperInvariant()}else{$null})}
  }
  $kind=Get-PciParentNodeKind $current
  $row=[pscustomobject]@{Hop=$hop;NodeId=$nodeId;Kind=$kind;Pci=$pci;ParentNodeId=$null;ParentRead='not-read'}
  $rows+=$row
  # ROOT-enumerated devices are not the device-tree root. Only this exact
  # documented Windows root needs no parent-property query.
  if($kind -ceq 'device-tree-root'){
   $row.ParentRead='not-required-root';$state='complete';$termination='device-tree-root';break
  }
  try{$parent=@(& $ReadParent $current)}catch{
   $row.ParentRead='failed';$termination='parent-read-failed';break
  }
  if($parent.Count -ne 1 -or $parent[0] -isnot [string] -or $parent[0].Length -gt 2048 -or
     $parent[0] -match '[\x00-\x1f\x7f]' -or ($parent[0].Length -gt 0 -and !$parent[0].Trim())){
   $row.ParentRead='invalid';$termination='invalid-parent-response';break
  }
  if($parent[0] -ceq ''){
   $row.ParentRead='empty';$state='complete';$termination='parent-reported-empty';break
  }
  $row.ParentRead='observed'
  $row.ParentNodeId=Get-PciParentNodeId $Context $parent[0]
  if($seen.ContainsKey($parent[0])){$termination='cycle';$cycleTo=$row.ParentNodeId;break}
  $current=$parent[0]
 }
 return [ordered]@{
  State=$state;Termination=$termination;StopNodeId=$stopNode;CycleToNodeId=$cycleTo;Nodes=$rows
 }
}

function New-PciParentReport([string]$CaseId,$Context){
 return [ordered]@{
  Test='windows-pci-parent-v3';RunId=$Context.RunId;Case=$CaseId;ReadStatus='error'
  FailureReason=$null;ExpectedChains=$(if($CaseId -ceq '108'){1}else{2});CompletedChains=0;Targets=@()
  RawIdentitiesExported=$false;ExternalConnectorVerified=$false;PrebootTopologyVerified=$false
  PhysicalDisplayRouteVerified=$false;VirtualAdapterAdmissionGranted=$false
  HardwareUnlockTested=$false;WriteEligible=$false
 }
}
function Get-PciParentReport($Devices,[string]$CaseId,[scriptblock]$ReadParent){
 $context=New-PciParentContext
 $report=New-PciParentReport $CaseId $context
 try{$selected=@(Get-PciParentTargets $Devices $CaseId)}catch{
  $report.FailureReason='target-selection-failed';return $report
 }
 foreach($device in $selected){
  $report.Targets+=Get-PciParentChain $device.InstanceId $ReadParent $context
 }
 $report.CompletedChains=@($report.Targets|Where-Object {$_.State -ceq 'complete'}).Count
 if($report.CompletedChains -eq $report.ExpectedChains){$report.ReadStatus='complete'}
 elseif(@($report.Targets|Where-Object {$_.Nodes.Count -gt 0}).Count){$report.ReadStatus='partial'}
 else{$report.ReadStatus='error'}
 return $report
}

function Get-DisplayParentReport($Devices,[scriptblock]$ReadParent,$Context){
 # Generic observation only: keep every row, including duplicate card models.
 # The exact-case selectors above remain the admission-independent CLI contract.
 if($null -eq $Context){$Context=New-PciParentContext}
 $all=@($Devices);$limit=64
 $report=[ordered]@{
  Test='windows-display-parent-v1';RunId=$Context.RunId;ReadStatus='partial'
  ExpectedChains=$all.Count;CompletedChains=0;Targets=@();Truncated=($all.Count -gt $limit)
  DuplicateIdentityCount=0;RawIdentitiesExported=$false;PrebootTopologyVerified=$false
  PhysicalDisplayRouteVerified=$false;VirtualAdapterAdmissionGranted=$false
  HardwareUnlockTested=$false;WriteEligible=$false
 }
 $seen=@{};$index=0
 for($index=0;$index -lt [Math]::Min($all.Count,$limit);$index++){
  $device=$all[$index]
  $identity=$null
  if($device.InstanceId -is [string]){$identity=$device.InstanceId}
  elseif($device.PNPDeviceID -is [string]){$identity=$device.PNPDeviceID}
  $valid=$identity -and $identity.Length -le 2048 -and $identity.Trim() -and $identity -notmatch '[\x00-\x1f\x7f]'
  $node=if($valid){Get-PciParentNodeId $Context $identity}else{[guid]::NewGuid().ToString('N')}
  $duplicate=$null
  if($valid){
   if($seen.ContainsKey($identity)){$duplicate=$seen[$identity];$report.DuplicateIdentityCount++}
   else{$seen[$identity]=$index}
  }
  $chain=Get-PciParentChain $identity $ReadParent $Context
  $chain['AdapterIndex']=$index;$chain['AdapterNodeId']=$node;$chain['DuplicateOfIndex']=$duplicate
  $report.Targets+=,$chain
 }
 $report.CompletedChains=@($report.Targets | Where-Object {$_.State -ceq 'complete'}).Count
 if($all.Count -gt 0 -and !$report.Truncated -and $report.CompletedChains -eq $all.Count){$report.ReadStatus='complete'}
 return $report
}

# Imports expose only functions, never PnP queries, self-tests or output folders.
if($MyInvocation.InvocationName -eq '.'){return}
if($PciParentsSelfTest){
 $checks=0
 function Assert-ParentTest([bool]$Condition,[string]$Name){
  if(!$Condition){throw ('Parent-chain regression: '+$Name)}
  $script:checks++
 }
 $target='PCI\VEN_10DE&DEV_2208&SUBSYS_40811458\PRIVATE'
 $bridge='PCI\VEN_1022&DEV_14EE\PRIVATE'
 $r=Get-PciParentChain $target {param($id) if($id -eq $target){$bridge}else{''}}
 Assert-ParentTest ($r.State -ceq 'complete' -and $r.Termination -ceq 'parent-reported-empty') 'explicit empty parent completion'
 Assert-ParentTest ($r.Nodes.Count -eq 2 -and $r.Nodes[0].Pci.Subsystem -ceq '40811458' -and $r.Nodes[1].Pci.Vendor -ceq '1022') 'PCI fields retained'
 Assert-ParentTest ($r.Nodes[0].ParentNodeId -ceq $r.Nodes[1].NodeId) 'parent edge identity'
 Assert-ParentTest (($r|ConvertTo-Json -Depth 10) -notmatch 'PRIVATE|PCI\\') 'raw identity privacy'
 $r=Get-PciParentChain $target {param($id) $id.ToLowerInvariant()}
 Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'cycle' -and $r.CycleToNodeId -ceq $r.Nodes[0].NodeId) 'case insensitive cycle'
 $r=Get-PciParentChain $target {throw 'PRIVATE failed read'}
 Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'parent-read-failed' -and $r.Nodes.Count -eq 1) 'failed parent preserves target'
 Assert-ParentTest (($r|ConvertTo-Json -Depth 10) -notmatch 'PRIVATE|failed read') 'error text privacy'
 $r=Get-PciParentChain $target {'A';'B'}
 Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'invalid-parent-response') 'ambiguous parent'
 foreach($badParent in @($null,42,('X'*2049),'   ',("bad"+[char]0+'id'))){
  $r=Get-PciParentChain $target {$badParent}
  Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'invalid-parent-response') 'invalid parent response'
 }
 $script:sequence=0
 $r=Get-PciParentChain $target {$script:sequence++;'ACPI\PRIVATE\'+$script:sequence}
 Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'depth-limit' -and $r.Nodes.Count -eq 16 -and $script:sequence -eq 16) 'depth bound'
 $r=Get-PciParentChain ('X'*2049) {throw 'must not read'}
 Assert-ParentTest ($r.State -ceq 'error' -and $r.Termination -ceq 'invalid-instance-id' -and $r.Nodes.Count -eq 0) 'invalid start'
 $script:reads=0
 $r=Get-PciParentChain $target {
  param($id)
  $script:reads++
  if($id -eq $target){'ACPI\PRIVATE\1'}
  elseif($id -eq 'ACPI\PRIVATE\1'){'ROOT\PRIVATE\0000'}
  elseif($id -eq 'ROOT\PRIVATE\0000'){'HTREE\ROOT\0'}
  else{throw 'must not query the tree root'}
 }
 Assert-ParentTest ($r.State -ceq 'complete' -and $r.Termination -ceq 'device-tree-root' -and $r.Nodes.Count -eq 4 -and $script:reads -eq 3) 'non PCI tail reaches exact root'
 Assert-ParentTest ($r.Nodes[1].Kind -ceq 'acpi' -and $r.Nodes[2].Kind -ceq 'root' -and $r.Nodes[3].Kind -ceq 'device-tree-root') 'non PCI classification'
 Assert-ParentTest ($r.Nodes[3].ParentRead -ceq 'not-required-root') 'no root property query'
 $boundaryNodes=@($target)+@(1..14|ForEach-Object {'ACPI\PRIVATE\'+$_})+@('HTREE\ROOT\0')
 $parents=@{}
 for($i=0;$i -lt $boundaryNodes.Count-1;$i++){$parents[$boundaryNodes[$i]]=$boundaryNodes[$i+1]}
 $r=Get-PciParentChain $target {param($id) if(!$parents.ContainsKey($id)){throw 'must not read root'};$parents[$id]}
 Assert-ParentTest ($r.State -ceq 'complete' -and $r.Nodes.Count -eq 16) 'root at final allowed node'
 $parents[$boundaryNodes[14]]='ACPI\PRIVATE\15'
 $parents['ACPI\PRIVATE\15']='HTREE\ROOT\0'
 $r=Get-PciParentChain $target {param($id) if(!$parents.ContainsKey($id)){throw 'must not read root'};$parents[$id]}
 Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'depth-limit' -and $r.Nodes.Count -eq 16) 'root beyond bound remains partial'
 $r=Get-PciParentChain 'ROOT\PRIVATE\0000' {throw 'PRIVATE unavailable'}
 Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'parent-read-failed') 'ROOT enumerator is not tree root'
 $r=Get-PciParentChain 'HTREE\ROOT\1' {throw 'PRIVATE unavailable'}
 Assert-ParentTest ($r.State -ceq 'partial' -and $r.Termination -ceq 'parent-read-failed') 'nonexact HTREE root is not accepted'

 $multi=@('PCI\VEN_10DE&DEV_2204&SUBSYS_40411458\PRIVATE-A','PCI\VEN_10DE&DEV_1E04&SUBSYS_12FA10DE\PRIVATE-B','PCI\VEN_10DE&DEV_2C02&SUBSYS_41781458\PRIVATE-C')|ForEach-Object {[pscustomobject]@{InstanceId=$_}}
 $selected=@(Get-PciParentTargets $multi '17')
 Assert-ParentTest ($selected.Count -eq 2 -and @($selected|Where-Object {$_.InstanceId -match '2C02'}).Count -eq 0) 'exact targets exclude 5080'
 $bridgeA='PCI\VEN_1022&DEV_43F5\PRIVATE-BRIDGE-A'
 $bridgeB='PCI\VEN_1022&DEV_43F5\PRIVATE-BRIDGE-B'
 $shared='PCI\VEN_1022&DEV_14DB\PRIVATE-SHARED'
 $script:reads=0
 $report=Get-PciParentReport $multi '17' {
  param($id)
  $script:reads++
  if($id -eq $multi[0].InstanceId){$bridgeA}
  elseif($id -eq $multi[1].InstanceId){$bridgeB}
  elseif($id -eq $bridgeA){$shared}
  elseif($id -eq $bridgeB){$shared.ToLowerInvariant()}
  elseif($id -ieq $shared){'HTREE\ROOT\0'}
  else{throw 'Non-target traversed'}
 }
 Assert-ParentTest ($report.ReadStatus -ceq 'complete' -and $report.CompletedChains -eq 2 -and $script:reads -eq 6) 'complete aggregate and exact traversal'
 Assert-ParentTest ($report.Targets[0].Nodes[1].Pci.Device -ceq $report.Targets[1].Nodes[1].Pci.Device -and $report.Targets[0].Nodes[1].NodeId -cne $report.Targets[1].Nodes[1].NodeId) 'same model is not same instance'
 Assert-ParentTest ($report.Targets[0].Nodes[2].NodeId -ceq $report.Targets[1].Nodes[2].NodeId) 'actual shared ancestor identity'
 Assert-ParentTest (($report|ConvertTo-Json -Depth 10) -notmatch 'PRIVATE|InstanceId|PCI\\|HTREE') 'report contains no raw identities'
 $other=Get-PciParentReport $multi '17' {''}
 Assert-ParentTest ($report.RunId -cne $other.RunId -and $report.Targets[0].Nodes[0].NodeId -cne $other.Targets[0].Nodes[0].NodeId) 'per run identity isolation'
 $partial=Get-PciParentReport $multi '17' {throw 'PRIVATE'}
 Assert-ParentTest ($partial.ReadStatus -ceq 'partial' -and $partial.CompletedChains -eq 0 -and $partial.Targets.Count -eq 2) 'no completed chain is not complete'
 $partial=Get-PciParentReport $multi '17' {param($id) if($id -eq $multi[0].InstanceId){''}else{throw 'PRIVATE'}}
 Assert-ParentTest ($partial.ReadStatus -ceq 'partial' -and $partial.CompletedChains -eq 1) 'mixed complete and failed chains'
 foreach($bad in @(@($multi[0]),@($multi[0],$multi[0],$multi[1]))){
  $refused=Get-PciParentReport $bad '17' {throw 'selection must stop before reading'}
  Assert-ParentTest ($refused.ReadStatus -ceq 'error' -and $refused.FailureReason -ceq 'target-selection-failed' -and $refused.Targets.Count -eq 0) 'missing or duplicate target refuses'
 }
 $zbox=@('PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA\PRIVATE-A','PCI\VEN_8086&DEV_9BC8&SUBSYS_B44019DA\PRIVATE-B','ROOT\RDP\PRIVATE')|ForEach-Object {[pscustomobject]@{InstanceId=$_}}
 $zselected=@(Get-PciParentTargets $zbox '167')
 Assert-ParentTest ($zselected.Count -eq 2 -and $zselected[0].InstanceId -match '2504' -and $zselected[1].InstanceId -match '9BC8' -and @($zselected|Where-Object {$_.InstanceId -match '^ROOT'}).Count -eq 0) 'ZBOX selects physical PCI roles'
 $refused=Get-PciParentReport @($zbox[0],$zbox[2]) '167' {throw 'must not read RDP'}
 Assert-ParentTest ($refused.ReadStatus -ceq 'error' -and $refused.Targets.Count -eq 0) 'RDP cannot replace Intel'
 foreach($flag in @('RawIdentitiesExported','ExternalConnectorVerified','PrebootTopologyVerified','PhysicalDisplayRouteVerified','VirtualAdapterAdmissionGranted','HardwareUnlockTested','WriteEligible')){
  Assert-ParentTest ($report[$flag] -ceq $false -and $partial[$flag] -ceq $false -and $refused[$flag] -ceq $false) ('unchanged false flag '+$flag)
 }
 Write-Host ('PASS: '+$checks+' CPU-only PCI parent assertions; no PnP query, hardware access or report files.')
 exit 0
}

$devices=$null
try{$devices=@(Get-PnpDevice -PresentOnly -Class Display -ErrorAction Stop)}catch{}
if($null -eq $devices){
 $report=New-PciParentReport $PciParentsCase (New-PciParentContext)
 $report.FailureReason='display-inventory-unavailable'
}else{
 $report=Get-PciParentReport $devices $PciParentsCase {
  param($id)
  $p=Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_Parent -ErrorAction Stop
  if($p.Type -cne 'String' -or $p.Data -isnot [string]){throw 'Unknown parent property.'}
  $p.Data
 }
}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents unavailable.'}
$folder=Join-Path $docs ('GPU-Unlock-Pci-Parents-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $folder|Out-Null
$path=Join-Path $folder 'pci-parents.json'
$report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Read status: '+$report.ReadStatus+'; complete chains: '+$report.CompletedChains+'/'+$report.ExpectedChains)
Write-Host ('Return only reviewed '+$path+'. Partial/error results are useful. No settings change, EFI or reboot.')
