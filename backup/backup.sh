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

# Backup Retention (Set in docker-compose/.env, defaults to 7 days)
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Filename will be generated inside the loop for each DB

# --- Input Validation ---
# Errors go to stderr (>&2)
if [ -z "$DB_HOST" ]; then
  echo "$(date): Error: PRIMARY_HOST environment variable is not set." >&2
  exit 1
fi
if [ -z "$DB_NAMES_STR" ]; then
  echo "$(date): Error: PRIMARY_DBS environment variable is not set (should be a comma-separated list)." >&2
  exit 1
fi
if [ -z "$PGPASSWORD" ]; then
  echo "$(date): Error: PGPASSWORD environment variable is not set." >&2
  exit 1
fi
# Rclone checks removed

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
      echo "$(date): Warning: Skipping empty database name in PRIMARY_DBS list." >&2
      continue # Skip to the next database name
  fi

  echo "$(date): --- Processing database: ${DB_NAME} ---"

  # Generate timestamp and paths for this specific database
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  BACKUP_FILENAME="${DB_NAME}_backup_${TIMESTAMP}.sql.gz"
  BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

  echo "$(date): Starting backup of database '${DB_NAME}' from host '${DB_HOST}:${DB_PORT}' to ${BACKUP_PATH}"

  # Perform the backup using pg_dump, compressing the output and sending stderr to script's stderr
  # Use --clean to add drop commands before create commands
  # Use --if-exists with --clean for safety
  pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" --clean --if-exists 2>&1 | gzip > "$BACKUP_PATH"
  PGDUMP_EXIT_CODE=${PIPESTATUS[0]} # Capture exit code of pg_dump (first command in pipe)

  # Check pg_dump exit status
  if [ $PGDUMP_EXIT_CODE -eq 0 ]; then
    echo "$(date): Backup successful for '${DB_NAME}': ${BACKUP_PATH}"
  else
    # Error message goes to stderr
    echo "$(date): Error: Backup failed for database '${DB_NAME}' with exit code ${PGDUMP_EXIT_CODE}. See logs above for details. Skipping further steps for this DB." >&2
    # Optional: remove potentially incomplete backup file
    rm -f "$BACKUP_PATH"
    # Continue to the next database instead of exiting the whole script
    continue
  fi

  # --- Upload handled by Duplicati ---
  # The backup file ${BACKUP_PATH} is now ready in the /backups volume.
  # Duplicati server (running in the same container) should be configured
  # to monitor the /backups directory and upload changes to the remote destination.
  echo "$(date): --- Finished processing database: ${DB_NAME} ---"

done # End of database loop

# --- Local Cleanup ---
echo "$(date): Cleaning up local backups older than ${BACKUP_RETENTION_DAYS} days in ${BACKUP_DIR}..."
# Let find output (list of deleted files) and errors go to stdout/stderr
find "$BACKUP_DIR" -name "*_backup_*.sql.gz" -type f -mtime "+${BACKUP_RETENTION_DAYS}" -print -delete

echo "$(date): Backup process finished."

exit 0