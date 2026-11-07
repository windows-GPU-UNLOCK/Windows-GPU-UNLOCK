# GPL-2.0-only. One resumable entry point for Windows and saved-file diagnostics.
[CmdletBinding()]
param(
 [string]$Captures,
 [string]$SessionRoot,
 [string]$Python='python',
 [switch]$Offline,
 [switch]$NonInteractive,
 [switch]$Prepare,
 [ValidatePattern('^(?:[D-Zd-z])?$')][string]$Drive,
 [string]$Confirmation,
 [switch]$Resume
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'diagnostic-session.ps1')
. (Join-Path $PSScriptRoot 'diagnostic-inventory.ps1')
. (Join-Path $PSScriptRoot 'diagnostic-graph.ps1')
. (Join-Path $PSScriptRoot 'capture-setup.ps1')

function Show-GuDiagnosticSummary($Report,[string]$Root) {
 Write-Host ''
 Write-Host 'Windows GPU diagnostics'
 if($Report.CollectionHost) {
  Write-Host ('Windows inventory: '+$Report.CollectionHost.ReadStatus)
  Write-Host ('Display adapters observed: '+@($Report.CollectionHost.DisplayAdapters).Count)
 }
 Write-Host ('Saved-file review: '+$Report.SavedEvidence.Status)
 if($Report.SavedEvidence.Reused){Write-Host 'Unchanged saved inputs: reused the verified offline result.'}
 if($Report.SourceChanged){Write-Host 'Source files changed: cached analysis was rechecked.'}
 if($Report.GraphOption.AlreadyPrepared){Write-Host 'An existing USB preparation was found. This launcher will collect it without staging again.'}
 elseif($Report.GraphOption.PreparationIncomplete){Write-Host 'A previous preparation attempt needs review. No further staging or EFI attempt is requested.'}
 elseif(!$Report.GraphOption.Available){Write-Host ('Graph-only EFI unavailable: '+($Report.GraphOption.Reasons -join ', '))}
 Write-Host ''
 Write-Host $Report.NextAction.Message
 Write-Host ('Report to review and share: '+(Join-Path $Root 'report.json'))
 Write-Host 'The other session files and original captures stay local.'
}

$session=$null
try {
 if($Offline -and $Prepare){throw 'Offline review cannot prepare EFI media.'}
 $session=Open-GuDiagnosticSession $SessionRoot
 if(!$NonInteractive -and !$Captures -and !$session.State.EvidenceDirectory -and !$session.State.InputChoiceRecorded -and
    !(Test-Path -LiteralPath (Join-Path $session.Root 'graph-receipt.json'))) {
  Write-Host 'Already have captures? Paste their folder, or press Enter to observe this Windows machine.'
  $answer=Read-Host 'Capture folder'
  $session.State.InputChoiceRecorded=$true
  if($answer){$Captures=$answer.Trim().Trim('"')}
 }
 $report=Invoke-GuDiagnosticSession $session -Captures $Captures -Python $Python -Offline:$Offline
 Show-GuDiagnosticSummary $report $session.Root
 $wantPrepare=[bool]$Prepare
 if(!$NonInteractive -and !$Offline -and !$Prepare -and $report.GraphOption.Available -and
    $report.SavedEvidence.Status -eq 'not-provided') {
  Write-Host ''
  Write-Host 'Optional: one USB graph observation records firmware display/PCI relationships.'
  Write-Host 'It does not read GPU MMIO, dump firmware images, release drivers or unlock the GPU.'
  $wantPrepare=((Read-Host 'Type USB to prepare this observation, or Enter to finish') -ceq 'USB')
 }
 if($wantPrepare) {
  if(!$report.GraphOption.Available){throw 'Graph preparation is unavailable. Read report.json; no repeat or alternative boot is requested.'}
  $choices=@(Get-CaptureUsbChoices)
  if(!$choices.Count){throw 'Connect a FAT32 USB with a drive letter. The Windows report is already saved.'}
  $selected=$null
  if($Drive) {
   $matches=@($choices|Where-Object {$_.Drive -eq $Drive})
   if($matches.Count -ne 1 -or !$matches[0].Eligible){throw 'The selected USB is not available. Nothing was staged.'}
   $selected=$matches[0]
  }elseif($NonInteractive){throw 'Explicit -Drive is required with -Prepare -NonInteractive.'}
  else{
   for($i=0;$i -lt $choices.Count;$i++) {
    $c=$choices[$i];$state=if($c.Eligible){'available'}else{$c.Reason}
    Write-Host ('{0}. {1}: {2} | {3} | {4} GiB | {5}' -f ($i+1),$c.Drive,$c.Label,$c.Model,$c.SizeGiB,$state)
   }
   $selected=Select-CaptureUsb $choices (Read-Host 'USB number (Enter to cancel)')
  }
  Write-Host ('Selected '+$selected.Drive+': '+$selected.Label+' ('+$selected.Model+')')
  Write-Host 'Preparation copies a graph-only EFI and backs up any existing removable boot loader.'
  Write-Host 'It does not format the USB, change boot settings or restart Windows.'
  Write-Host 'Booting a firmware diagnostic can hang. This session requests at most one observation.'
  if(!$NonInteractive){$Confirmation=Read-Host 'Type PREPARE to continue, or Enter to cancel'}
  if($Confirmation -cne 'PREPARE'){throw 'Cancelled. The diagnostic report is saved; nothing was staged.'}
  Assert-CaptureUsbUnchanged $selected
  $prepared=Prepare-GuDiagnosticGraph -SessionRoot $session.Root -Drive $selected.Drive -Confirmation $Confirmation
  Write-Host ''
  Write-Host 'USB prepared. Fully shut down, then manually select this USB once from the firmware boot menu.'
  Write-Host 'If Windows has not started after two minutes, power off, remove the USB and use normal Windows Boot Manager.'
  Write-Host 'If recovery is needed, record that outcome. Do not repeat the diagnostic.'
  Write-Host 'After returning to Windows, reopen Start-Capture.cmd with the same session and USB.'
  $report.GraphOption.AlreadyPrepared=$true
  $report.GraphOption.Available=$false
  $report.NextAction=[ordered]@{Code='one-prepared-observation';Message='The selected USB is prepared for one manually selected graph observation. Reopen the same launcher afterward to collect its results. Do not repeat an attempted run.'}
  Write-GuSessionJson (Join-Path $session.Root 'report.json') $report
 }
} catch {
 Write-Host ''
 Write-Host ('Diagnostics stopped: '+$_.Exception.Message) -ForegroundColor Yellow
 Write-Host 'Keep any existing report and captures. No automatic boot or retry was requested.'
 exit 1
} finally {
 if($session -and $session.Lock){$session.Lock.Dispose()}
}
