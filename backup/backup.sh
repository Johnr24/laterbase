#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Read connection details from environment variables
# Defaults are provided for port and user if not set
DB_HOST="${PRIMARY_HOST}"
DB_PORT="${PRIMARY_PORT:-5432}"
DB_USER="${PRIMARY_USER:-postgres}"
DB_NAMES_STR="${PRIMARY_DBS}" # Comma-separated list of DBs
# PGPASSWORD should be set as an environment variable in docker-compose

# Rclone Configuration (Set these in docker-compose/.env)
RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME}" # e.g., mygdrive
RCLONE_REMOTE_PATH="${RCLONE_REMOTE_PATH}" # e.g., resolve_backups

# Backup Retention (Set in docker-compose/.env, defaults to 7 days)
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Filename will be generated inside the loop for each DB

# --- Input Validation ---
if [ -z "$DB_HOST" ]; then
  echo "$(date): Error: PRIMARY_HOST environment variable is not set." >> /var/log/cron.log
  exit 1
fi
if [ -z "$DB_NAMES_STR" ]; then
  echo "$(date): Error: PRIMARY_DBS environment variable is not set (should be a comma-separated list)." >> /var/log/cron.log
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
# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Convert comma-separated string to an array
IFS=',' read -r -a DB_NAMES <<< "$DB_NAMES_STR"

# Loop through each database name
for DB_NAME in "${DB_NAMES[@]}"; do
  # Trim whitespace (just in case)
  DB_NAME=$(echo "$DB_NAME" | xargs)
  if [ -z "$DB_NAME" ]; then
      echo "$(date): Warning: Skipping empty database name in PRIMARY_DBS list." >> /var/log/cron.log
      continue # Skip to the next database name
  fi

  echo "$(date): --- Processing database: ${DB_NAME} ---" >> /var/log/cron.log

  # Generate timestamp and paths for this specific database
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  BACKUP_FILENAME="${DB_NAME}_backup_${TIMESTAMP}.sql.gz"
  BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

  echo "$(date): Starting backup of database '${DB_NAME}' from host '${DB_HOST}:${DB_PORT}' to ${BACKUP_PATH}" >> /var/log/cron.log

  # Perform the backup using pg_dump, compressing the output
  # Use --clean to add drop commands before create commands
  # Use --if-exists with --clean for safety
  pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" --clean --if-exists | gzip > "$BACKUP_PATH"

  # Check pg_dump exit status
  if [ $? -eq 0 ]; then
    echo "$(date): Backup successful for '${DB_NAME}': ${BACKUP_PATH}" >> /var/log/cron.log
  else
    echo "$(date): Error: Backup failed for database '${DB_NAME}'. Skipping further steps for this DB." >> /var/log/cron.log
    # Optional: remove potentially incomplete backup file
    rm -f "$BACKUP_PATH"
    # Continue to the next database instead of exiting the whole script
    continue
  fi

  # --- Rclone Upload ---
  if [ -n "$RCLONE_REMOTE_NAME" ] && [ -n "$RCLONE_REMOTE_PATH" ]; then
    RCLONE_DESTINATION="${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH}/${DB_NAME}" # Store in DB-specific subfolder
    echo "$(date): Uploading backup for '${DB_NAME}' to ${RCLONE_DESTINATION}..." >> /var/log/cron.log
    # Ensure the remote subdirectory exists (optional, depends on rclone/remote behavior)
    # rclone mkdir "$RCLONE_DESTINATION" --config /config/rclone.conf --log-file /var/log/cron.log --log-level INFO
    rclone copy "$BACKUP_PATH" "$RCLONE_DESTINATION/" --config /config/rclone.conf --log-file /var/log/cron.log --log-level INFO
    if [ $? -eq 0 ]; then
      echo "$(date): Upload successful for '${DB_NAME}': ${BACKUP_FILENAME} to ${RCLONE_DESTINATION}" >> /var/log/cron.log
    else
      echo "$(date): Error: Upload failed for '${DB_NAME}': ${BACKUP_FILENAME} to ${RCLONE_DESTINATION}." >> /var/log/cron.log
      # Decide if upload failure should be fatal or just logged for this DB
    fi
  else
     echo "$(date): Skipping rclone upload for '${DB_NAME}' as RCLONE_REMOTE_NAME or RCLONE_REMOTE_PATH is not set." >> /var/log/cron.log
  fi

  echo "$(date): --- Finished processing database: ${DB_NAME} ---" >> /var/log/cron.log

done # End of database loop

# --- Local Cleanup ---
echo "$(date): Cleaning up local backups older than ${BACKUP_RETENTION_DAYS} days in ${BACKUP_DIR}..." >> /var/log/cron.log
find "$BACKUP_DIR" -name "*_backup_*.sql.gz" -type f -mtime "+${BACKUP_RETENTION_DAYS}" -print -delete >> /var/log/cron.log 2>&1

echo "$(date): Backup process finished." >> /var/log/cron.log

exit 0