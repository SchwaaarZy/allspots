param(
  [string]$Message
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

try {
  git rev-parse --is-inside-work-tree *> $null
} catch {
  Write-Error "Erreur: ce dossier n'est pas un dépôt Git."
  exit 1
}

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ([string]::IsNullOrWhiteSpace($Message)) {
  $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $hostName = $env:COMPUTERNAME
  $Message = "sync: $date on $hostName"
}

Write-Host "[1/4] Fetch origin..."
git fetch origin

Write-Host "[2/4] Pull rebase sur $branch..."
git pull --rebase --autostash origin $branch

$status = git status --porcelain
if (-not [string]::IsNullOrWhiteSpace($status)) {
  Write-Host "[3/4] Commit des changements locaux..."
  git add -A
  git commit -m "$Message"

  Write-Host "[4/4] Push vers origin/$branch..."
  git push origin $branch
  Write-Host "Synchronisation terminée (pull + commit + push)."
} else {
  Write-Host "Aucun changement local. Dépôt déjà synchronisé après pull."
}
