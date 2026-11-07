# Packaged byte/source/scope refusals only; no EFI execution.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-graph.ps1')
. (Join-Path $PSScriptRoot 'graph-fixture.ps1')
function Reject([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};if(!$failed){throw 'Expected fixture refusal absent'}}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$bytes=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'fixtures/graph-only.fixture'))
$m=Get-Content (Join-Path $PSScriptRoot 'fixtures/graph-only.manifest.json') -Raw|ConvertFrom-Json
$null=Assert-GraphFixture $bytes $m $repo
$bad=[byte[]]$bytes.Clone();$bad[0]=$bad[0] -bxor 1;Reject {Assert-GraphFixture $bad $m $repo}
$copy=$m|ConvertTo-Json -Depth 8|ConvertFrom-Json;$copy.CanUnlock=$true;Reject {Assert-GraphFixture $bytes $copy $repo}
$copy=$m|ConvertTo-Json -Depth 8|ConvertFrom-Json;$copy.FixtureOnly=$false;Reject {Assert-GraphFixture $bytes $copy $repo}
$copy=$m|ConvertTo-Json -Depth 8|ConvertFrom-Json;$copy.Sources[0].Sha256='0'*64;Reject {Assert-GraphFixture $bytes $copy $repo}
$copy=$m|ConvertTo-Json -Depth 8|ConvertFrom-Json;$copy.Sources[0].Path='../private';Reject {Assert-GraphFixture $bytes $copy $repo}
$copy=$m|ConvertTo-Json -Depth 8|ConvertFrom-Json;$copy.Sources[1]=$copy.Sources[0];Reject {Assert-GraphFixture $bytes $copy $repo}
Write-Host 'PASS: packaged fixture bytes, scope, source digest, traversal and duplicate-source refusals. No EFI execution.'
