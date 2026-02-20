param(
  [string]$TaskName = "AllspotsAutoSync"
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$syncScript = Join-Path $repoRoot "scripts\sync.ps1"

if (-not (Test-Path $syncScript)) {
  Write-Error "Script introuvable: $syncScript"
  exit 1
}

$action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$syncScript`" -Message `"auto-sync windows (30 min)`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
$trigger.RepetitionInterval = New-TimeSpan -Minutes 30
$trigger.RepetitionDuration = New-TimeSpan -Days 3650

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Description "Synchronise automatiquement le repo allspots toutes les 30 minutes" `
  -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host "Auto-sync Windows activé (toutes les 30 minutes)."
Write-Host "Tâche: $TaskName"
Write-Host "Script: $syncScript"
Write-Host "Vérifier: Get-ScheduledTask -TaskName $TaskName"
