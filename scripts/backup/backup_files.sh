#!/usr/bin/env sh
set -eu

CONFIG_FILE="${CONFIG_FILE:-/opt/complex_eeg/config/.env}"

if [ -f "$CONFIG_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  set +a
fi

DATA_ROOT="${DATA_ROOT:-/srv/complex_eeg}"
BACKUP_ROOT="${BACKUP_ROOT:-${BACKUP_DIR:-/backup/complex_eeg}}"
LOG_DIR="${BACKUP_LOG_DIR:-${LOG_DIR:-/var/log/complex_eeg}/backup}"
STATUS_DIR="${STATUS_DIR:-${BACKUP_STATUS_DIR:-$BACKUP_ROOT/status}}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_ROOT/files/daily/files_${STAMP}.tar.gz"
TMP="${OUT}.tmp"
LOG_FILE="$LOG_DIR/files_backup.log"
STATUS_FILE="$STATUS_DIR/files_backup.prom"

mkdir -p "$BACKUP_ROOT/files/daily" "$BACKUP_ROOT/files/weekly" \
         "$BACKUP_ROOT/files/latest" "$LOG_DIR" "$STATUS_DIR"
mkdir -p "$DATA_ROOT/experiments" "$DATA_ROOT/pipeline_results"

if tar -czf "$TMP" -C "$DATA_ROOT" experiments pipeline_results; then
  mv "$TMP" "$OUT"
  cp "$OUT" "$BACKUP_ROOT/files/latest/files_latest.tar.gz"
  if [ "$(date -u +%u)" = "7" ]; then
    cp "$OUT" "$BACKUP_ROOT/files/weekly/files_${STAMP}.tar.gz"
  fi
  SIZE="$(wc -c < "$OUT" | tr -d ' ')"
  TS="$(date -u +%s)"
  {
    echo "complex_eeg_files_backup_success 1"
    echo "complex_eeg_files_backup_last_success_timestamp $TS"
    echo "complex_eeg_files_backup_size_bytes $SIZE"
  } > "$STATUS_FILE"
  echo "$STAMP files backup ok: $OUT" >> "$LOG_FILE"
else
  rm -f "$TMP"
  echo "complex_eeg_files_backup_success 0" > "$STATUS_FILE"
  echo "$STAMP files backup failed" >> "$LOG_FILE"
  exit 1
fi
