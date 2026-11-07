# GPL-2.0-only. Local state and read-only orchestration for Start-Capture.cmd.
# This module never installs tools, changes policy, prepares media or boots.

function Test-GuSessionInteger($Value) {
 return ($Value -is [int] -or $Value -is [long])
}

function Assert-GuSessionPath([string]$Path) {
 $full=[IO.Path]::GetFullPath($Path)
 if($full.StartsWith('\\')){throw 'Use a local session folder.'}
 $item=$full
 while($item) {
  if(Test-Path -LiteralPath $item) {
   $entry=Get-Item -LiteralPath $item -Force -ErrorAction Stop
   if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Session paths must not use links or reparse points.'}
  }
  $parent=[IO.Path]::GetDirectoryName($item)
  if($parent -eq $item){break}
  $item=$parent
 }
 return $full
}

function Get-GuSessionHash([string]$Path) {
 return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Get-GuSessionTextHash([string]$Text) {
 $hash=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}
 finally{$hash.Dispose()}
}

function Write-GuSessionJson([string]$Path,$Value) {
 $full=Assert-GuSessionPath $Path
 $parent=[IO.Path]::GetDirectoryName($full)
 if(!(Test-Path -LiteralPath $parent -PathType Container)){throw 'Session output folder is unavailable.'}
 $pending=Join-Path $parent ('.'+[IO.Path]::GetFileName($full)+'.pending-'+[guid]::NewGuid().ToString('N'))
 try {
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 64))
  $stream=[IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  if(Test-Path -LiteralPath $full){[IO.File]::Replace($pending,$full,[System.Management.Automation.Language.NullString]::Value)}
  else{[IO.File]::Move($pending,$full)}
 }finally{
  if(Test-Path -LiteralPath $pending -PathType Leaf){Remove-Item -LiteralPath $pending -ErrorAction SilentlyContinue}
 }
}

function Read-GuSessionJson([string]$Path) {
 $full=Assert-GuSessionPath $Path
 $item=Get-Item -LiteralPath $full -ErrorAction Stop
 if($item.PSIsContainer -or $item.Length -gt 16MB){throw 'Session record is not a bounded regular file.'}
 try{return [IO.File]::ReadAllText($full)|ConvertFrom-Json -ErrorAction Stop}
 catch{throw 'Session record is unreadable. Preserve it and choose a new local session folder.'}
}

function Open-GuDiagnosticSession([string]$Root) {
 if(!$Root) {
  $documents=[Environment]::GetFolderPath('MyDocuments')
  if(!$documents){throw 'Documents is unavailable. Supply -SessionRoot with a writable local folder.'}
  $Root=Join-Path $documents 'GPU-Unlock-Diagnostics'
 }
 $full=Assert-GuSessionPath $Root
 if(!(Test-Path -LiteralPath $full)){New-Item -ItemType Directory -Path $full -ErrorAction Stop|Out-Null}
 if(!(Test-Path -LiteralPath $full -PathType Container)){throw 'Session root is not a directory.'}
 $lockPath=Assert-GuSessionPath (Join-Path $full 'session.lock')
 try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
 catch{throw 'This session is already open or is not writable. Close the other setup window and reopen this one.'}
 try {
  $statePath=Join-Path $full 'session.json'
  if(Test-Path -LiteralPath $statePath) {
   $old=Read-GuSessionJson $statePath
   if(!(Test-GuSessionInteger $old.SchemaVersion) -or $old.SchemaVersion -ne 1 -or
      $old.SessionId -isnot [string] -or $old.SessionId -cnotmatch '^[0-9a-f]{32}$' -or
      $old.EvidenceDirectory -isnot [string] -or $old.EvidenceDirectory.Length -gt 4096 -or
      $old.AnalysisCacheKey -isnot [string] -or $old.AnalysisCacheKey -cnotmatch '^(?:[0-9a-f]{64})?$' -or
      $old.AnalysisReportSha256 -isnot [string] -or $old.AnalysisReportSha256 -cnotmatch '^(?:[0-9a-f]{64})?$') {
    throw 'Session schema is invalid. Preserve the folder and choose another -SessionRoot.'
   }
   $state=[ordered]@{SchemaVersion=1;SessionId=$old.SessionId;CreatedUtc=[string]$old.CreatedUtc
    UpdatedUtc=[string]$old.UpdatedUtc;SourceDigest=[string]$old.SourceDigest
    EvidenceDirectory=$old.EvidenceDirectory;AnalysisCacheKey=$old.AnalysisCacheKey
    AnalysisReportSha256=$old.AnalysisReportSha256;InputChoiceRecorded=($old.InputChoiceRecorded -eq $true)}
  } else {
   $state=[ordered]@{SchemaVersion=1;SessionId=[guid]::NewGuid().ToString('N')
    CreatedUtc=[DateTime]::UtcNow.ToString('o');UpdatedUtc='';SourceDigest=''
    EvidenceDirectory='';AnalysisCacheKey='';AnalysisReportSha256='';InputChoiceRecorded=$false}
   Write-GuSessionJson $statePath $state
  }
  return [pscustomobject]@{Root=$full;State=$state;Lock=$lock}
 }catch{$lock.Dispose();throw}
}

