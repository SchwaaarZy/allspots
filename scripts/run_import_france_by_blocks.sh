#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$PROJECT_ROOT/scripts/out"
TS="$(date +%Y%m%d_%H%M%S)"

PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="python3"
fi

SLEEP_SECONDS="1.8"
RADIUS="12000"
INCLUDE_DOMTOM="true"
DRY_RUN="false"
MAX_REQUESTS="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sleep-seconds)
      SLEEP_SECONDS="${2:?missing value for --sleep-seconds}"
      shift 2
      ;;
    --radius)
      RADIUS="${2:?missing value for --radius}"
      shift 2
      ;;
    --no-domtom)
      INCLUDE_DOMTOM="false"
      shift
      ;;
    --max-requests)
      MAX_REQUESTS="${2:?missing value for --max-requests}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "Option non reconnue: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$OUT_DIR"

BLOCK1="ile_de_france hauts_de_france grand_est normandie centre_val_de_loire"
BLOCK2="bretagne pays_de_la_loire nouvelle_aquitaine"
BLOCK3="occitanie provence_alpes_cote_dazur auvergne_rhone_alpes bourgogne_franche_comte"
BLOCK4="corse"
if [[ "$INCLUDE_DOMTOM" == "true" ]]; then
  BLOCK4="$BLOCK4 dom_tom"
fi

BLOCKS=("$BLOCK1" "$BLOCK2" "$BLOCK3" "$BLOCK4")
PART_FILES=()

echo "🇫🇷 Import France par blocs"
echo "   Python: $PYTHON_BIN"
echo "   Sleep: $SLEEP_SECONDS"
echo "   Radius: $RADIUS"
echo "   DOM-TOM: $INCLUDE_DOMTOM"
echo "   Max requests: $MAX_REQUESTS"
echo

for i in "${!BLOCKS[@]}"; do
  block_index=$((i + 1))
  regions="${BLOCKS[$i]}"
  out_file="$OUT_DIR/pois_france_block${block_index}_${TS}.json"
  PART_FILES+=("$out_file")

  cmd=(
    "$PYTHON_BIN" "$PROJECT_ROOT/scripts/import_hybride.py"
    --osm-mode all-departments
    --regions
  )

  for region in $regions; do
    cmd+=("$region")
  done

  cmd+=(
    --categories all
    --skip-datagouv
    --skip-unesco
    --sleep-seconds "$SLEEP_SECONDS"
    --radius "$RADIUS"
    --output "$out_file"
  )

  if [[ "$MAX_REQUESTS" != "0" ]]; then
    cmd+=(--max-requests "$MAX_REQUESTS")
  fi

  echo "▶️ Bloc $block_index: $regions"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '   '
    printf '%q ' "${cmd[@]}"
    echo
  else
    "${cmd[@]}"
  fi
  echo
done

FINAL_FILE="$OUT_DIR/pois_france_complete_blocks_${TS}.json"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "🧪 Dry run terminé"
  echo "Fichier final prévu: $FINAL_FILE"
  exit 0
fi

"$PYTHON_BIN" - "$FINAL_FILE" "${PART_FILES[@]}" <<'PY'
import json
import sys
from pathlib import Path

def dedupe_key(poi):
    source = str(poi.get("source", "")).strip().lower()

    if source == "openstreetmap" and poi.get("osmId"):
        return f"osm:{poi['osmId']}"

    if source == "unesco" and poi.get("unescoId"):
        return f"unesco:{poi['unescoId']}"

    name = str(poi.get("name", "")).strip().lower()
    location = poi.get("location", {})
    lat = location.get("_latitude", poi.get("lat"))
    lng = location.get("_longitude", poi.get("lng"))

    try:
        if name and lat is not None and lng is not None:
            return f"name:{name}:{round(float(lat), 5)}:{round(float(lng), 5)}"
    except (TypeError, ValueError):
        return None

    return None

merged = {}
for file_path in sys.argv[2:]:
    p = Path(file_path)
    if not p.exists():
        continue
    data = json.loads(p.read_text(encoding="utf-8"))
    for poi in data:
        key = dedupe_key(poi)
        if key:
            merged[key] = poi

final = list(merged.values())
out_path = Path(sys.argv[1])
out_path.write_text(json.dumps(final, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"merged={len(final)} file={out_path}")
PY

echo "✅ Fusion finale terminée: $FINAL_FILE"
echo "🚀 Import Firestore: node scripts/import_to_firestore.js $FINAL_FILE"
