# GPL-2.0-only. Host discovery and input validation; no staging in these helpers.
function Get-CaptureUsbChoices {
 $choices=@()
 foreach($disk in @(Get-Disk | Where-Object {$_.BusType -eq 'USB'})) {
  foreach($part in @(Get-Partition -DiskNumber $disk.Number)) {
   if(!$part.DriveLetter){continue}
   $vol=Get-Volume -DriveLetter $part.DriveLetter
   $reason=if($disk.IsBoot -or $disk.IsSystem -or $part.IsSystem -or $part.IsBoot){'Windows boot/system disk'}
    elseif($disk.IsOffline -or $disk.IsReadOnly){'disk is offline or read-only'}
    elseif([string]$part.DriveLetter -notmatch '^[D-Zd-z]$'){'drive letter is reserved by the existing staging tool'}
    elseif(!$disk.UniqueId){'disk identity is unavailable; ask a maintainer'}
    elseif($vol.FileSystem -ne 'FAT32'){'not FAT32; this tool will not format it'}else{''}
   $choices+=[pscustomobject]@{Drive=[string]$part.DriveLetter;DiskNumber=$disk.Number;PartitionNumber=$part.PartitionNumber
    Label=[string]$vol.FileSystemLabel;Model=[string]$disk.FriendlyName;SizeGiB=[math]::Round($vol.Size/1GB,1)
    FileSystem=[string]$vol.FileSystem;Eligible=(!$reason);Reason=$reason
    Identity=[string]$disk.UniqueId;Offset=$part.Offset;SizeBytes=$part.Size}
  }
 }
 return $choices
}

function Select-CaptureUsb($Choices,[string]$Answer) {
 $n=0
 if(![int]::TryParse($Answer,[ref]$n) -or $n -lt 1 -or $n -gt @($Choices).Count){throw 'No USB selected. Setup cancelled without staging.'}
 $choice=@($Choices)[$n-1]
 if(!$choice.Eligible){throw ('That USB cannot be used: '+$choice.Reason)}
 return $choice
}

function Assert-CaptureUsbUnchanged($Selected) {
 $current=@(Get-CaptureUsbChoices | Where-Object {$_.Drive -eq $Selected.Drive})
 if($current.Count -ne 1 -or !$current[0].Eligible -or $current[0].DiskNumber -ne $Selected.DiskNumber -or
    $current[0].PartitionNumber -ne $Selected.PartitionNumber -or $current[0].Model -ne $Selected.Model -or
    $current[0].Label -ne $Selected.Label -or $current[0].Identity -ne $Selected.Identity -or
    $current[0].Offset -ne $Selected.Offset -or $current[0].SizeBytes -ne $Selected.SizeBytes){
  throw 'The USB selection changed. Setup stopped before staging; start again and check the selected drive.'
 }
}
