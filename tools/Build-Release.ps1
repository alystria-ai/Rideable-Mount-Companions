param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskVersion=(Get-Content -LiteralPath (Join-Path $taskRoot 'VERSION') -Raw).Trim()
if($taskVersion -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
if(!$OutputDirectory){$OutputDirectory=Join-Path $taskRoot 'dist'}
$taskOut=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $taskOut -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskZip=Join-Path $taskOut "Rideable-Mount-Companions-$taskVersion.zip"
if(Test-Path -LiteralPath $taskZip){throw 'Output already exists. Choose another output directory.'}
$taskFiles=@('enabled.txt','mod_settings.ini','README.md','LICENSE')
foreach($taskFolder in @('Scripts','config','Localization')){
 $taskFiles+=@(Get-ChildItem -LiteralPath (Join-Path $taskRoot $taskFolder) -File -Recurse | ForEach-Object { $_.FullName.Substring($taskRoot.Length+1).Replace('\','/') })
}
$taskProfiles=Get-Content -LiteralPath (Join-Path $taskRoot 'config/creature-profiles.json') -Raw | ConvertFrom-Json
$taskRoster=Get-Content -LiteralPath (Join-Path $taskRoot 'characters/creatures.json') -Raw | ConvertFrom-Json
foreach($taskCreature in $taskRoster){
 $taskIds=$taskProfiles.profiles.($taskCreature.key)
 foreach($taskMode in @('english','multilingual')){if($taskIds.$taskMode -notmatch '^[a-f0-9-]{36}$'){throw ('Missing profile: '+$taskCreature.key)}}
}
$taskArchive=[IO.Compression.ZipFile]::Open($taskZip,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($taskFile in ($taskFiles | Sort-Object -Unique)){
  $taskPath=Join-Path $taskRoot $taskFile
  if((Get-Item -LiteralPath $taskPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked files are not allowed in the release'}
  $taskText=[IO.File]::ReadAllText($taskPath)
  if($taskText -match '(?i)(?:apiKey|api_key)\s*[=:]\s*["''][a-z0-9_-]{20,}|sk_car_[a-zA-Z0-9]+'){throw ('Credential-shaped value in '+$taskFile)}
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($taskArchive,$taskPath,('Dawnwalker/Binaries/Win64/ue4ss/Mods/CreatureCompanionMounts/'+$taskFile),[IO.Compression.CompressionLevel]::Optimal) | Out-Null
 }
 # Writable session folder must exist even when the source .gitkeep is absent.
 $taskArchive.CreateEntry('Dawnwalker/Binaries/Win64/ue4ss/Mods/CreatureCompanionMounts/runtime/') | Out-Null
} finally {$taskArchive.Dispose()}
$taskVerify=[IO.Compression.ZipFile]::OpenRead($taskZip)
try {
 $taskPrefix='Dawnwalker/Binaries/Win64/ue4ss/Mods/CreatureCompanionMounts/'
 foreach($taskRequired in @('enabled.txt','mod_settings.ini','Scripts/main.lua','Scripts/translations.lua','config/config.ini','config/creature-profiles.lua','config/creature-profiles.json')){
  if(!$taskVerify.GetEntry($taskPrefix+$taskRequired)){throw ('Missing release file: '+$taskRequired)}
 }
 if(@($taskVerify.Entries | Where-Object {$_.FullName -match '(?i)\.(exe|dll)$|\.git/|profile-state|convai-config|\.log$'}).Count){throw 'Unexpected runtime or private files in release'}
} finally {$taskVerify.Dispose()}
$taskHash=(Get-FileHash -LiteralPath $taskZip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $taskOut 'SHA256SUMS.txt'),"$taskHash  $([IO.Path]::GetFileName($taskZip))`n",[Text.UTF8Encoding]::new($false))
Write-Output ('Built and verified '+[IO.Path]::GetFileName($taskZip))
