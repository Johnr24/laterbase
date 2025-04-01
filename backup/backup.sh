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

# Rclone Configuration (Set these in docker-compose/.env)
RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME}" # e.g., mygdrive
RCLONE_REMOTE_PATH="${RCLONE_REMOTE_PATH}" # e.g., resolve_backups

# Backup Retention (Set in docker-compose/.env, defaults to 7 days)
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

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
if [ -z "$RCLONE_REMOTE_NAME" ]; then
  echo "$(date): Warning: RCLONE_REMOTE_NAME is not set. Backup will not be uploaded." >> /var/log/cron.log
  # Decide if this should be a fatal error (exit 1) or just a warning
fi
if [ -z "$RCLONE_REMOTE_PATH" ]; then
  echo "$(date): Warning: RCLONE_REMOTE_PATH is not set. Backup will not be uploaded." >> /var/log/cron.log
  # Decide if this should be a fatal error (exit 1) or just a warning
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

# --- Rclone Upload ---
if [ -n "$RCLONE_REMOTE_NAME" ] && [ -n "$RCLONE_REMOTE_PATH" ]; then
  RCLONE_DESTINATION="${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH}"
  echo "$(date): Uploading backup to ${RCLONE_DESTINATION}..." >> /var/log/cron.log
  rclone copy "$BACKUP_PATH" "$RCLONE_DESTINATION" --config /config/rclone.conf --log-file /var/log/cron.log --log-level INFO
  if [ $? -eq 0 ]; then
    echo "$(date): Upload successful: ${BACKUP_FILENAME} to ${RCLONE_DESTINATION}" >> /var/log/cron.log
  else
    echo "$(date): Error: Upload failed for ${BACKUP_FILENAME} to ${RCLONE_DESTINATION}." >> /var/log/cron.log
    # Decide if upload failure should be fatal (exit 1) or just logged
  fi
else
   echo "$(date): Skipping rclone upload as RCLONE_REMOTE_NAME or RCLONE_REMOTE_PATH is not set." >> /var/log/cron.log
fi

# --- Local Cleanup ---
echo "$(date): Cleaning up local backups older than ${BACKUP_RETENTION_DAYS} days in ${BACKUP_DIR}..." >> /var/log/cron.log
find "$BACKUP_DIR" -name "${DB_NAME}_backup_*.sql.gz" -type f -mtime "+${BACKUP_RETENTION_DAYS}" -print -delete >> /var/log/cron.log 2>&1

echo "$(date): Backup process finished." >> /var/log/cron.log

exit 0