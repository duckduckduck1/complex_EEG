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
RESTORE_TEST_DIR="${RESTORE_TEST_DIR:-$BACKUP_ROOT/restore_tests}"
LOG_DIR="${BACKUP_LOG_DIR:-${LOG_DIR:-/var/log/complex_eeg}/backup}"
POSTGRES_USER="${POSTGRES_USER:-complex_eeg}"
POSTGRES_DB="${POSTGRES_DB:-complex_eeg}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOG_DIR/restore_check.log"
TEST_DB="restore_test_$$"

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "POSTGRES_PASSWORD is required" >&2
  exit 1
fi

mkdir -p "$RESTORE_TEST_DIR" "$LOG_DIR"
cd "$APP_ROOT"

POSTGRES_LATEST="$BACKUP_ROOT/postgres/latest/postgres_latest.sql.gz"
FILES_LATEST="$BACKUP_ROOT/files/latest/files_latest.tar.gz"

# Verify archives exist and are non-empty
test -s "$POSTGRES_LATEST"
test -s "$FILES_LATEST"

# Verify gzip and tar integrity
gzip -t "$POSTGRES_LATEST"
tar -tzf "$FILES_LATEST" > /dev/null

# Restore PostgreSQL dump into a temporary database
docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
  psql -U "$POSTGRES_USER" -c "CREATE DATABASE $TEST_DB;"
if zcat "$POSTGRES_LATEST" | docker compose exec -T \
     -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
     psql -U "$POSTGRES_USER" -d "$TEST_DB" -q; then
  docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
    psql -U "$POSTGRES_USER" -c "DROP DATABASE $TEST_DB;" || true
  echo "$STAMP restore check ok" >> "$LOG_FILE"
else
  docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
    psql -U "$POSTGRES_USER" -c "DROP DATABASE IF EXISTS $TEST_DB;" || true
  echo "$STAMP restore check FAILED" >> "$LOG_FILE"
  exit 1
fi
