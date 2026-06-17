#!/usr/bin/env sh
set -eu

CONFIG_FILE="${CONFIG_FILE:-/opt/complex_eeg/config/.env}"

if [ -f "$CONFIG_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  set +a
fi

BACKUP_ROOT="${BACKUP_ROOT:-${BACKUP_DIR:-/backup/complex_eeg}}"
LOG_DIR="${BACKUP_LOG_DIR:-${LOG_DIR:-/var/log/complex_eeg}/backup}"
DAILY_RETENTION_DAYS="${DAILY_RETENTION_DAYS:-14}"
WEEKLY_RETENTION_DAYS="${WEEKLY_RETENTION_DAYS:-56}"

mkdir -p "$LOG_DIR" \
         "$BACKUP_ROOT/postgres/daily" "$BACKUP_ROOT/postgres/weekly" \
         "$BACKUP_ROOT/files/daily" "$BACKUP_ROOT/files/weekly"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOG_DIR/cleanup_old_backups.log"

find "$BACKUP_ROOT/postgres/daily" -type f -name "*.sql.gz" \
     -mtime +"$DAILY_RETENTION_DAYS" -delete
find "$BACKUP_ROOT/files/daily" -type f -name "*.tar.gz" \
     -mtime +"$DAILY_RETENTION_DAYS" -delete
find "$BACKUP_ROOT/postgres/weekly" -type f -name "*.sql.gz" \
     -mtime +"$WEEKLY_RETENTION_DAYS" -delete
find "$BACKUP_ROOT/files/weekly" -type f -name "*.tar.gz" \
     -mtime +"$WEEKLY_RETENTION_DAYS" -delete

echo "$STAMP cleanup ok" >> "$LOG_FILE"
