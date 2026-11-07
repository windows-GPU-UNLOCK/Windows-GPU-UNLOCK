# Offline only: reads existing files, never starts EFI or accesses GPU hardware.
[CmdletBinding()]
param([string]$Captures, [string]$Python='python.exe', [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
if (!$Captures) { $Captures = Read-Host 'Enter the folder containing your existing DIAG00.TXT / DIAG01.TXT' }
$source = (Resolve-Path -LiteralPath $Captures).Path
if (!(Test-Path -LiteralPath $source -PathType Container)) { throw 'Select a folder, not a file.' }
$root = Split-Path -Parent $PSScriptRoot
$pythonCommand = @(Get-Command $Python -CommandType Application -ErrorAction Stop)[0]
if($pythonCommand.Source -match '\\Microsoft\\WindowsApps\\python(?:3)?\.exe$') {
    throw 'Python resolves to a Windows app alias. Use -Python with your known-good python.exe path; do not change PATH.'
}
$documents = if($OutputRoot){(Resolve-Path -LiteralPath $OutputRoot).Path}else{[Environment]::GetFolderPath('MyDocuments')}
if (!$documents) { throw 'Documents folder is unavailable.' }
$output = Join-Path $documents ('GPU-Unlock-Capture-Check-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $output | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Get-ReceiptHash([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}
$sourceHashes = [ordered]@{}
foreach($relative in @('tools/test-existing-captures.ps1','research/profile/check-compatibility.py','research/profile/make-profile.py','research/profile/proven.json')) {
    $sourceHashes[$relative] = (Get-ReceiptHash (Join-Path $root $relative))
}
$result = [ordered]@{ test = 'existing-capture-refusal-v2'; run_id = [Guid]::NewGuid().ToString('N');
    source_sha256 = $sourceHashes; report_sha256 = $null; checker_exit = $null; status = 'FAILED'; phase = 'python-check' }
$process = New-Object System.Diagnostics.Process
try {
    $process.StartInfo.FileName = $pythonCommand.Source
    # Windows filenames cannot contain a quote. The folder is one quoted argument.
    $process.StartInfo.Arguments = '-I -c "import sys; print(''graph-python-''+str(sys.version_info[0]))"'
    $process.StartInfo.WorkingDirectory = $root
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = $utf8
    $process.StartInfo.StandardErrorEncoding = $utf8
    if (!$process.Start()) { throw 'Python did not start.' }
    $probeOut = $process.StandardOutput.ReadToEndAsync()
    $probeErr = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(10000)) { $process.Kill(); throw 'Python check timed out.' }
    if ($process.ExitCode -ne 0 -or $probeOut.Result.Trim() -cne 'graph-python-3') { throw 'Not a working Python 3 interpreter.' }
    $process.Close()
    $result.phase = 'checker'
    $process.StartInfo.Arguments = '-I research/profile/check-compatibility.py "' + (Join-Path $source '.') + '" --json'
    if (!$process.Start()) { throw 'Python did not start.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(120000)) { $process.Kill(); throw 'Offline check timed out.' }
    $result.checker_exit = $process.ExitCode
    if ($process.ExitCode -notin @(0, 2, 3)) { throw 'Checker failed.' }
    $report = $stdout.Result | ConvertFrom-Json
    if ($report.route -ne 'automatic_local_profile' -or $report.write_eligible -ne $false -or
        $report.hardware_tested -ne $false) { throw 'Unexpected report.' }
    [IO.File]::WriteAllText((Join-Path $output 'report.json'), $stdout.Result, $utf8)
    foreach($relative in $sourceHashes.Keys) {
        if((Get-ReceiptHash (Join-Path $root $relative)) -ne $sourceHashes[$relative]) {
            throw 'Source changed during check; stop and retain these results.'
        }
    }
    $result.report_sha256 = (Get-ReceiptHash (Join-Path $output 'report.json'))
    $result.status = $report.status
    $result.phase = 'done'
    Write-Host ('Report status: ' + $report.status)
    foreach ($check in $report.checks) { Write-Host ($check.capture + ': ' + $check.code) }
} catch {
    Write-Host 'The offline check failed. Send result.json; do not collect new EFI logs.'
    if($result.phase -eq 'python-check') { Write-Host 'Use -Python with the known-good Python 3 executable you already use. Do not change PATH or settings.' }
} finally {
    $process.Dispose()
    [IO.File]::WriteAllText((Join-Path $output 'result.json'), ($result | ConvertTo-Json), $utf8)
}
Write-Host ('Results folder: ' + $output)
Write-Host 'Review and attach report.json (if present) and result.json to your existing issue.'
Write-Host 'A refusal remains refused. Do not reboot, change settings or force another profile.'
if ($result.status -eq 'FAILED') { exit 1 }
exit 0
