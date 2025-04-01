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

# --- Dynamic Rclone Configuration Loop ---
echo "$(date): Starting dynamic rclone configuration..." >&1
N=1
while true; do
    # Construct variable names for the Nth remote
    name_var_name="RCLONE_REMOTE_${N}_NAME"
    type_var_name="RCLONE_REMOTE_${N}_TYPE"

    # Use indirect expansion to get the values
    remote_name="${!name_var_name}"
    remote_type="${!type_var_name}"

    # If NAME is not set, we've processed all defined remotes
    if [ -z "$remote_name" ]; then
        echo "$(date): No more RCLONE_REMOTE_${N}_NAME found. Configuration loop finished." >&1
        break
    fi

    # TYPE is mandatory if NAME is set
    if [ -z "$remote_type" ]; then
        echo "$(date): Error: RCLONE_REMOTE_${N}_NAME ('$remote_name') is set, but RCLONE_REMOTE_${N}_TYPE is missing. Skipping remote ${N}." >&2
        N=$((N + 1))
        continue
    fi

    echo "$(date): Processing remote ${N}: Name='$remote_name', Type='$remote_type'" >&1

    # Check if the remote already exists
    if rclone config show "$remote_name:" --config "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "$(date): Remote '$remote_name' already exists in $CONFIG_FILE. Skipping creation." >&1
    else
        # Remote does not exist, proceed with creation
        echo "$(date): Remote '$remote_name' not found in $CONFIG_FILE. Creating..." >&1
        declare -a rclone_params=() # Use an array for parameters

        # Find all parameters for the current remote N
        param_prefix="RCLONE_REMOTE_${N}_PARAM_"
        # Use process substitution with env and grep for portability
        while IFS='=' read -r env_var_full env_var_value; do
            if [ -n "$env_var_value" ]; then # Ensure value is not empty
                # Extract the rclone key part (e.g., SERVICE_ACCOUNT_CREDENTIALS)
                rclone_key_upper=${env_var_full#"$param_prefix"}
                # Convert to lowercase for rclone config command
                rclone_key_lower=$(echo "$rclone_key_upper" | tr '[:upper:]' '[:lower:]')
                # Add the key=value pair to the array
                rclone_params+=("${rclone_key_lower}=${env_var_value}")
            fi
        done < <(env | grep "^${param_prefix}")

        # Check if any parameters were found
        if [ ${#rclone_params[@]} -eq 0 ]; then
            echo "$(date): Warning: No parameters (RCLONE_REMOTE_${N}_PARAM_*) found for remote '$remote_name'. Creating with type only." >&2
        fi

        # Construct and execute the command
        echo "$(date): Running: rclone config create \"$remote_name\" \"$remote_type\" [params...] --config \"$CONFIG_FILE\"" >&1
        rclone config create \
            "$remote_name" \
            "$remote_type" \
            "${rclone_params[@]}" \
            --config "$CONFIG_FILE"

        # Check exit status
        if [ $? -eq 0 ]; then
            echo "$(date): Successfully created rclone remote '$remote_name' (type: $remote_type)." >&1
        else
            echo "$(date): Error: Failed to create rclone remote '$remote_name' (type: $remote_type). Check parameters and permissions." >&2
            # Consider exiting if creation fails: exit 1
        fi
    fi # End if remote exists check

    # Move to the next potential remote
    N=$((N + 1))
done

echo "$(date): Entrypoint configuration check finished." >&1
exit 0