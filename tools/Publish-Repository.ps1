param([switch]$Publish)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskRepo='alystria-ai/Rideable-Mount-Companions'
if(!$Publish){Write-Output "Prepared repository: $taskRepo. No remote changes. Supply -Publish only when ready.";return}
Push-Location $taskRoot
try {
 if(git status --porcelain){throw 'Commit reviewed source before publishing'}
 gh repo view $taskRepo --json name 2>$null | Out-Null
 if($LASTEXITCODE){
  gh repo create $taskRepo --public --description 'Ride native creatures in The Blood of Dawnwalker, with companion commands, multilingual voices and adjustable riding.'
  if($LASTEXITCODE){throw 'Repository creation failed'}
 }
 $taskExpected="https://github.com/$taskRepo.git"
 $taskRemote=git remote get-url origin 2>$null
 if($LASTEXITCODE){git remote add origin $taskExpected}
 elseif($taskRemote -ne $taskExpected){throw 'Origin does not match the intended repository'}
 git push -u origin HEAD:main
 if($LASTEXITCODE){throw 'Push failed'}
} finally {Pop-Location}
