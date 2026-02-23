#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$PROJECT_ROOT/scripts/out"
TS="$(date +%Y%m%d_%H%M%S)"
PYTHON_BIN="python3"

if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
  PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
fi

mkdir -p "$OUT_DIR"

ALL_DEPARTMENTS=true
USE_COMMUNES=false
NO_DOMTOM=false
RADIUS=12000
SLEEP_SECONDS=2.5
COMMUNES_LIMIT=0
MIN_POPULATION=0
MAX_REQUESTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --department)
      ALL_DEPARTMENTS=false
      TARGET_DEPARTMENT="${2:?missing value for --department}"
      shift 2
      ;;
    --all-departments)
      ALL_DEPARTMENTS=true
      shift
      ;;
    --use-communes)
      USE_COMMUNES=true
      shift
      ;;
    --no-domtom)
      NO_DOMTOM=true
      shift
      ;;
    --radius)
      RADIUS="${2:?missing value for --radius}"
      shift 2
      ;;
    --sleep-seconds)
      SLEEP_SECONDS="${2:?missing value for --sleep-seconds}"
      shift 2
      ;;
    --communes-limit)
      COMMUNES_LIMIT="${2:?missing value for --communes-limit}"
      shift 2
      ;;
    --min-population)
      MIN_POPULATION="${2:?missing value for --min-population}"
      shift 2
      ;;
    --max-requests)
      MAX_REQUESTS="${2:?missing value for --max-requests}"
      shift 2
      ;;
    *)
      echo "Option non reconnue: $1"
      exit 1
      ;;
  esac
done

CATEGORIES=(culture nature experienceGustative histoire activites)
PART_FILES=()

for category in "${CATEGORIES[@]}"; do
  out_file="$OUT_DIR/pois_${category}_${TS}.json"
  PART_FILES+=("$out_file")

  cmd=("$PYTHON_BIN" "$PROJECT_ROOT/scripts/import_osm_france.py" --category "$category" --radius "$RADIUS" --sleep-seconds "$SLEEP_SECONDS" --output "$out_file")

  if [[ "$ALL_DEPARTMENTS" == true ]]; then
    cmd+=(--all-departments)
  else
    cmd+=(--department "$TARGET_DEPARTMENT")
  fi

  if [[ "$USE_COMMUNES" == true ]]; then
    cmd+=(--use-communes --communes-limit "$COMMUNES_LIMIT" --min-population "$MIN_POPULATION")
  fi

  if [[ "$NO_DOMTOM" == true ]]; then
    cmd+=(--no-domtom)
  fi

  if [[ "$MAX_REQUESTS" != "0" ]]; then
    cmd+=(--max-requests "$MAX_REQUESTS")
  fi

  echo "▶️ Import catégorie: $category"
  "${cmd[@]}"
done

MERGED_FILE="$OUT_DIR/pois_all_categories_${TS}.json"

"$PYTHON_BIN" - "$MERGED_FILE" "${PART_FILES[@]}" <<'PY'
import json
import sys
from pathlib import Path

def normalize(s):
    return ''.join(ch for ch in (s or '').lower().strip() if ch.isalnum())

merged = {}

for file_path in sys.argv[2:]:
    p = Path(file_path)
    if not p.exists():
        continue
    data = json.loads(p.read_text(encoding='utf-8'))
    for poi in data:
        osm_id = poi.get('osmId')
        if osm_id is not None:
            key = f"osm:{osm_id}"
        else:
            lat = poi.get('lat')
            lng = poi.get('lng')
            if lat is None or lng is None:
                continue
            key = f"{normalize(poi.get('name'))}:{round(float(lat), 6)}:{round(float(lng), 6)}"
        merged[key] = poi

out = list(merged.values())
out_path = Path(sys.argv[1])
out_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
print(f"deduped={len(out)} file={out_path}")
PY

echo "✅ Fichier fusionné anti-doublons: $MERGED_FILE"
echo "🚀 Import Firestore: node scripts/import_to_firestore.js $MERGED_FILE"
