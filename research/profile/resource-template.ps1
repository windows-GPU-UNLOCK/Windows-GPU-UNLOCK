# Exact bus8/2204/147d diagnostic template. Only Windows ESP GUID data changes.
function New-GuResourceTemplate([string]$Repo,[guid]$WindowsGuid,[string]$MachineId,[string]$Output){
 $sentinel=[guid]'a2b4c6d8-1357-49ab-bcde-102030405060'
 if($MachineId -cne 'issue172' -or $WindowsGuid -eq [guid]::Empty -or $WindowsGuid -eq $sentinel){throw 'Invalid resource template case/Windows pin.'}
 $base=Join-Path $Repo 'research/profile/resource-template';$mp=Join-Path $base 'template.json';$tp=Join-Path $base 'probe-bus8.template'
 if((ProbeHash $mp) -cne 'f1e799c72a9a937eef4939e6e2de43b8f36329104ac1b076a0adb67b28669a89' -or
    (ProbeHash $tp) -cne 'f8a8b25ee0e8e02dcd0645f0a0285b7625cd3c302a6a0d5e34bd3f72e0c2e5ab'){throw 'Resource template identity changed.'}
 $m=Get-Content -LiteralPath $mp -Raw|ConvertFrom-Json
 foreach($row in $m.SourcePins){
  if($row.Path -cnotmatch '^(internal-boot|deps/edk2/MdePkg/Include|research/pci-decode)/[A-Za-z0-9_./-]+$' -or $row.Path.Contains('..') -or (ProbeHash (Join-Path $Repo $row.Path)) -cne $row.Sha256){throw 'Resource template source pin changed.'}
 }
 . (Join-Path $Repo 'research/profile/probe-manifest.ps1')
 Assert-GuGenericProbeManifest $Repo $m.Build $tp
 if($m.Build.TargetBus -ne 8 -or $m.Build.ExpectedDevice -cne '220410de' -or $m.Build.ExpectedSubsystem -cne '147d10de' -or $m.Build.ExpectedSegment -ne 0){throw 'Wrong resource template target.'}
 $bytes=[IO.File]::ReadAllBytes($tp);$old=$sentinel.ToByteArray();$pin=$WindowsGuid.ToByteArray()
 if($bytes.Length -ne 31744 -or $m.GuidOffset -ne 26624){throw 'Unexpected resource template layout.'}
 for($i=0;$i -lt 16;$i++){if($bytes[26624+$i] -ne $old[$i]){throw 'Resource GUID data mismatch.'};$bytes[26624+$i]=$pin[$i]}
 if(Test-Path -LiteralPath $Output){throw 'Output exists; preserve it.'}
 New-Item -ItemType Directory -Path $Output|Out-Null
 $image=Join-Path $Output 'BOOTX64.EFI';[IO.File]::WriteAllBytes($image,$bytes)
 $hash=ProbeHash $image;$m.Build.EfiSha256=$hash;$m.Pe.sha256=$hash
 $m.Build|Add-Member -NotePropertyName BuildPerformed -NotePropertyValue $false
 $m.Build|Add-Member -NotePropertyName Personalization -NotePropertyValue 'windows-esp-guid-data-only'
 $m.Build|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Output 'manifest.json') -Encoding utf8
 $m.Pe|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $Output 'pe-verification.json') -Encoding utf8
 Assert-GuGenericProbeManifest $Repo $m.Build $image
 return $Output
}
