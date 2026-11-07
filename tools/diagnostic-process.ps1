# GPL-2.0-only. Bounded native process invocation; imports perform no work.
# Callers validate which executable to run. This helper never invokes a shell.
# Arguments follow Microsoft's documented C-runtime argv quoting rules:
# https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments
function ConvertTo-GuProcessArgument {
 [CmdletBinding()]
 param([AllowEmptyString()][AllowNull()][string]$Value)
 $quoted=New-Object System.Text.StringBuilder
 [void]$quoted.Append([char]34)
 $slashes=0
 foreach($character in ([string]$Value).ToCharArray()) {
  if($character -eq [char]92){$slashes++;continue}
  if($character -eq [char]34) {
   [void]$quoted.Append([char]92,($slashes*2+1))
   [void]$quoted.Append([char]34)
  } else {
   if($slashes){[void]$quoted.Append([char]92,$slashes)}
   [void]$quoted.Append($character)
  }
  $slashes=0
 }
 if($slashes){[void]$quoted.Append([char]92,($slashes*2))}
 [void]$quoted.Append([char]34)
 return $quoted.ToString()
}

function Invoke-GuDiagnosticProcess {
 <#
 .SYNOPSIS
 Runs one validated executable with bounded time and combined output.
 .DESCRIPTION
 UTF-8 stdout/stderr are drained concurrently in fixed-size asynchronous chunks.
 MaxOutputCharacters counts both streams. Only completed bounded stdout is
 returned; stderr and partial output are never returned. Standard input is EOF.
 Cancellation propagates after finally cleanup. Only this Process instance is
 killed, never a process name, PID search, process tree, or unrelated process.
 #>
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$Application,
  [AllowEmptyCollection()][AllowEmptyString()][AllowNull()][string[]]$ArgumentList=@(),
  [double]$TimeoutSeconds=120,
  [long]$MaxOutputCharacters=16777216
 )
 $status='start-failed';$exitCode=$null;$standardOutput=$null
 $process=$null;$started=$false;$timer=$null
 $stdout=$null;$stderr=$null;$stdin=$null
 try {
  # A drive-relative path such as C:python.exe is not an absolute executable.
  if($Application -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+\\[^\\/]+\\)' -or
     $Application.IndexOf([char]0) -ge 0 -or ![IO.File]::Exists($Application) -or
     [double]::IsNaN($TimeoutSeconds) -or [double]::IsInfinity($TimeoutSeconds) -or
     $TimeoutSeconds -lt 0.05 -or $TimeoutSeconds -gt 3600 -or
     $MaxOutputCharacters -lt 0 -or $MaxOutputCharacters -gt 67108864) {
   throw 'Invalid process invocation bounds or executable.'
  }
  $arguments=New-Object System.Collections.Generic.List[string]
  foreach($argument in $ArgumentList) {
   if(([string]$argument).IndexOf([char]0) -ge 0){throw 'An argument contains a null character.'}
   $arguments.Add((ConvertTo-GuProcessArgument $argument))
  }
  $start=New-Object System.Diagnostics.ProcessStartInfo
  $start.FileName=[IO.Path]::GetFullPath($Application)
  $start.Arguments=[string]::Join(' ',$arguments.ToArray())
  $start.UseShellExecute=$false
  $start.CreateNoWindow=$true
  $start.RedirectStandardInput=$true
  $start.RedirectStandardOutput=$true
  $start.RedirectStandardError=$true
  # The JSON analyzer emits ASCII; UTF-8 also preserves other diagnostic text.
  $encoding=New-Object System.Text.UTF8Encoding($false,$false)
  $start.StandardOutputEncoding=$encoding
  $start.StandardErrorEncoding=$encoding
  $process=New-Object System.Diagnostics.Process
  $process.StartInfo=$start
  $timer=[Diagnostics.Stopwatch]::StartNew()
  if(!$process.Start()){throw 'Process did not start.'}
  $started=$true
  $stdin=$process.StandardInput
  $stdin.Close()
  $stdout=$process.StandardOutput;$stderr=$process.StandardError
  $outBuffer=New-Object char[] 4096
  $errBuffer=New-Object char[] 4096
  $outTask=$stdout.ReadAsync($outBuffer,0,$outBuffer.Length)
  $errTask=$stderr.ReadAsync($errBuffer,0,$errBuffer.Length)
  $outEnded=$false;$errEnded=$false
  [long]$total=0
  $captured=New-Object System.Text.StringBuilder
  while($true) {
   if($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds){$status='timeout';break}
   $progress=$false
   if(!$outEnded -and $outTask.IsCompleted) {
    $read=$outTask.GetAwaiter().GetResult()
    $progress=$true
    if($read -eq 0){$outEnded=$true}
    else {
     $total+=$read
     if($total -gt $MaxOutputCharacters){$status='output-limit';break}
     [void]$captured.Append($outBuffer,0,$read)
     $outTask=$stdout.ReadAsync($outBuffer,0,$outBuffer.Length)
    }
   }
   if(!$errEnded -and $errTask.IsCompleted) {
    $read=$errTask.GetAwaiter().GetResult()
    $progress=$true
    if($read -eq 0){$errEnded=$true}
    else {
     $total+=$read
     if($total -gt $MaxOutputCharacters){$status='output-limit';break}
     $errTask=$stderr.ReadAsync($errBuffer,0,$errBuffer.Length)
    }
   }
   if($outEnded -and $errEnded -and $process.HasExited) {
    $status='completed';$exitCode=$process.ExitCode
    $standardOutput=$captured.ToString()
    break
   }
   if(!$progress){[Threading.Thread]::Sleep(10)}
  }
 } catch [System.Management.Automation.PipelineStoppedException] {
  throw
 } catch {
  # Do not return exception text, executable paths, stderr, or partial JSON.
  $status='start-failed';$exitCode=$null;$standardOutput=$null
 } finally {
  if($timer){$timer.Stop()}
  if($process) {
   if($started) {
    try {
     if(!$process.HasExited){$process.Kill();[void]$process.WaitForExit(1000)}
    } catch {}
   }
   # Never call parameterless WaitForExit/ReadToEnd: inherited pipe handles or
   # a stalled child must not extend the deadline indefinitely.
   foreach($stream in @($stdin,$stdout,$stderr)) {
    if($stream){try{$stream.Dispose()}catch{}}
   }
   try{$process.Dispose()}catch{}
  }
 }
 return [pscustomobject]@{Status=$status;ExitCode=$exitCode;StandardOutput=$standardOutput}
}
