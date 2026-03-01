#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PROJECT_ID="${PROJECT_ID:-allspots-5872e}"
CHUNKS_DIR="${CHUNKS_DIR:-scripts/out/chunks_20260225_172834}"
START_INDEX="${START_INDEX:-5}"
CHECK_EVERY_SEC="${CHECK_EVERY_SEC:-120}"
IMPORT_RETRY_EVERY_SEC="${IMPORT_RETRY_EVERY_SEC:-900}"
CLEANUP_EVERY_SEC="${CLEANUP_EVERY_SEC:-600}"
IMPORT_BATCH_SIZE="${IMPORT_BATCH_SIZE:-20}"
IMPORT_BATCH_SLEEP="${IMPORT_BATCH_SLEEP:-6.0}"

mkdir -p scripts/out
MONITOR_LOG="scripts/out/monitor_import_cleanup_$(date +%Y%m%d_%H%M%S).log"
IMPORT_DONE_FLAG="scripts/out/.import_done_notified"
CLEANUP_DONE_FLAG="scripts/out/.cleanup_done_notified"

notify() {
  local title="$1"
  local message="$2"
  echo "[$(date '+%F %T')] NOTIFY | $title | $message" | tee -a "$MONITOR_LOG"
  osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1 || true
}

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$MONITOR_LOG"
}

latest_import_log() {
  ls -t scripts/out/import_firestore_chunks_*.log 2>/dev/null | head -n 1 || true
}

is_import_running() {
  pgrep -f "import_firestore_chunks.sh|import_to_firestore.py" >/dev/null 2>&1
}

import_is_done_from_log() {
  local log_file="$1"
  [[ -n "$log_file" ]] || return 1
  grep -q "🎉 Tous les chunks ont été importés" "$log_file"
}

start_import_attempt() {
  log "Démarrage tentative import (start-index=$START_INDEX, batch-size=$IMPORT_BATCH_SIZE, batch-sleep=$IMPORT_BATCH_SLEEP)"
  (
    cd "$PROJECT_ROOT"
    PYTHONUNBUFFERED=1 \
    FIRESTORE_BATCH_SIZE="$IMPORT_BATCH_SIZE" \
    FIRESTORE_BATCH_SLEEP="$IMPORT_BATCH_SLEEP" \
    bash scripts/import_firestore_chunks.sh \
      --chunks-dir "$CHUNKS_DIR" \
      --start-index "$START_INDEX" \
      --project-id "$PROJECT_ID"
  ) >> "$MONITOR_LOG" 2>&1 &
  local import_pid=$!
  log "Tentative import lancée (pid=$import_pid)"
}

run_cleanup_batch() {
  .venv/bin/python scripts/delete_generic_spots.py \
    --project-id "$PROJECT_ID" \
    --apply \
    --limit 120 \
    --query-limit 60 \
    --max-retries 2 \
    --base-delay 2 \
    --print-limit 20 \
    --backup scripts/out/delete_generic_spots_apply_last.json >> "$MONITOR_LOG" 2>&1 || true
}

count_generic_candidates() {
  local out
  out=$(
    .venv/bin/python scripts/delete_generic_spots.py \
      --project-id "$PROJECT_ID" \
      --query-limit 120 \
      --max-retries 2 \
      --base-delay 2 \
      --print-limit 5 2>>"$MONITOR_LOG" || true
  )

  local candidates
  candidates=$(printf "%s\n" "$out" | awk -F': ' '/Candidats/{print $2}' | tail -n 1 | tr -dc '0-9')
  if [[ -z "$candidates" ]]; then
    candidates="999999"
  fi
  echo "$candidates"
}

log "Monitor started | log=$MONITOR_LOG | check_every=${CHECK_EVERY_SEC}s"

cleanup_last_run_epoch=0
import_last_run_epoch=0

latest_log_on_start="$(latest_import_log)"
if [[ -f "$IMPORT_DONE_FLAG" ]] && ! import_is_done_from_log "$latest_log_on_start"; then
  rm -f "$IMPORT_DONE_FLAG"
fi

while true; do
  now_epoch=$(date +%s)

  log_file="$(latest_import_log)"
  if [[ ! -f "$IMPORT_DONE_FLAG" ]]; then
    if is_import_running; then
      log "Import en cours | log=${log_file:-none}"
    else
      if import_is_done_from_log "$log_file"; then
        notify "Allspots" "Import des spots terminé ✅"
        : > "$IMPORT_DONE_FLAG"
      else
        if (( now_epoch - import_last_run_epoch >= IMPORT_RETRY_EVERY_SEC )); then
          import_last_run_epoch=$now_epoch
          start_import_attempt
        else
          log "Import non terminé. Prochaine tentative auto dans $((IMPORT_RETRY_EVERY_SEC - (now_epoch - import_last_run_epoch)))s"
        fi
      fi
    fi
  fi

  if [[ -f "$IMPORT_DONE_FLAG" && ! -f "$CLEANUP_DONE_FLAG" ]]; then
    if (( now_epoch - cleanup_last_run_epoch >= CLEANUP_EVERY_SEC )); then
      cleanup_last_run_epoch=$now_epoch
      log "Lancement batch suppression spots génériques"
      run_cleanup_batch
      candidates="$(count_generic_candidates)"
      log "Candidats génériques restants: $candidates"

      if [[ "$candidates" == "0" ]]; then
        notify "Allspots" "Suppression POI sans nom / Autre terminée ✅"
        : > "$CLEANUP_DONE_FLAG"
      fi
    fi
  fi

  sleep "$CHECK_EVERY_SEC"
done
