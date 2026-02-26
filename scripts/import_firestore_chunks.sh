#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CHUNKS_DIR="$PROJECT_ROOT/scripts/out/chunks"
PROJECT_ID="allspots-5872e"
START_INDEX="1"
PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="python3"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chunks-dir)
      CHUNKS_DIR="${2:?missing value for --chunks-dir}"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="${2:?missing value for --project-id}"
      shift 2
      ;;
    --start-index)
      START_INDEX="${2:?missing value for --start-index}"
      shift 2
      ;;
    *)
      echo "Option non reconnue: $1"
      exit 1
      ;;
  esac
done

if [[ ! -d "$CHUNKS_DIR" ]]; then
  echo "Dossier chunks introuvable: $CHUNKS_DIR"
  exit 1
fi

FILES=()
while IFS= read -r file; do
  FILES+=("$file")
done < <(find "$CHUNKS_DIR" -maxdepth 1 -type f -name '*.json' | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Aucun chunk JSON trouvé dans: $CHUNKS_DIR"
  exit 1
fi

LOG_FILE="$PROJECT_ROOT/scripts/out/import_firestore_chunks_$(date +%Y%m%d_%H%M%S).log"
echo "🧩 Import Firestore par chunks"
echo "   Chunks dir: $CHUNKS_DIR"
echo "   Start index: $START_INDEX"
echo "   Project ID: $PROJECT_ID"
echo "   Python: $PYTHON_BIN"
echo "   Log: $LOG_FILE"
echo

index=0
for file in "${FILES[@]}"; do
  index=$((index + 1))
  if (( index < START_INDEX )); then
    continue
  fi

  echo "▶️ Chunk #$index: $file" | tee -a "$LOG_FILE"
  if ! GOOGLE_CLOUD_PROJECT="$PROJECT_ID" "$PYTHON_BIN" "$PROJECT_ROOT/scripts/import_to_firestore.py" "$file" >> "$LOG_FILE" 2>&1; then
    echo "❌ Échec au chunk #$index: $file" | tee -a "$LOG_FILE"
    echo "💡 Reprise: bash scripts/import_firestore_chunks.sh --start-index $index" | tee -a "$LOG_FILE"
    exit 1
  fi
  echo "✅ Chunk #$index terminé" | tee -a "$LOG_FILE"
  echo | tee -a "$LOG_FILE"
done

echo "🎉 Tous les chunks ont été importés" | tee -a "$LOG_FILE"
