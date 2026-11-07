# Read-only Windows policy observations. Never enroll/update/delete keys or boot EFI.
[CmdletBinding()]
param([switch]$SelfTest,[string]$PublicCertificate)
$ErrorActionPreference='Stop'
function Get-CaReferences {
 $r=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'secureboot-ca-references.json') -Raw|ConvertFrom-Json
 $labels=@('microsoft-uefi-ca-2011','microsoft-uefi-ca-2023','windows-uefi-ca-2023','microsoft-option-rom-ca-2023')
 if($r.SchemaVersion -ne 1 -or @($r.Certificates).Count -ne $labels.Count){throw 'Invalid public reference table.'}
 $map=@{};$seen=@{}
 foreach($c in $r.Certificates){
  if($c.Label -cnotin $labels -or $c.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or $map.ContainsKey($c.Sha256) -or $seen.ContainsKey($c.Label)){throw 'Invalid public certificate reference.'}
  $map[$c.Sha256]=$c.Label;$seen[$c.Label]=$true
 }
 return $map
}
function Get-ByteHash([byte[]]$Bytes){
 $h=[Security.Cryptography.SHA256]::Create()
 try{([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Convert-SignatureDatabase([byte[]]$Bytes){
 if($Bytes.Length -gt 4MB){throw 'Database too large.'}
 $known=Get-CaReferences
 $counts=[ordered]@{};foreach($label in @($known.Values|Sort-Object)){$counts[$label]=0}
 $result=[ordered]@{ListCount=0;EntryCount=0;X509ListedEntries=0;UnrecognizedX509Entries=0;Sha256Entries=0;OtherTypeEntries=0;KnownPublicCertificateCounts=$counts}
 [long]$at=0
 while($at -lt $Bytes.Length){
  if($Bytes.Length-$at -lt 28 -or $result.ListCount -ge 4096){throw 'Invalid signature-list header.'}
  $guidBytes=New-Object byte[] 16;[Array]::Copy($Bytes,$at,$guidBytes,0,16);$type=([guid]::new($guidBytes)).ToString()
  [long]$size=[BitConverter]::ToUInt32($Bytes,$at+16)
  [long]$header=[BitConverter]::ToUInt32($Bytes,$at+20)
  [long]$entry=[BitConverter]::ToUInt32($Bytes,$at+24)
  if($size -lt 28 -or $size -gt $Bytes.Length-$at -or $header -gt $size-28 -or $entry -lt 16 -or
     ($size-28-$header)%$entry -ne 0){throw 'Invalid signature-list bounds.'}
  [long]$number=($size-28-$header)/$entry
  if($number -gt 100000-$result.EntryCount){throw 'Too many signature entries.'}
  $result.ListCount++;$result.EntryCount+=$number
  if($type -ceq 'a5c059a1-94e4-4aa7-87b5-ab155c2bf072'){
   if($entry -le 16 -or $entry -gt 1MB){throw 'Invalid listed X509 entry size.'}
   for([long]$i=0;$i -lt $number;$i++){
    $data=New-Object byte[] ($entry-16);[Array]::Copy($Bytes,$at+28+$header+$i*$entry+16,$data,0,$data.Length)
    $result.X509ListedEntries++;$digest=Get-ByteHash $data
    if($known.ContainsKey($digest)){$counts[$known[$digest]]++}else{$result.UnrecognizedX509Entries++}
   }
  }elseif($type -ceq 'c1c41626-504c-4092-aca9-41f936934328'){
   if($entry -ne 48){throw 'Invalid SHA256 entry size.'};$result.Sha256Entries+=$number
  }else{$result.OtherTypeEntries+=$number}
  $at+=$size
 }
 return $result
}
function Read-PublicDatabase([ValidateSet('db','dbx')][string]$Name){
 try{
  $v=Get-SecureBootUEFI -Name $Name -ErrorAction Stop
  if($v.Bytes -isnot [byte[]]){throw 'Unexpected variable representation.'}
 }catch{return [ordered]@{Name=$Name;ReadStatus='unavailable';ErrorCategory=([string]$_.CategoryInfo.Category);Summary=$null}}
 try{return [ordered]@{Name=$Name;ReadStatus='parsed';ErrorCategory=$null;Summary=(Convert-SignatureDatabase $v.Bytes)}}
 catch{return [ordered]@{Name=$Name;ReadStatus='not-parsed';ErrorCategory='InvalidData';Summary=$null}}
}
function New-TestSignatureList([guid]$Type,[byte[]]$Payload){
 $b=New-Object byte[] (28+16+$Payload.Length);[Array]::Copy($Type.ToByteArray(),0,$b,0,16)
 [Array]::Copy([BitConverter]::GetBytes([uint32]$b.Length),0,$b,16,4)
 [Array]::Copy([BitConverter]::GetBytes([uint32](16+$Payload.Length)),0,$b,24,4)
 [Array]::Copy($Payload,0,$b,44,$Payload.Length);return ,$b
}
if($SelfTest){
 $private=[Text.Encoding]::UTF8.GetBytes('PRIVATE-OWNER-PAYLOAD')
 $x=New-TestSignatureList ([guid]'a5c059a1-94e4-4aa7-87b5-ab155c2bf072') $private
 $h=New-TestSignatureList ([guid]'c1c41626-504c-4092-aca9-41f936934328') (New-Object byte[] 32)
 $r=Convert-SignatureDatabase ([byte[]]($x+$h));$json=$r|ConvertTo-Json -Depth 6
 if($r.EntryCount -ne 2 -or $r.UnrecognizedX509Entries -ne 1 -or $r.Sha256Entries -ne 1 -or $json.Contains('PRIVATE') -or $json.Contains((Get-ByteHash $private))){throw 'Count/privacy regression.'}
 foreach($bad in @([byte[]]@(1,2,3),([byte[]]$x.Clone()))){
  if($bad.Length -gt 3){[Array]::Clear($bad,16,4)}
  $rejected=$false;try{Convert-SignatureDatabase $bad|Out-Null}catch{$rejected=$true};if(!$rejected){throw 'Malformed list accepted.'}
 }
 $bad=[byte[]]$x.Clone();[Array]::Copy([BitConverter]::GetBytes([uint32]1000000),0,$bad,20,4)
 $rejected=$false;try{Convert-SignatureDatabase $bad|Out-Null}catch{$rejected=$true};if(!$rejected){throw 'Oversized header accepted.'}
 $script:MockDatabase=[byte[]]($x+$h)
 function Get-SecureBootUEFI {param($Name,$ErrorAction);[pscustomobject]@{Bytes=$script:MockDatabase}}
 $r=Read-PublicDatabase 'db'
 if($r.ReadStatus -cne 'parsed' -or $r.Summary.EntryCount -ne 2){throw 'Mocked read failed.'}
 function Get-SecureBootUEFI {param($Name,$ErrorAction);throw 'PRIVATE-EXCEPTION-PATH'}
 $r=Read-PublicDatabase 'dbx'
 if($r.ReadStatus -cne 'unavailable' -or ($r|ConvertTo-Json -Depth 6).Contains('PRIVATE')){throw 'Read failure exposed data or became success.'}
 if($PublicCertificate){
  $cert=[IO.File]::ReadAllBytes($PublicCertificate);$r=Convert-SignatureDatabase (New-TestSignatureList ([guid]'a5c059a1-94e4-4aa7-87b5-ab155c2bf072') $cert)
  if(($r.KnownPublicCertificateCounts.Values|Measure-Object -Sum).Sum -ne 1){throw 'Public certificate recognition failed.'}
 }
 Write-Host 'PASS: bounded signature-list counts, unknown-data redaction, malformed refusal and optional public reference recognition. No firmware queries.';exit
}
$state='unknown';try{$s=Confirm-SecureBootUEFI -ErrorAction Stop;if($s -is [bool]){$state=if($s){'enabled'}else{'disabled'}}}catch{}
$report=[ordered]@{Test='secureboot-public-database-v1';SecureBootState=$state;Databases=@((Read-PublicDatabase 'db'),(Read-PublicDatabase 'dbx'));
 RawVariablesExported=$false;OwnerIdentifiersExported=$false;SignatureValidated=$false;FirmwareTrustEstablished=$false;HardwareTested=$false;WriteEligible=$false;
 Limits='Counts and exact public-CA fingerprints only. Unknown entries stay unknown. No certificate subjects, owner GUIDs, raw hashes/keys or raw databases are exported. No image revocation, SBAT, signature or firmware execution decision is made.';
 Next='Keep Secure Boot/keys/settings unchanged. No EFI preparation, staging or boot is authorized.'}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$out=Join-Path $docs ('GPU-Unlock-SecureBoot-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $out|Out-Null
$path=Join-Path $out 'secureboot-databases.json';$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Return only reviewed '+$path+'. Keep Secure Boot enabled; no key/settings/staging/boot changes.')
