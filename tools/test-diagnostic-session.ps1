# GPL-2.0-only. Local file/replay tests; no Windows inventory, USB access or boot.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'diagnostic-session.ps1')
$script:Checks=0
function Assert-SessionTest([bool]$Condition,[string]$Message) {
 if(!$Condition){throw ('FAILED: '+$Message)}
 $script:Checks++
}
function Assert-SessionThrows([scriptblock]$Action,[string]$Message) {
 $failed=$false
 try{& $Action|Out-Null}catch{$failed=$true}
 Assert-SessionTest $failed $Message
}
$script:InventoryCalls=0;$script:GraphReads=0;$script:ParserCalls=0;$script:AnalyzerCalls=0
$script:AnalyzerMode='normal'
function Get-GuDiagnosticInventory {
 $script:InventoryCalls++
 return [pscustomobject]@{SchemaVersion=1;ReadStatus='partial';DisplayAdapters=@(
  @{Index=0;Pci=@{Vendor='1002';Device='FFFF';Subsystem='00000000'}},
  @{Index=1;Pci=@{Vendor='10DE';Device='FFFF';Subsystem='11111111'}},
  @{Index=2;Pci=@{Vendor='10DE';Device='FFFF';Subsystem='11111111'}})
  hardware_tested=$false;write_eligible=$false}
}
function Get-GuGraphCapabilities {return [pscustomobject]@{Available=$true;Reasons=@()}}
function Read-GuDiagnosticGraphCapture {
 param($SessionRoot)
 $script:GraphReads++
 return [pscustomobject]@{Status='awaiting-capture';Reason='no-existing-capture';ReceiptVerified=$false;CaptureDirectory=$null}
}
function Prepare-GuDiagnosticGraph {throw 'Read-only session must never prepare media'}
function Invoke-GuSavedEvidence([string]$Folder,[string]$Python,[string]$PreviousCacheKey) {
 $script:AnalyzerCalls++
 if($script:AnalyzerMode -eq 'missing-python'){
  return [pscustomobject]@{Status='dependency-needed';Reason='python-unavailable';Report=$null;Reused=$false}
 }
 if($script:AnalyzerMode -eq 'refused'){
  return [pscustomobject]@{Status='input-refused';Reason='input-needs-review';Report=$null;Reused=$false}
 }
 $hash=Get-GuSessionHash (Join-Path $Folder 'DIAG00.TXT')
 $unchanged=($hash -ceq $PreviousCacheKey)
 if(!$unchanged){$script:ParserCalls++}
 $analysis=[pscustomobject]@{SchemaVersion=1;CacheKey=$hash;InputDigest=$hash;AnalyzerDigest=('b'*64)
  InputFiles=@(@{Id='capture-1';Kind='diagnostic';Bytes=1;Sha256=$hash})
  Stages=@(@{Name='graph';Status='partial'});Observations=@()
  Unchanged=$unchanged;CacheReusable=$true;hardware_tested=$false;write_eligible=$false}
 return [pscustomobject]@{Status='reviewed';Reason='existing-files-only';Report=$analysis;Reused=$false}
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('gpu-unified-session-test-'+[guid]::NewGuid().ToString('N'))
$session=$null
try {
 New-Item -ItemType Directory -Path $testRoot|Out-Null
 $captureRoot=Join-Path $testRoot 'saved captures'
 New-Item -ItemType Directory -Path $captureRoot|Out-Null
 [IO.File]::WriteAllText((Join-Path $captureRoot 'DIAG00.TXT'),'capture-complete=0')
 $session=Open-GuDiagnosticSession (Join-Path $testRoot 'session')
 $id=$session.State.SessionId
 Assert-SessionTest ($id -cmatch '^[0-9a-f]{32}$') 'session identity created'
 Assert-SessionThrows {Open-GuDiagnosticSession $session.Root} 'concurrent invocation is refused'
 $before=$script:InventoryCalls
 $report=Invoke-GuDiagnosticSession $session -Captures $captureRoot -Offline
 Assert-SessionTest ($script:InventoryCalls -eq $before) 'offline review does not query Windows'
 Assert-SessionTest (!$report.GraphOption.Available) 'offline review does not offer preparation'
 Assert-SessionTest ($report.SavedEvidence.Status -eq 'reviewed' -and !$report.SavedEvidence.Reused) 'first existing-file review runs'
 Assert-SessionTest ($report.NextAction.Code -eq 'share-report') 'partial capture does not request another boot'
 Assert-SessionTest (!$report.hardware_tested -and !$report.write_eligible) 'analysis grants no hardware eligibility'
 $public=[IO.File]::ReadAllText((Join-Path $session.Root 'report.json'))
 Assert-SessionTest (!$public.Contains($testRoot) -and !$public.Contains($captureRoot)) 'private session and input paths are absent'
 $report=Invoke-GuDiagnosticSession $session -Offline
 Assert-SessionTest ($report.SavedEvidence.Reused -and $script:ParserCalls -eq 1) 'unchanged inputs reuse analysis'
 Assert-SessionTest ($script:AnalyzerCalls -eq 2) 'reuse still rechecks input hashes'
 [IO.File]::WriteAllText((Join-Path $captureRoot 'DIAG00.TXT'),'capture-complete=0 changed')
 $report=Invoke-GuDiagnosticSession $session -Offline
 Assert-SessionTest (!$report.SavedEvidence.Reused -and $script:ParserCalls -eq 2) 'input drift reruns analysis'
 $session.State.SourceDigest='a'*64
 $report=Invoke-GuDiagnosticSession $session -Offline
 Assert-SessionTest ($report.SourceChanged -and !$report.SavedEvidence.Reused -and $script:ParserCalls -eq 3) 'source drift invalidates reuse'
 [IO.File]::AppendAllText((Join-Path $session.Root 'analysis.json'),' ')
 $report=Invoke-GuDiagnosticSession $session -Offline
 Assert-SessionTest (!$report.SavedEvidence.Reused -and $script:ParserCalls -eq 4) 'cached output drift invalidates reuse'
 $script:AnalyzerMode='missing-python'
 $report=Invoke-GuDiagnosticSession $session
 Assert-SessionTest ($report.CollectionHost.DisplayAdapters.Count -eq 3) 'mixed and duplicate adapters retained'
 Assert-SessionTest ($report.SavedEvidence.Status -eq 'dependency-needed') 'missing Python does not prevent Windows report'
 Assert-SessionTest ($report.NextAction.Code -eq 'python-needed-for-saved-files') 'missing dependency does not request EFI'
 $script:AnalyzerMode='refused'
 $report=Invoke-GuDiagnosticSession $session
 Assert-SessionTest ($report.NextAction.Code -eq 'review-saved-inputs') 'unsafe input gets review without a boot'
 $session.State.EvidenceDirectory=''
 Write-GuSessionJson (Join-Path $session.Root 'graph-preparation.json') @{Attempt='started'}
 $report=Invoke-GuDiagnosticSession $session
 Assert-SessionTest ($report.GraphOption.PreparationIncomplete -and !$report.GraphOption.Available) 'interrupted preparation never offers restage'
 Assert-SessionTest ($report.NextAction.Code -eq 'review-incomplete-preparation') 'interrupted preparation explains review'
 Write-GuSessionJson (Join-Path $session.Root 'graph-receipt.json') @{Receipt='mock'}
 $report=Invoke-GuDiagnosticSession $session
 Assert-SessionTest ($script:GraphReads -eq 1 -and $report.GraphOption.AlreadyPrepared) 'resume collects before considering preparation'
 Assert-SessionTest ($report.NextAction.Code -eq 'resume-existing-session') 'no existing log does not request another preparation'
 $report=Invoke-GuDiagnosticSession $session -Captures $session.Root -Offline
 Assert-SessionTest ($report.SavedEvidence.Status -eq 'input-unavailable') 'session output cannot become its own input'
 $report=Invoke-GuDiagnosticSession $session -Captures $testRoot -Offline
 Assert-SessionTest ($report.SavedEvidence.Status -eq 'input-unavailable') 'input parent cannot include session outputs'
 $report=Invoke-GuDiagnosticSession $session -Captures ([string][char]0)
 Assert-SessionTest ($report.SavedEvidence.Reason -eq 'input-directory-invalid' -and $report.CollectionHost) 'invalid input path still preserves Windows report'
 Assert-SessionTest (!$session.State.EvidenceDirectory) 'invalid new input does not silently reuse a previous folder'
 $stateFile=Join-Path $session.Root 'session.json'
 $stateBefore=[IO.File]::ReadAllText($stateFile)
 $held=[IO.File]::Open($stateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{Assert-SessionThrows {Write-GuSessionJson $stateFile @{broken='replacement'}} 'failed atomic replacement is surfaced'}
 finally{$held.Dispose()}
 Assert-SessionTest ([IO.File]::ReadAllText($stateFile) -ceq $stateBefore) 'failed replacement preserves previous state'
 Assert-SessionTest (@(Get-ChildItem -LiteralPath $session.Root -Force -Filter '*.pending-*').Count -eq 0) 'failed replacement removes only its own pending output'
 $session.Lock.Dispose();$session=$null
 $session=Open-GuDiagnosticSession (Join-Path $testRoot 'session')
 Assert-SessionTest ($session.State.SessionId -ceq $id) 'resume retains session identity'
 $session.Lock.Dispose();$session=$null
 $bad=Join-Path $testRoot 'bad-schema'
 New-Item -ItemType Directory -Path $bad|Out-Null
 Write-GuSessionJson (Join-Path $bad 'session.json') @{SchemaVersion='1'}
 Assert-SessionThrows {Open-GuDiagnosticSession $bad} 'string schema version is refused'
 Write-GuSessionJson (Join-Path $bad 'session.json') @{SchemaVersion=1.0}
 Assert-SessionThrows {Open-GuDiagnosticSession $bad} 'float schema version is refused'
 foreach($flag in @($true,'false',0,$null)) {
  $claim=[pscustomobject]@{SchemaVersion=1;CacheKey=('a'*64);hardware_tested=$flag;write_eligible=$false}
  Assert-SessionTest (!(Test-GuAnalysisReport $claim)) 'non-false hardware claims are refused'
 }
 $launcher=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'start-capture.ps1'))
 $cmd=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../Start-Capture.cmd'))
 Assert-SessionTest ($launcher -notmatch '(?i)StageUnlock|new-machine[.]ps1|build-probe[.]ps1') 'single entry point has no profile or deep-probe dispatch'
 Assert-SessionTest (($launcher+$cmd) -notmatch '(?i)ExecutionPolicy|EncodedCommand|Set-ExecutionPolicy') 'launcher does not bypass script policy'
 Write-Host ('PASS: '+$script:Checks+' session assertions; local files and mocked providers only.')
} finally {
 if($session -and $session.Lock){$session.Lock.Dispose()}
 if(Test-Path -LiteralPath $testRoot) {
  $resolved=[IO.Path]::GetFullPath((Get-Item -LiteralPath $testRoot).FullName)
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
  if(!$resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
     [IO.Path]::GetFileName($resolved) -notmatch '^gpu-unified-session-test-[0-9a-f]{32}$'){throw 'Test cleanup boundary'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
