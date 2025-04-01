#!/bin/bash
set -e # Exit on error

CONFIG_FILE="/config/rclone.conf"
RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME}" # From env
SERVICE_ACCOUNT_CREDS="${RCLONE_SERVICE_ACCOUNT_CREDENTIALS}" # From env

# Ensure the config directory exists (though it should be mounted)
mkdir -p /config
# Ensure the config file exists, create if not (rclone needs it)
touch "$CONFIG_FILE"
# Logging will go to stdout/stderr now

# Check if remote name and credentials are provided
if [ -n "$RCLONE_REMOTE_NAME" ] && [ -n "$SERVICE_ACCOUNT_CREDS" ]; then
    echo "$(date): RCLONE_SERVICE_ACCOUNT_CREDENTIALS detected. Attempting to configure rclone remote '$RCLONE_REMOTE_NAME'." >&1

    # Check if the remote already exists in the config file
    # Use rclone config show to check for a specific remote
    if ! rclone config show "$RCLONE_REMOTE_NAME:" --config "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "$(date): Remote '$RCLONE_REMOTE_NAME' not found in $CONFIG_FILE. Creating..." >&1

        # Create the remote using service account credentials
        # Note: rclone expects the credentials directly, not a file path here
        rclone config create \
            "$RCLONE_REMOTE_NAME" \
            drive \
            scope=drive \
            service_account_credentials="$SERVICE_ACCOUNT_CREDS" \
            --config "$CONFIG_FILE"

        if [ $? -eq 0 ]; then
            echo "$(date): Successfully created rclone remote '$RCLONE_REMOTE_NAME' using Service Account." >&1
        else
            echo "$(date): Error: Failed to create rclone remote '$RCLONE_REMOTE_NAME' using Service Account. Check credentials and permissions." >&2
            # Consider exiting if creation fails: exit 1
        fi
    else
        echo "$(date): Rclone remote '$RCLONE_REMOTE_NAME' already exists in $CONFIG_FILE. Skipping creation." >&1
    fi
else
    echo "$(date): RCLONE_SERVICE_ACCOUNT_CREDENTIALS not set or RCLONE_REMOTE_NAME is empty. Skipping dynamic rclone configuration." >&1
fi

echo "$(date): Entrypoint configuration check finished." >&1
exit 0