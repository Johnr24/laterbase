#!/bin/bash
set -e

# Ensure PGDATA is set (should be inherited from Dockerfile)
echo "PGDATA is: $PGDATA"

# Check if primary host is provided
if [ -z "$PRIMARY_HOST" ]; then
  echo "Error: PRIMARY_HOST environment variable is not set."
  exit 1
fi

# Check if replication password is provided
if [ -z "$REPL_PASSWORD" ]; then
  echo "Error: REPL_PASSWORD environment variable is not set."
  exit 1
fi

# Clean the data directory (pg_basebackup requires it to be empty or non-existent)
# The entrypoint script might create it, so we ensure it's clean.
echo "Cleaning data directory $PGDATA..."
rm -rf "$PGDATA"/*
# Ensure the directory exists with correct permissions after cleaning
mkdir -p "$PGDATA"
chown postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"

# Perform the base backup from the primary server
# Using default user 'postgres' as discussed. Adjust -U if Resolve uses a different admin user.
# Password is provided via PGPASSWORD env var for pg_basebackup
echo "Starting base backup from $PRIMARY_HOST..."
PGPASSWORD="$REPL_PASSWORD" pg_basebackup \
    --host="$PRIMARY_HOST" \
    --port=5432 \
    --username=postgres \
    --pgdata="$PGDATA" \
    --wal-method=stream \
    --verbose \
    --progress

# Check if backup was successful
if [ $? -ne 0 ]; then
    echo "Error: pg_basebackup failed."
    exit 1
fi
echo "Base backup completed."

# Create standby signal file
touch "$PGDATA/standby.signal"
echo "Created standby.signal file."

# Configure primary connection info in postgresql.auto.conf
# This file is automatically included by postgresql.conf
# Using default user 'postgres'. Adjust if needed.
cat >> "$PGDATA/postgresql.auto.conf" <<EOF

# Added by setup_standby.sh for replication
primary_conninfo = 'host=$PRIMARY_HOST port=5432 user=postgres password=$REPL_PASSWORD sslmode=prefer sslcompression=0 gssencmode=prefer krbsrvname=postgres target_session_attrs=any'
primary_slot_name = 'laterbase_standby_slot' # Optional: Define a specific replication slot on primary
EOF

# Ensure correct permissions for config file
chown postgres:postgres "$PGDATA/postgresql.auto.conf"
chmod 600 "$PGDATA/postgresql.auto.conf"

echo "Standby configuration complete. PostgreSQL will start in standby mode."