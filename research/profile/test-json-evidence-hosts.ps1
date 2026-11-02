# Actual trusted integer gate under installed Windows PowerShell and PowerShell7.
# CPU-only JSON fixtures: no capture files, compiler, GPU, EFI or build permission.
[CmdletBinding()]
param([string]$PowerShell7='pwsh',[string]$OutputRoot,[switch]$Child)
$ErrorActionPreference='Stop'
if($Child){
 . (Join-Path $PSScriptRoot '../../internal-boot/unlock/local-profile.ps1')
 $checks=0
 foreach($token in @('0','1','2','-1','2147483648','9223372036854775807','null','true','false','"0"','"1"','"2"','0.0','1.0','2e0','[]','{}')){
  $parsed=ConvertFrom-Json ('{"value":'+$token+'}')
  foreach($want in @(0,1,2)){
   $accepted=Test-GuExactInteger $parsed.value $want
   if($accepted -ne ($token -ceq [string]$want)){throw 'JSON number gate regression.'}
   $checks++
  }
 }
 $v=ConvertFrom-Json '{"value":2}'
 [ordered]@{HostMajor=$PSVersionTable.PSVersion.Major;IntegerType=$v.value.GetType().Name;Checks=$checks;Passed=$true}|ConvertTo-Json -Compress
 exit 0
}
if(!$OutputRoot){$OutputRoot=[Environment]::GetFolderPath('MyDocuments')}
$parent=Get-Item -LiteralPath $OutputRoot
if(!$parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $parent.FullName.StartsWith('\\')){throw 'Use an existing regular local output folder.'}
$out=Join-Path $parent.FullName ('GPU-Unlock-Json-Gates-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $out|Out-Null
$result=[ordered]@{Test='evidence-json-hosts-v1';State='unavailable';Hosts=@();HardwareAccess=$false;WriteEligible=$false}
try{
 $legacy=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
 $commands=@(Get-Command $PowerShell7 -CommandType Application -All -ErrorAction Stop)
 if(!(Test-Path -LiteralPath $legacy -PathType Leaf) -or !$commands.Count){throw 'Missing existing host.'}
 foreach($exe in @($legacy,$commands[0].Source)){
  $p=New-Object Diagnostics.Process
  try{
   $p.StartInfo.FileName=$exe
   $p.StartInfo.Arguments='-NoProfile -File "'+$PSCommandPath+'" -Child'
   $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
   $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
   if(!$p.Start()){throw 'Host failed to start.'}
   $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
   if(!$p.WaitForExit(45000)){$p.Kill();throw 'Host timed out.'}
   if($p.ExitCode -ne 0){throw 'Host gate failed.'}
   $r=$stdout.Result|ConvertFrom-Json
   if($r.Passed -ne $true -or $r.Checks -ne 51){throw 'Unexpected gate result.'}
   $result.Hosts+= $r
  }finally{$p.Dispose()}
 }
 if($result.Hosts[0].HostMajor -ne 5 -or $result.Hosts[1].HostMajor -ne 7){throw 'Unexpected host versions.'}
 $result.State='passed'
}catch{$result.State='stopped';Write-Host 'Host test stopped; no installs, PATH/policy edits or hardware repeat. Report summary only.'}
$path=Join-Path $out 'json-gates.json';$result|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('Return only reviewed '+$path+'. Expected passed,51 checks in each installed host. No source/receipt repair or boot requested.')
if($result.State -ne 'passed'){exit 1}
