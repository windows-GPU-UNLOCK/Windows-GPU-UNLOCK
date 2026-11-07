# Pure policy mocks. Never queries firmware, stages media or changes settings.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-graph.ps1')
Assert-GraphUnsignedBootPolicy $false
$cases=@(
 [pscustomobject]@{Value=$true},[pscustomobject]@{Value=$null},
 [pscustomobject]@{Value=0},[pscustomobject]@{Value=1},
 [pscustomobject]@{Value='False'},[pscustomobject]@{Value='True'},
 [pscustomobject]@{Value=''},[pscustomobject]@{Value=@()},
 [pscustomobject]@{Value=@($false)},[pscustomobject]@{Value=@($false,$true)},
 [pscustomobject]@{Value=[pscustomobject]@{State=$false}}
)
foreach($case in $cases){
 $refused=$false
 try{Assert-GraphUnsignedBootPolicy $case.Value}catch{$refused=$true}
 if(!$refused){throw 'Unverified policy value admitted. Stop; no hardware retry.'}
}
# Real preparation uses the same strict function before build and staging.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'prepare-graph.ps1'),[ref]$null,[ref]$null)
$calls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Assert-GraphUnsignedBootPolicy'},$true))
if($calls.Count -ne 2){throw 'Preparation policy checkpoints changed; review source.'}
$parent=[Environment]::GetFolderPath('MyDocuments');if(!$parent){throw 'Documents unavailable.'}
$folder=Join-Path $parent ('GPU-Unlock-Boot-Policy-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $folder|Out-Null
$report=[ordered]@{Test='graph-unsigned-policy-v1';Passed=$true;MockFalseAccepted=$true;UnverifiedCasesRefused=$cases.Count;PreparationCheckpoints=2;ActualFirmwarePolicyRead=$false;PolicyChanged=$false;HardwareAccess=$false;EfiExecuted=$false;WriteEligible=$false;EnabledSecureBootRouteProvided=$false}
$path=Join-Path $folder 'boot-policy.json'
$report|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('PASS: strict mock policy gates. Return only '+$path+'. Enabled/unknown firmware policy still stops; no settings change or EFI run.')
