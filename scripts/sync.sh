#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Erreur: ce dossier n'est pas un dépôt Git."
  exit 1
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
msg="${1:-sync: $(date '+%Y-%m-%d %H:%M:%S') on $(hostname)}"

echo "[1/4] Fetch origin..."
git fetch origin

echo "[2/4] Pull rebase sur $branch..."
git pull --rebase --autostash origin "$branch"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "[3/4] Commit des changements locaux..."
  git add -A
  git commit -m "$msg"

  echo "[4/4] Push vers origin/$branch..."
  git push origin "$branch"
  echo "Synchronisation terminée (pull + commit + push)."
else
  echo "Aucun changement local. Dépôt déjà synchronisé après pull."
fi