function Get-GuDiagnosticSourceDigest {
 $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
 $paths=@('tools/start-capture.ps1','tools/capture-setup.ps1','tools/diagnostic-session.ps1',
  'tools/diagnostic-process.ps1','tools/diagnostic-inventory.ps1',
  'tools/test-windows-preflight.ps1','tools/test-pci-parents.ps1','tools/diagnostic-graph.ps1',
  'tools/review_diagnostic_session.py','research/profile/check-compatibility.py',
  'research/profile/make-profile.py','research/profile/proven.json','research/profile/capture_graph.py',
  'research/profile/gpu_path.py','research/profile/summarize-graph.py',
  'research/profile/review-nvgop-code.py','research/profile/review-edid-bindings.py',
  'research/profile/review-command-log.py','research/profile/review-gop-records.py',
  'research/profile/graph-template.ps1','research/profile/graph-template/template.json')
 $rows=foreach($path in $paths) {
  $full=Join-Path $repo $path
  if(Test-Path -LiteralPath $full -PathType Leaf){$path+' '+(Get-GuSessionHash $full)}
  else{$path+' missing'}
 }
 return Get-GuSessionTextHash ($rows -join [char]10)
}

function Test-GuAnalysisReport($Report) {
 if($null -eq $Report){return $false}
 return ((Test-GuSessionInteger $Report.SchemaVersion) -and $Report.SchemaVersion -eq 1 -and
  $Report.hardware_tested -is [bool] -and $Report.hardware_tested -eq $false -and
  $Report.write_eligible -is [bool] -and $Report.write_eligible -eq $false -and
  $Report.CacheKey -is [string] -and $Report.CacheKey -cmatch '^[0-9a-f]{64}$')
}

function Invoke-GuSavedEvidence([string]$Folder,[string]$Python,[string]$PreviousCacheKey) {
 . (Join-Path $PSScriptRoot '../research/profile/collection-host.ps1')
 . (Join-Path $PSScriptRoot 'diagnostic-process.ps1')
 try{$application=Resolve-GuPythonApplication $Python}
 catch{return [pscustomobject]@{Status='dependency-needed';Reason='python-unavailable';Report=$null;Reused=$false}}
 $arguments=@('-I','-B',(Join-Path $PSScriptRoot 'review_diagnostic_session.py'),$Folder)
 if($PreviousCacheKey){$arguments+=@('--previous-cache-key',$PreviousCacheKey)}
 try {
  $process=Invoke-GuDiagnosticProcess -Application $application -ArgumentList $arguments -TimeoutSeconds 120 -MaxOutputCharacters 16MB
  if($process.Status -ne 'completed') {
   $reason=if($process.Status -in @('timeout','output-limit','start-failed')){'analyzer-'+$process.Status}else{'analyzer-unavailable'}
   return [pscustomobject]@{Status='analysis-unavailable';Reason=$reason;Report=$null;Reused=$false}
  }
  $exit=$process.ExitCode
  $text=$process.StandardOutput
  $report=$text|ConvertFrom-Json -ErrorAction Stop
  if($exit -notin @(0,2,3) -or !(Test-GuAnalysisReport $report)){throw 'Unexpected analyzer result'}
  return [pscustomobject]@{Status=if($exit -eq 0){'reviewed'}elseif($exit -eq 2){'input-refused'}else{'analysis-unavailable'}
   Reason=if($exit -eq 0){'existing-files-only'}elseif($exit -eq 2){'input-needs-review'}else{'analyzer-unavailable'}
   Report=$report;Reused=$false}
 }catch{return [pscustomobject]@{Status='analysis-unavailable';Reason='analyzer-did-not-return-a-valid-report';Report=$null;Reused=$false}}
}

