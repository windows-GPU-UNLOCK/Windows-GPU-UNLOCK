# Fixed non-boot test data. This module only reads bytes; it never executes EFI.
function Assert-GraphFixture([byte[]]$Bytes,$Manifest,[string]$Repo){
 $expected='487f558711204faeb7fd9af599b1fcd31b98580529f6aee970f3220c91f76ab0'
 $h=[Security.Cryptography.SHA256]::Create()
 try{$actual=([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
 if($actual -cne $expected -or $Manifest.EfiSha256 -cne $expected -or
    $Manifest.Mode -cne 'graph-only-build' -or $Manifest.FixtureOnly -isnot [bool] -or !$Manifest.FixtureOnly){throw 'Packaged fixture identity mismatch. Do not execute or boot it.'}
 foreach($flag in @('HardwareTested','CanUnlock','CanDetach','ReadsGpuMmio','DumpsProm','DumpsImages','WritesFirmwareVariables')){
  if($Manifest.$flag -isnot [bool] -or $Manifest.$flag -ne $false){throw 'Unexpected packaged fixture scope.'}
 }
 $known=@('internal-boot/boot/handoff.c','internal-boot/boot/diagnostic.c','internal-boot/efi_runtime.c','internal-boot/unlock/sha256.c','internal-boot/boot/diagnostic.h','internal-boot/boot/media.h','internal-boot/boot/flow.h','internal-boot/unlock/machine-profile.h','internal-boot/unlock/gpu-family.h','internal-boot/unlock/firmware-profile.h')
 if(@($Manifest.Sources).Count -ne $known.Count){throw 'Packaged fixture source list mismatch.'}
 $seen=@{}
 foreach($row in $Manifest.Sources){
  if($row.Path -cnotin $known -or $seen.ContainsKey($row.Path) -or $row.Sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid packaged source record.'}
  $seen[$row.Path]=$true
  if((Get-GraphHash (Join-Path $Repo $row.Path)) -cne $row.Sha256){throw 'Packaged fixture recorded sources changed. Stop; do not substitute an image.'}
 }
 return $actual
}
