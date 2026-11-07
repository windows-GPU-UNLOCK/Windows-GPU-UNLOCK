# Actual CLI orchestration with a synthetic baseline helper; no Windows/firmware queries.
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('inspection-cli-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$entry=Join-Path $root 'prepare-policy-inspection.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'prepare-policy-inspection.ps1') -Destination $entry
@'
param($Mode,$Machine,$Baseline,[switch]$PassThru)
$out=Join-Path $PSScriptRoot ('result-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out|Out-Null
if($Mode -eq 'Record'){
 '{"fixture":true}'|Set-Content (Join-Path $out 'baseline.json') -Encoding utf8
 Set-Content (Join-Path $PSScriptRoot 'record-folder.txt') $out -Encoding utf8
}
[ordered]@{Status='observations-match';ExactConfigurationUnchanged=$true;PublicVariablesUnchanged=$true;EnabledDecryptedWindowsPathObserved=$true}|ConvertTo-Json|Set-Content (Join-Path $out 'policy-check.json') -Encoding utf8
if($Mode -eq 'Verify'){Set-Content (Join-Path $PSScriptRoot 'verify-folder.txt') $out -Encoding utf8}
if($PassThru){[pscustomobject]@{OutputFolder=$out;BaselinePath=(Join-Path $out 'baseline.json');ReportPath=(Join-Path $out 'policy-check.json')}}
'@ | Set-Content (Join-Path $root 'test-policy-baseline.ps1') -Encoding utf8
function Run-Inspection([string]$Arguments,[string[]]$Answers){
 $p=New-Object Diagnostics.Process
 try{
  $p.StartInfo.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $p.StartInfo.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$entry+'" '+$Arguments
  $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
  $p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  $p.Start()|Out-Null
  $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  foreach($a in $Answers){$p.StandardInput.WriteLine($a)};$p.StandardInput.Close()
  if(!$p.WaitForExit(15000)){$p.Kill();throw 'CLI test timeout'}
  return [pscustomobject]@{Exit=$p.ExitCode;Out=$stdout.Result}
 }finally{$p.Dispose()}
}
$r=Run-Inspection '' @('DECLINE')
if($r.Exit -eq 0 -or (Test-Path (Join-Path $root 'record-folder.txt')) -or $r.Out.Contains('BASELINE READY')){throw 'Decline reached baseline or firmware briefing'}
$r=Run-Inspection '' @('INSPECT-ONLY')
if($r.Exit -ne 0 -or !$r.Out.Contains('BASELINE READY')){throw 'Accepted mock preparation failed'}
$folder=(Get-Content (Join-Path $root 'record-folder.txt') -Raw).Trim()
if(!(Test-Path (Join-Path $folder 'inspection-receipt.json'))){throw 'Receipt missing'}
$r=Run-Inspection ('-Verify -Folder "'+$folder+'"') @('YES','UNKNOWN','UNKNOWN')
if($r.Exit -ne 0){throw 'Mock verification failed'}
$verifyFolder=(Get-Content (Join-Path $root 'verify-folder.txt') -Raw).Trim()
$report=Get-Content (Join-Path $verifyFolder 'inspection-check.json') -Raw|ConvertFrom-Json
if(!$report.BaselineObservationsMatch -or $report.OwnerReportedMenuMatch -cne 'UNKNOWN' -or $report.PolicyChangeAuthorized -or $report.EfiExecutionAuthorized -or $report.RecoveryVerified){throw 'CLI report widened authorization or lost unknown'}
'changed'|Set-Content (Join-Path $folder 'baseline.json')
$r=Run-Inspection ('-Verify -Folder "'+$folder+'"') @()
if($r.Exit -eq 0){throw 'Tampered baseline passed actual CLI'}
Write-Host 'PASS: actual CLI decline, accepted mock baseline, unknown verification and tamper refusal. Synthetic helper; no system/firmware queries.'
