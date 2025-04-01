#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Read connection details from environment variables
# Defaults are provided for port and user if not set
DB_HOST="${PRIMARY_HOST}"
DB_PORT="${PRIMARY_PORT:-5432}"
DB_USER="${PRIMARY_USER:-postgres}"
DB_NAME="${PRIMARY_DB}" # This needs to be the actual Resolve DB name
# PGPASSWORD should be set as an environment variable in docker-compose

BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="${DB_NAME}_backup_${TIMESTAMP}.sql.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

# --- Input Validation ---
if [ -z "$DB_HOST" ]; then
  echo "$(date): Error: PRIMARY_HOST environment variable is not set." >> /var/log/cron.log
  exit 1
fi
if [ -z "$DB_NAME" ]; then
  echo "$(date): Error: PRIMARY_DB environment variable is not set (should be the Resolve DB name)." >> /var/log/cron.log
  exit 1
fi
if [ -z "$PGPASSWORD" ]; then
  echo "$(date): Error: PGPASSWORD environment variable is not set." >> /var/log/cron.log
  exit 1
fi

# --- Backup Execution ---
echo "$(date): Starting backup of database '${DB_NAME}' from host '${DB_HOST}:${DB_PORT}' to ${BACKUP_PATH}" >> /var/log/cron.log

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Perform the backup using pg_dump, compressing the output
# Use --clean to add drop commands before create commands
# Use --if-exists with --clean for safety
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" --clean --if-exists | gzip > "$BACKUP_PATH"

# Check pg_dump exit status
if [ $? -eq 0 ]; then
  echo "$(date): Backup successful: ${BACKUP_PATH}" >> /var/log/cron.log
else
  echo "$(date): Error: Backup failed for database '${DB_NAME}'." >> /var/log/cron.log
  # Optional: remove potentially incomplete backup file
  rm -f "$BACKUP_PATH"
  exit 1
fi

# --- Optional: Cleanup old backups (e.g., keep last 7 days) ---
# echo "$(date): Cleaning up backups older than 7 days..." >> /var/log/cron.log
# find "$BACKUP_DIR" -name "${DB_NAME}_backup_*.sql.gz" -type f -mtime +7 -delete

echo "$(date): Backup process finished." >> /var/log/cron.log

exit 0