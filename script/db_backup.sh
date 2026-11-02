#!/usr/bin/env bash
# Daily backup of the development PostgreSQL database.
# Usage: ./script/db_backup.sh [retention_days]
set -euo pipefail

RETENTION_DAYS="${1:-14}"
DB_NAME="${DATABASE_NAME:-expense_tracker_development}"
DB_HOST="${DATABASE_HOST:-127.0.0.1}"
DB_PORT="${DATABASE_PORT:-5432}"
DB_USER="${DATABASE_USERNAME:-${USER:-postgres}}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/expense-tracker}"

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump"

echo "Backing up $DB_NAME -> $FILE"
PGPASSWORD="${DATABASE_PASSWORD:-}" pg_dump \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$FILE" \
  "$DB_NAME"

echo "Backup created: $FILE ($(du -h "$FILE" | cut -f1))"

# Prune old backups
find "$BACKUP_DIR" -name "${DB_NAME}_*.dump" -type f -mtime +"$RETENTION_DAYS" -print -delete

echo "Done. Retention: ${RETENTION_DAYS} days."
