# Offline production VBIOS parser test. Reads existing files; never stages or boots.
[CmdletBinding()]
param([string]$CaptureFolder,[string]$Clang='clang',[string]$VcVars,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $PSScriptRoot 'host.ps1')
function Hash-CacheFile([string]$Path){
 $h=[Security.Cryptography.SHA256]::Create();$f=[IO.File]::OpenRead($Path)
 try{([BitConverter]::ToString($h.ComputeHash($f))).Replace('-','').ToLowerInvariant()}finally{$f.Dispose();$h.Dispose()}
}
function Test-PromCache([string]$Folder,[string]$Locator){
 $prom=Join-Path $Folder 'PROM.BIN';$item=Get-Item -LiteralPath $prom -Force
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -ne 1MB){throw 'PROM.BIN must be a regular existing 1 MiB file. Keep original files unchanged.'}
 $hash=Hash-CacheFile $prom
 $process=New-Object Diagnostics.Process
 try{
  $process.StartInfo.FileName=$Locator;$process.StartInfo.Arguments='"'+[IO.Path]::GetFullPath($prom)+'"'
  $process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
  $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
  $process.StartInfo.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
  $process.Start()|Out-Null;$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  if(!$process.WaitForExit(30000)){$process.Kill();throw 'Offline parser timed out. No hardware action is authorized.'}
  $fields=$null;$state='not-found'
  if($process.ExitCode -eq 0){
   $parsed=$stdout.Result|ConvertFrom-Json
   $keys=@('image_off','image_size','dmem_size','data_off','pkc_off','ucode_id','engine_mask','sig_count','sig_versions','sig_bytes')
   if(@($parsed.PSObject.Properties).Count -ne $keys.Count -or @($parsed.PSObject.Properties|Where-Object {$_.Name -cnotin $keys}).Count){throw 'Unexpected parser result fields.'}
   $fields=[ordered]@{}
   foreach($key in $keys){
    $v=$parsed.$key
    if(($v -isnot [int] -and $v -isnot [long]) -or $v -lt 0 -or $v -gt [uint32]::MaxValue){throw 'Unexpected parser numeric result.'}
    $fields[$key]=$v
   }
   $state='located'
  }elseif($process.ExitCode -ne 1){throw 'Offline parser failed. Preserve original files; no boot or retry is requested.'}
  if((Hash-CacheFile $prom) -cne $hash){throw 'PROM changed during offline analysis.'}
  return [ordered]@{Test='production-fwsec-cache-v1';PromBytes=$item.Length;PromSha256=$hash;
    ParserSha256=(Hash-CacheFile $Locator);ParserExit=$process.ExitCode;FwsecState=$state;Fwsec=$fields;
    HardwareVerified=$false;WriteEligible=$false;ProfileGenerated=$false;
    Next='Review these local-file observations with the existing capture. No EFI boot, profile generation or unlock is authorized.'}
 }finally{$process.Dispose()}
}
if($MyInvocation.InvocationName -eq '.'){return}
Import-GuHostCompiler $VcVars
$locator=Build-GuFwsecLocate $repo $Clang
if($SelfTest){
 $temp=Join-Path ([IO.Path]::GetTempPath()) ('prom-cache-test-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $temp|Out-Null
 $prom=Join-Path $temp 'PROM.BIN';[IO.File]::WriteAllBytes($prom,(New-Object byte[] 1MB))
 $before=Hash-CacheFile $prom;$r=Test-PromCache $temp $locator
 if($r.FwsecState -cne 'not-found' -or $r.ParserExit -ne 1 -or $r.WriteEligible -or (Hash-CacheFile $prom) -cne $before){throw 'Production parser refusal regression'}
 [IO.File]::WriteAllBytes($prom,(New-Object byte[] 4));$refused=$false
 try{Test-PromCache $temp $locator}catch{$refused=$true}
 if(!$refused){throw 'Truncated PROM accepted'}
 Write-Host 'PASS: real production parser rejects synthetic empty PROM, preserves bytes and refuses truncated inputs. No GPU access.';exit
}
if(!$CaptureFolder){$CaptureFolder=Read-Host 'Existing folder containing PROM.BIN (for example G:\RTX3090-UNLOCK)'}
$result=Test-PromCache $CaptureFolder $locator
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$output=Join-Path $docs ('GPU-Unlock-Prom-Cache-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $output|Out-Null
$path=Join-Path $output 'prom-cache-report.json';$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Return only reviewed '+$path+'. Keep PROM/IMG/DIAG files local. Do not boot or stage anything.')
