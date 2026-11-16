# Collection host helpers only. No install, PATH/settings edits or hardware access.
function Resolve-GuPythonApplication([string]$Name,[scriptblock]$Find={param($n) Get-Command $n -CommandType Application -All -ErrorAction Stop}){
 try{$commands=@(& $Find $Name)}catch{throw 'Python application unavailable. Use -Python with an existing known-good executable; do not install or change PATH.'}
 if(!$commands.Count){throw 'No Python application found.'}
 $source=$commands[0].Source
 if($source -isnot [string] -or !$source -or !(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Python resolution did not select one existing executable.'}
 if($source -match '(?i)[\\/]Microsoft[\\/]WindowsApps[\\/]python(?:3)?\.exe$'){throw 'Python is a Windows app alias. Use -Python with an existing known-good executable; do not install or change PATH.'}
 return [IO.Path]::GetFullPath($source)
}
function New-GuCollectionOutput([string]$Root,[ValidatePattern('^[A-Za-z0-9-]{1,64}$')][string]$Prefix,[string]$ForbiddenRoot){
 if(!$Root){$Root=[Environment]::GetFolderPath('MyDocuments')}
 try{
  if(!$Root){throw 'No default output root'}
  $parent=Get-Item -LiteralPath $Root -ErrorAction Stop
  if(!$parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Output root is not a regular directory'}
  $full=[IO.Path]::GetFullPath($parent.FullName).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
  if($ForbiddenRoot){
   $blocked=[IO.Path]::GetFullPath($ForbiddenRoot).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
   if($full.StartsWith($blocked,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must not be on capture media'}
  }
  $path=Join-Path $full ($Prefix+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Path $path -ErrorAction Stop|Out-Null
  return $path
 }catch{throw 'Local output folder could not be created. Collection only: use -OutputRoot with an existing writable local folder (for example your TEMP folder). Do not change permissions/settings or boot again.'}
}
