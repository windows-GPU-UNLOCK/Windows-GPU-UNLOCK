# Windows inventory test only. No elevation, EFI, GPU writes or settings changes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$documents = [Environment]::GetFolderPath('MyDocuments')
if (!$documents) { throw 'Documents folder is unavailable. Stop and report this message.' }
$folder = Join-Path $documents ('GPU-Unlock-Collector-Test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$python = @(Get-Command python.exe -CommandType Application -All -ErrorAction SilentlyContinue) | Select-Object -First 1
if (!$python -or $python.Source -isnot [string] -or $python.Source -match 'WindowsApps' -or !(Test-Path -LiteralPath $python.Source -PathType Leaf)) {
    throw 'An existing Python application was not found, or resolves to an installer alias. Stop without installing or changing settings.'
}
New-Item -ItemType Directory -Path $folder | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-TestPython([string]$arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $python.Source
    $info.Arguments = $arguments
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (!$process.Start()) { throw 'Python did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(120000)) {
            $process.Kill()
            throw 'Python timed out. Stop and report this message.'
        }
        [PSCustomObject]@{ Code = $process.ExitCode; Out = $stdout.Result; Err = $stderr.Result }
    } finally { $process.Dispose() }
}

$result = [ordered]@{
    test = 'collector-unicode-capture-v1'
    collector_sha256 = (Get-FileHash (Join-Path $PSScriptRoot 'collect_compatibility.py') -Algorithm SHA256).Hash.ToLowerInvariant()
    regression_exit = $null
    collection_exit = $null
    collection_complete = $false
    status = 'not-run'
}
try {
    Write-Host '1/2 Checking the collector with synthetic data...'
    $checks = Invoke-TestPython '-I -m unittest discover -s tools -p test_collect_compatibility.py'
    $result.regression_exit = $checks.Code
    if ($checks.Code -ne 0) { throw 'Synthetic checks failed. Stop here.' }
    Write-Host '2/2 Reading Windows hardware inventory...'
    $capture = Invoke-TestPython '-I tools/collect_compatibility.py'
    $result.collection_exit = $capture.Code
    if ($capture.Code -notin @(0, 2)) { throw 'Inventory collection failed. Stop here.' }
    $report = $capture.Out | ConvertFrom-Json
    if ($report.schema_version -ne 1 -or $report.purpose -ne 'compatibility-research-inventory' -or
        $report.assessment.can_unlock -ne $false -or $report.assessment.status -ne 'not-assessed') {
        throw 'Unexpected inventory response. Stop here.'
    }
    [IO.File]::WriteAllText((Join-Path $folder 'inventory.json'), $capture.Out, $utf8)
    $result.collection_complete = $report.collection_complete -eq $true
    $result.status = if ($capture.Code -eq 0 -and $result.collection_complete) { 'PASS' } else { 'PARTIAL' }
} catch {
    # Do not save raw subprocess output, traceback paths or local identifiers.
    $result.status = 'FAILED'
    Write-Host 'FAILED. Do not retry or change settings; send result.json and this status.'
} finally {
    [IO.File]::WriteAllText((Join-Path $folder 'result.json'), ($result | ConvertTo-Json), $utf8)
}
Write-Host ('Result: ' + $result.status)
Write-Host ('Files saved in: ' + $folder)
Write-Host 'Review result.json and inventory.json (if present), then attach those files to your issue.'
Write-Host 'Expected: PASS, collection_complete true, can_unlock false. This is an inventory test only.'
if ($result.status -eq 'FAILED') { exit 1 }
if ($result.status -eq 'PARTIAL') { exit 2 }
exit 0