function Get-GuPublicGraphOption($Capabilities,[bool]$Prepared) {
 $available=($Capabilities.Available -is [bool] -and $Capabilities.Available -eq $true)
 $reasons=@($Capabilities.Reasons | Where-Object {$_ -is [string] -and $_ -cmatch '^[a-z0-9][a-z0-9-]{0,95}$'})
 if(!$available -and !$reasons.Count){$reasons=@('capability-unavailable')}
 return [ordered]@{Available=($available -and !$Prepared);AlreadyPrepared=$Prepared;Reasons=$reasons
  Scope='graph-only';RequiresExplicitConfirmation=$true
  CanUnlock=$false;CanDetach=$false;ReadsGpuMmio=$false;DumpsProm=$false;DumpsImages=$false}
}

function Get-GuDiagnosticNextAction($Saved,$Association,$Graph) {
 if($Saved.Status -eq 'dependency-needed') {
  return [ordered]@{Code='python-needed-for-saved-files';Message='Windows observations are ready. Install or select Python to review the saved files, then reopen the same launcher. No EFI repeat is needed.'}
 }
 if($Saved.Status -in @('input-refused','analysis-unavailable','input-unavailable')) {
  return [ordered]@{Code='review-saved-inputs';Message='Keep the existing files and share report.json. The saved-file review needs attention; no further EFI capture is requested.'}
 }
 if($Saved.Status -eq 'reviewed') {
  return [ordered]@{Code='share-report';Message='Share report.json for the next evidence-based step. Keep raw captures locally. No additional EFI capture is requested.'}
 }
 if($Association.Status -eq 'refused') {
  return [ordered]@{Code='review-prepared-session';Message='The prepared session could not be associated with this media/source. Preserve the USB and local session. Saved files can still be reviewed separately; do not repeat the EFI run.'}
 }
 if($Graph.PreparationIncomplete) {
  return [ordered]@{Code='review-incomplete-preparation';Message='A previous preparation attempt has no completed receipt. Preserve the local session and USB for review; the launcher will not prepare or request a boot again.'}
 }
 if($Graph.AlreadyPrepared) {
  return [ordered]@{Code='resume-existing-session';Message='This session already has a preparation receipt. Reopen this same launcher with the original USB to collect existing results. If the test was already attempted, do not repeat it.'}
 }
 if($Graph.Available) {
  return [ordered]@{Code='optional-graph-observation';Message='Windows observations are ready. You can review saved captures or choose one graph-only USB observation from this launcher.'}
 }
 return [ordered]@{Code='share-windows-report';Message='Share report.json or open a folder of existing captures in this launcher. The report explains which EFI prerequisites are unavailable.'}
}

