#!/usr/bin/env bash
# Daily backup of the development PostgreSQL database, encrypted at rest with
# openssl (AES-256-CBC + PBKDF2). The key file must live outside the backup
# directory and be readable only by its owner.
#
# Usage: ./script/db_backup.sh [retention_days]
#   BACKUP_ENCRYPTION=openssl|none   (default: openssl)
#   BACKUP_ENCRYPTION_KEY_FILE=path  (default: ~/.config/expense-tracker/backup.key)
set -euo pipefail
umask 077

RETENTION_DAYS="${1:-14}"
DB_NAME="${DATABASE_NAME:-expense_tracker_development}"
DB_HOST="${DATABASE_HOST:-127.0.0.1}"
DB_PORT="${DATABASE_PORT:-5432}"
DB_USER="${DATABASE_USERNAME:-${USER:-postgres}}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/expense-tracker}"
ENCRYPTION="${BACKUP_ENCRYPTION:-openssl}"
KEY_FILE="${BACKUP_ENCRYPTION_KEY_FILE:-$HOME/.config/expense-tracker/backup.key}"

if [ "$ENCRYPTION" = "openssl" ]; then
  if [ ! -r "$KEY_FILE" ]; then
    echo "Backup encryption key not found: $KEY_FILE" >&2
    echo "Create one with: mkdir -p \"$(dirname "$KEY_FILE")\" && openssl rand -base64 32 > \"$KEY_FILE\" && chmod 600 \"$KEY_FILE\"" >&2
    echo "Or set BACKUP_ENCRYPTION=none for an unencrypted backup." >&2
    exit 1
  fi

  KEY_MODE="$(stat -f '%Lp' "$KEY_FILE" 2>/dev/null || stat -c '%a' "$KEY_FILE" 2>/dev/null || echo unknown)"
  case "$KEY_MODE" in
    600|400) ;;
    *)
      echo "Backup key must not be readable by other users (mode 600 or 400, found $KEY_MODE)." >&2
      exit 1
      ;;
  esac

  command -v openssl >/dev/null 2>&1 || { echo "openssl is required for encrypted backups." >&2; exit 1; }
elif [ "$ENCRYPTION" != "none" ]; then
  echo "Unsupported BACKUP_ENCRYPTION: $ENCRYPTION (use openssl or none)." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
PLAIN="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump"

if [ "$ENCRYPTION" = "openssl" ]; then
  FILE="${PLAIN}.enc"
  TMP="$BACKUP_DIR/.${DB_NAME}_${TIMESTAMP}.dump.tmp"
else
  FILE="$PLAIN"
  TMP="$FILE"
fi

cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

echo "Backing up $DB_NAME -> $FILE"
PGPASSWORD="${DATABASE_PASSWORD:-}" pg_dump \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$TMP" \
  "$DB_NAME"

chmod 600 "$TMP"
trap - EXIT

if [ "$ENCRYPTION" = "openssl" ]; then
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
    -in "$TMP" -out "$FILE" -pass "file:$KEY_FILE"
  chmod 600 "$FILE"
  rm -f "$TMP"
fi

echo "Backup created: $FILE ($(du -h "$FILE" | cut -f1))"

# Prune old backups (both encrypted and plaintext).
find "$BACKUP_DIR" -name "${DB_NAME}_*.dump*" -type f -mtime +"$RETENTION_DAYS" -print -delete

echo "Done. Retention: ${RETENTION_DAYS} days."
