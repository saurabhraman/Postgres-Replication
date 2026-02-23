#!/bin/bash
# scripts/backup.sh
# Full database backup using pg_dump, compressed with gzip.
# Environment variables (set in docker-compose.yml):
#   DB_HOST, DB_USER, DB_NAME, PGPASSWORD, BACKUP_RETAIN_DAYS

set -euo pipefail

BACKUP_DIR="/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/${DB_NAME:-mfi_banking}_$DATE.sql.gz"
RETAIN_DAYS="${BACKUP_RETAIN_DAYS:-7}"

echo "=== Backup started at $(date) ==="
echo "Host: ${DB_HOST:-db-primary} | Database: ${DB_NAME:-mfi_banking}"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Wait for primary to be ready
until pg_isready -h "${DB_HOST:-db-primary}" -U "${DB_USER:-postgres}" -q; do
    echo "Waiting for database to be ready..."
    sleep 2
done

# Perform dump
pg_dump \
    -h "${DB_HOST:-db-primary}" \
    -U "${DB_USER:-postgres}" \
    -d "${DB_NAME:-mfi_banking}" \
    --format=custom \
    --compress=6 \
    -f "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "Backup successful: $BACKUP_FILE ($BACKUP_SIZE)"

    # Delete backups older than retention period
    DELETED=$(find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$RETAIN_DAYS" -delete -print | wc -l)
    if [ "$DELETED" -gt 0 ]; then
        echo "Cleaned up $DELETED backup(s) older than $RETAIN_DAYS days"
    fi
else
    echo "ERROR: Backup failed!"
    exit 1
fi

echo "=== Backup completed at $(date) ==="