function Invoke-GuDiagnosticSession($Session,[string]$Captures,[string]$Python='python',[switch]$Offline) {
 $state=$Session.State
 $source=Get-GuDiagnosticSourceDigest
 $sourceChanged=($state.SourceDigest -and $state.SourceDigest -cne $source)
 $prepared=Test-Path -LiteralPath (Join-Path $Session.Root 'graph-receipt.json') -PathType Leaf
 $attempted=Test-Path -LiteralPath (Join-Path $Session.Root 'graph-preparation.json') -PathType Leaf
 $association=[ordered]@{Status='not-associated';Reason='saved-files-are-unbound';ReceiptVerified=$false}
 $capabilities=[pscustomobject]@{Available=$false;Reasons=@('offline-only')}
 $hostReport=$null
 if(!$Offline) {
  try{$hostReport=Get-GuDiagnosticInventory}
  catch{$hostReport=[ordered]@{SchemaVersion=1;ReadStatus='unavailable';Reason='windows-inventory-unavailable';hardware_tested=$false;write_eligible=$false}}
  try{$capabilities=Get-GuGraphCapabilities}
  catch{$capabilities=[pscustomobject]@{Available=$false;Reasons=@('capability-query-unavailable')}}
  if($prepared -and !$Captures) {
   try {
    $collected=Read-GuDiagnosticGraphCapture -SessionRoot $Session.Root
    $reason=if($collected.Reason -is [string] -and $collected.Reason -cmatch '^[a-z0-9][a-z0-9-]{0,95}$'){$collected.Reason}else{'collection-status'}
    $status=if($collected.Status -in @('collected','complete','waiting','pending','awaiting-capture','refused','unavailable')){[string]$collected.Status}else{'refused'}
    $association=[ordered]@{Status=$status;Reason=$reason;ReceiptVerified=($collected.ReceiptVerified -eq $true)}
    if($collected.ReceiptVerified -eq $true -and $collected.CaptureDirectory) {$state.EvidenceDirectory=[string]$collected.CaptureDirectory}
   }catch{$association=[ordered]@{Status='refused';Reason='collection-unavailable';ReceiptVerified=$false}}
  }
 }
 $inputError=$false
 if($Captures){
  try{$state.EvidenceDirectory=[IO.Path]::GetFullPath($Captures)}
  catch{$inputError=$true;$state.EvidenceDirectory=''}
  $state.InputChoiceRecorded=$true
 }
 $saved=[pscustomobject]@{Status='not-provided';Reason='no-saved-inputs';Report=$null;Reused=$false}
 if($inputError){
  $saved=[pscustomobject]@{Status='input-unavailable';Reason='input-directory-invalid';Report=$null;Reused=$false}
 }elseif($state.EvidenceDirectory) {
  $evidence=[IO.Path]::GetFullPath($state.EvidenceDirectory).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
  $sessionPath=$Session.Root.TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
  if(!(Test-Path -LiteralPath $state.EvidenceDirectory -PathType Container) -or
     $sessionPath.StartsWith($evidence,[StringComparison]::OrdinalIgnoreCase)) {
   $saved=[pscustomobject]@{Status='input-unavailable';Reason='select-the-capture-folder-not-the-session-or-its-parent';Report=$null;Reused=$false}
  }else{
   $previous=$null
   $analysisPath=Join-Path $Session.Root 'analysis.json'
   if($state.AnalysisCacheKey -and $state.AnalysisReportSha256 -and (Test-Path -LiteralPath $analysisPath)) {
    try {
     if((Get-GuSessionHash (Assert-GuSessionPath $analysisPath)) -ceq $state.AnalysisReportSha256) {
      $candidate=Read-GuSessionJson $analysisPath
      if((Test-GuAnalysisReport $candidate) -and $candidate.CacheReusable -eq $true -and
         $candidate.CacheKey -ceq $state.AnalysisCacheKey){$previous=$candidate}
     }
    }catch{$previous=$null}
   }
   $key=if($previous -and !$sourceChanged){$state.AnalysisCacheKey}else{''}
   $saved=Invoke-GuSavedEvidence $state.EvidenceDirectory $Python $key
   if($saved.Report -and $saved.Report.Unchanged -eq $true) {
    if($previous -and $saved.Report.CacheKey -ceq $previous.CacheKey) {
     $saved.Report=$previous;$saved.Reused=$true
    }else{$saved=Invoke-GuSavedEvidence $state.EvidenceDirectory $Python ''}
   }
   if($saved.Report) {
    Write-GuSessionJson $analysisPath $saved.Report
    $state.AnalysisCacheKey=if($saved.Status -eq 'reviewed' -and $saved.Report.CacheReusable -eq $true){$saved.Report.CacheKey}else{''}
    $state.AnalysisReportSha256=Get-GuSessionHash $analysisPath
   }
  }
 }
 $graph=Get-GuPublicGraphOption $capabilities $prepared
 $association['CurrentHostVerified']=$false
 $association['CaptureOriginAttested']=$false
 $graph['AttemptRecorded']=[bool]$attempted
 $graph['PreparationIncomplete']=($attempted -and !$prepared)
 if($attempted){$graph.Available=$false}
 $report=[ordered]@{SchemaVersion=1;Test='unified-diagnostics-v1';SessionId=$state.SessionId
  UpdatedUtc=[DateTime]::UtcNow.ToString('o');SourceDigest=$source;SourceChanged=[bool]$sourceChanged
  CollectionHost=$hostReport;SavedEvidence=[ordered]@{Status=$saved.Status;Reason=$saved.Reason;Reused=$saved.Reused;Analysis=$saved.Report}
  CaptureAssociation=$association;GraphOption=$graph
  NextAction=(Get-GuDiagnosticNextAction $saved $association $graph)
  hardware_tested=$false;write_eligible=$false}
 Write-GuSessionJson (Join-Path $Session.Root 'report.json') $report
 $state.SourceDigest=$source;$state.UpdatedUtc=$report.UpdatedUtc
 Write-GuSessionJson (Join-Path $Session.Root 'session.json') $state
 return [pscustomobject]$report
}
