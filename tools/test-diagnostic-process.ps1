# GPL-2.0-only. Real bounded child-process tests; no hardware or global policy changes.
$ErrorActionPreference='Stop'
$script:Checks=0
function Check-ProcessTest([bool]$Condition,[string]$Message) {
 $script:Checks++
 if(!$Condition){throw ('FAILED: '+$Message)}
}
$Application='caller-value';$ArgumentList=@('caller-arguments')
$TimeoutSeconds=99;$MaxOutputCharacters=33
. (Join-Path $PSScriptRoot 'diagnostic-process.ps1')
Check-ProcessTest ($Application -ceq 'caller-value' -and $ArgumentList[0] -ceq 'caller-arguments' -and
 $TimeoutSeconds -eq 99 -and $MaxOutputCharacters -eq 33) 'Import changed caller variables.'

$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('gpu-diagnostic-process-test-'+[guid]::NewGuid().ToString('N'))
$sentinel=$null;$pipeline=$null;$async=$null
$childSource=@'
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

internal static class DiagnosticProcessFixture {
    private static void Marker(string path) {
        using (Process own = Process.GetCurrentProcess()) {
            File.WriteAllText(path, own.Id.ToString(CultureInfo.InvariantCulture) + "|" +
                own.StartTime.ToUniversalTime().Ticks.ToString(CultureInfo.InvariantCulture));
        }
    }
    private static void Flood(TextWriter writer) {
        string block = new string('x', 4096);
        for (;;) { writer.Write(block); writer.Flush(); }
    }
    public static int Main(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        if (args.Length == 0 || args[0] == "empty") return 0;
        if (args[0] == "args") {
            for (int i = 1; i < args.Length; i++) {
                Console.Out.Write(args[i].Length.ToString(CultureInfo.InvariantCulture));
                Console.Out.Write(":");
                Console.Out.Write(args[i]);
                Console.Out.Write("\n");
            }
            return 0;
        }
        if (args[0] == "exit") {
            Console.Out.Write("bounded-out");
            Console.Error.Write("bounded-error");
            return 23;
        }
        if (args[0] == "stdin") {
            Console.Out.Write(Console.In.Read().ToString(CultureInfo.InvariantCulture));
            return 0;
        }
        if (args[0] == "count") {
            Console.Out.Write(new string('x', Int32.Parse(args[1], CultureInfo.InvariantCulture)));
            if (args.Length > 2)
                Console.Error.Write(new string('e', Int32.Parse(args[2], CultureInfo.InvariantCulture)));
            return 0;
        }
        if (args[0] == "both") {
            Thread output = new Thread(delegate() {
                string block = new string('o', 4096);
                for (int i = 0; i < 128; i++) Console.Out.Write(block);
                Console.Out.Flush();
            });
            Thread error = new Thread(delegate() {
                string block = new string('e', 4096);
                for (int i = 0; i < 128; i++) Console.Error.Write(block);
                Console.Error.Flush();
            });
            output.Start(); error.Start(); output.Join(); error.Join();
            return 0;
        }
        if (args[0] == "hang") {
            Marker(args[1]); Thread.Sleep(30000); return 0;
        }
        if (args[0] == "flood-out" || args[0] == "flood-error") {
            Marker(args[1]);
            Flood(args[0] == "flood-out" ? Console.Out : Console.Error);
        }
        return 64;
    }
}
'@
function Test-OwnedChildEnded([string]$MarkerPath) {
 Check-ProcessTest ([IO.File]::Exists($MarkerPath)) 'Test child did not reach its marker.'
 $fields=([IO.File]::ReadAllText($MarkerPath)).Split('|')
 $childId=0;[long]$startTicks=0
 Check-ProcessTest ($fields.Count -eq 2 -and [int]::TryParse($fields[0],[ref]$childId) -and
  [long]::TryParse($fields[1],[ref]$startTicks)) 'Invalid owned-child identity marker.'
 $observed=$null
 try {
  $observed=[Diagnostics.Process]::GetProcessById($childId)
  # A reused PID is not the child we created and must never be killed.
  Check-ProcessTest ($observed.HasExited -or
   $observed.StartTime.ToUniversalTime().Ticks -ne $startTicks) 'The invocation left its own child running.'
 } catch [ArgumentException] {
  Check-ProcessTest $true 'Owned child has exited.'
 } finally {
  if($observed){$observed.Dispose()}
 }
}
try {
 New-Item -ItemType Directory -Path $testRoot|Out-Null
 $fixtureFolder=Join-Path $testRoot 'child fixture with spaces'
 New-Item -ItemType Directory -Path $fixtureFolder|Out-Null
 $sourcePath=Join-Path $fixtureFolder 'fixture.cs'
 $childPath=Join-Path $fixtureFolder 'fixture child.exe'
 [IO.File]::WriteAllText($sourcePath,$childSource,(New-Object Text.UTF8Encoding($false)))
 # The Windows .NET Framework compiler builds this fixed test fixture only.
 # Runtime diagnostics do not compile code or require this compiler/Python.
 $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
 if(![IO.File]::Exists($compiler)){$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'}
 Check-ProcessTest ([IO.File]::Exists($compiler)) 'Windows .NET Framework compiler is required for this test fixture.'
 $built=Invoke-GuDiagnosticProcess -Application $compiler -ArgumentList @('/nologo','/target:exe',('/out:'+$childPath),$sourcePath) -TimeoutSeconds 30 -MaxOutputCharacters 65536
 Check-ProcessTest ($built.Status -eq 'completed' -and $built.ExitCode -eq 0 -and [IO.File]::Exists($childPath)) 'Trusted process fixture compilation failed.'
 $unicode=([string][char]0x03a9)+([string][char]0x6f22)+[char]::ConvertFromUtf32(0x1f9ea)
 $values=@('', 'plain', 'two words', $unicode, 'C:\tail\', 'C:\two words\', '"',
  'two"quotes"', '\\"', '\\', 'ends\\"', '$HOME; $(ignored) & | > < ^ %',
  ('tabs'+[char]9+'here'), ('line'+[char]10+'break'))
 $echo=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList (@('args')+$values) -TimeoutSeconds 5
 $expected=New-Object Text.StringBuilder
 foreach($value in $values){[void]$expected.Append($value.Length);[void]$expected.Append(':');[void]$expected.Append($value);[void]$expected.Append([char]10)}
 Check-ProcessTest ($echo.Status -eq 'completed' -and $echo.ExitCode -eq 0) 'Argument echo process failed.'
 Check-ProcessTest ($echo.StandardOutput -ceq $expected.ToString()) 'Windows argv did not preserve spaces, Unicode, empty strings, quotes, backslashes or metacharacters.'

 $nonzero=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('exit') -TimeoutSeconds 5
 Check-ProcessTest ($nonzero.Status -eq 'completed' -and $nonzero.ExitCode -eq 23) 'Nonzero exit code was lost.'
 Check-ProcessTest ($nonzero.StandardOutput -ceq 'bounded-out') 'Stderr contaminated the returned stdout.'
 $empty=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('empty') -TimeoutSeconds 5 -MaxOutputCharacters 0
 Check-ProcessTest ($empty.Status -eq 'completed' -and $empty.StandardOutput -is [string] -and $empty.StandardOutput.Length -eq 0) 'Empty bounded output was not retained.'
 $input=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('stdin') -TimeoutSeconds 5
 Check-ProcessTest ($input.Status -eq 'completed' -and $input.StandardOutput -ceq '-1') 'Child input was not closed.'

 $both=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('both') -TimeoutSeconds 10 -MaxOutputCharacters 1048576
 Check-ProcessTest ($both.Status -eq 'completed' -and $both.ExitCode -eq 0) 'Simultaneous stdout/stderr deadlocked or exceeded the exact bound.'
 Check-ProcessTest ($both.StandardOutput.Length -eq 524288 -and $both.StandardOutput.Trim([char]'o').Length -eq 0) 'Concurrent stderr changed stdout content.'
 $edge=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('count','73','27') -TimeoutSeconds 5 -MaxOutputCharacters 100
 Check-ProcessTest ($edge.Status -eq 'completed' -and $edge.StandardOutput.Length -eq 73) 'Exact combined output bound was refused.'
 $over=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('count','73','28') -TimeoutSeconds 5 -MaxOutputCharacters 100
 Check-ProcessTest ($over.Status -eq 'output-limit' -and $null -eq $over.StandardOutput -and $null -eq $over.ExitCode) 'Combined output excess was not refused without partial output.'

 # A separate child created by this test must survive another invocation's
 # deadline and output-limit cleanup; it is cleaned via this exact object.
 $sentinelMarker=Join-Path $testRoot 'sentinel.identity'
 $sentinelInfo=New-Object Diagnostics.ProcessStartInfo
 $sentinelInfo.FileName=$childPath
 $sentinelInfo.Arguments=(ConvertTo-GuProcessArgument 'hang')+' '+(ConvertTo-GuProcessArgument $sentinelMarker)
 $sentinelInfo.UseShellExecute=$false;$sentinelInfo.CreateNoWindow=$true
 $sentinel=New-Object Diagnostics.Process
 $sentinel.StartInfo=$sentinelInfo
 Check-ProcessTest ($sentinel.Start()) 'Independent test sentinel did not start.'

 $timeoutMarker=Join-Path $testRoot 'timeout.identity'
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $timed=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('hang',$timeoutMarker) -TimeoutSeconds 1 -MaxOutputCharacters 100
 $watch.Stop()
 Check-ProcessTest ($timed.Status -eq 'timeout' -and $null -eq $timed.StandardOutput -and $null -eq $timed.ExitCode) 'Deadline did not return a bounded timeout result.'
 Check-ProcessTest ($watch.Elapsed.TotalSeconds -lt 5) 'Deadline cleanup exceeded its bound.'
 Test-OwnedChildEnded $timeoutMarker
 Check-ProcessTest (!$sentinel.HasExited) 'Timeout cleanup killed the unrelated test sentinel.'

 foreach($mode in @('flood-out','flood-error')) {
  $marker=Join-Path $testRoot ($mode+'.identity')
  $limited=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @($mode,$marker) -TimeoutSeconds 5 -MaxOutputCharacters 8192
  Check-ProcessTest ($limited.Status -eq 'output-limit' -and $null -eq $limited.StandardOutput) 'A streaming pipe was not bounded.'
  Test-OwnedChildEnded $marker
  Check-ProcessTest (!$sentinel.HasExited) 'Output-limit cleanup killed the unrelated test sentinel.'
 }

 $missing=Invoke-GuDiagnosticProcess -Application (Join-Path $testRoot 'missing.exe') -ArgumentList @('ignored')
 Check-ProcessTest ($missing.Status -eq 'start-failed' -and $null -eq $missing.StandardOutput) 'Missing executable leaked an exception or output.'
 $relative=Invoke-GuDiagnosticProcess -Application 'fixture child.exe'
 Check-ProcessTest ($relative.Status -eq 'start-failed') 'Relative executable was accepted.'
 $invalidPath=Join-Path $testRoot 'not-an-executable.exe'
 [IO.File]::WriteAllText($invalidPath,'This is fixed test data, not an executable.')
 $invalid=Invoke-GuDiagnosticProcess -Application $invalidPath
 Check-ProcessTest ($invalid.Status -eq 'start-failed' -and $null -eq $invalid.ExitCode) 'Native start failure escaped the result contract.'
 $nul=Invoke-GuDiagnosticProcess -Application $childPath -ArgumentList @('args',('a'+[char]0+'b'))
 Check-ProcessTest ($nul.Status -eq 'start-failed') 'An embedded argument null was accepted.'

 # Stop a separate PowerShell runspace while its helper owns a live child.
 # Parameters are supplied through AddParameter, never interpolated into code.
 $cancelMarker=Join-Path $testRoot 'cancel.identity'
 $pipeline=[PowerShell]::Create()
 [void]$pipeline.AddScript(@'
param($ModulePath,$ChildPath,$MarkerPath)
. $ModulePath
Invoke-GuDiagnosticProcess -Application $ChildPath -ArgumentList @('hang',$MarkerPath) -TimeoutSeconds 20
'@).AddParameter('ModulePath',(Join-Path $PSScriptRoot 'diagnostic-process.ps1')).AddParameter('ChildPath',$childPath).AddParameter('MarkerPath',$cancelMarker)
 $async=$pipeline.BeginInvoke()
 $wait=[Diagnostics.Stopwatch]::StartNew()
 while(![IO.File]::Exists($cancelMarker) -and $wait.Elapsed.TotalSeconds -lt 5 -and !$async.IsCompleted){[Threading.Thread]::Sleep(20)}
 $wait.Stop()
 Check-ProcessTest ([IO.File]::Exists($cancelMarker)) 'Cancellation fixture did not start its owned child.'
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $pipeline.Stop()
 try{[void]$pipeline.EndInvoke($async)}catch [System.Management.Automation.PipelineStoppedException]{}
 $watch.Stop()
 Check-ProcessTest ($watch.Elapsed.TotalSeconds -lt 5) 'Cancellation cleanup did not finish promptly.'
 Test-OwnedChildEnded $cancelMarker
 Check-ProcessTest (!$sentinel.HasExited) 'Cancellation cleanup killed the unrelated test sentinel.'
 $pipeline.Dispose();$pipeline=$null
 Write-Host ('PASS: '+$script:Checks+' bounded native process assertions on PowerShell '+$PSVersionTable.PSVersion+'. Actual controlled children only.')
} finally {
 if($pipeline){try{$pipeline.Stop()}catch{};try{$pipeline.Dispose()}catch{}}
 if($sentinel){try{if(!$sentinel.HasExited){$sentinel.Kill();[void]$sentinel.WaitForExit(1000)}}catch{};$sentinel.Dispose()}
 if(Test-Path -LiteralPath $testRoot) {
  $resolved=[IO.Path]::GetFullPath((Get-Item -LiteralPath $testRoot).FullName)
  $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
  if(!$resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase) -or
     [IO.Path]::GetFileName($resolved) -notmatch '^gpu-diagnostic-process-test-[0-9a-f]{32}$'){throw 'Test cleanup boundary.'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
