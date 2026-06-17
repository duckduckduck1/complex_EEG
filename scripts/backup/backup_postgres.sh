#!/usr/bin/env sh
set -eu

APP_ROOT="${APP_ROOT:-/opt/complex_eeg/app}"
CONFIG_FILE="${CONFIG_FILE:-/opt/complex_eeg/config/.env}"

if [ -f "$CONFIG_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  set +a
fi

BACKUP_ROOT="${BACKUP_ROOT:-${BACKUP_DIR:-/backup/complex_eeg}}"
LOG_DIR="${BACKUP_LOG_DIR:-${LOG_DIR:-/var/log/complex_eeg}/backup}"
STATUS_DIR="${STATUS_DIR:-${BACKUP_STATUS_DIR:-$BACKUP_ROOT/status}}"
POSTGRES_USER="${POSTGRES_USER:-complex_eeg}"
POSTGRES_DB="${POSTGRES_DB:-complex_eeg}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_ROOT/postgres/daily/postgres_${STAMP}.sql.gz"
TMP="${OUT}.tmp"
TMP_SQL="${OUT%.gz}.tmp.sql"
LOG_FILE="$LOG_DIR/postgres_backup.log"
STATUS_FILE="$STATUS_DIR/postgres_backup.prom"

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "POSTGRES_PASSWORD is required" >&2
  exit 1
fi

mkdir -p "$BACKUP_ROOT/postgres/daily" "$BACKUP_ROOT/postgres/weekly" \
         "$BACKUP_ROOT/postgres/latest" "$LOG_DIR" "$STATUS_DIR"
cd "$APP_ROOT"

if docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
     pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$TMP_SQL" \
   && gzip -c "$TMP_SQL" > "$TMP"; then
  rm -f "$TMP_SQL"
  mv "$TMP" "$OUT"
  cp "$OUT" "$BACKUP_ROOT/postgres/latest/postgres_latest.sql.gz"
  if [ "$(date -u +%u)" = "7" ]; then
    cp "$OUT" "$BACKUP_ROOT/postgres/weekly/postgres_${STAMP}.sql.gz"
  fi
  SIZE="$(wc -c < "$OUT" | tr -d ' ')"
  TS="$(date -u +%s)"
  {
    echo "complex_eeg_postgres_backup_success 1"
    echo "complex_eeg_postgres_backup_last_success_timestamp $TS"
    echo "complex_eeg_postgres_backup_size_bytes $SIZE"
  } > "$STATUS_FILE"
  echo "$STAMP postgres backup ok: $OUT" >> "$LOG_FILE"
else
  rm -f "$TMP" "$TMP_SQL"
  echo "complex_eeg_postgres_backup_success 0" > "$STATUS_FILE"
  echo "$STAMP postgres backup failed" >> "$LOG_FILE"
  exit 1
fi
