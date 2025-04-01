#!/bin/bash

# Script to perform automatable primary PostgreSQL server preparation steps for Laterbase.
# WARNING: This script does NOT configure pg_hba.conf. That MUST be done manually.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# Default values - override using environment variables if needed
: "${PRIMARY_HOST?Need to set PRIMARY_HOST}"
: "${PRIMARY_PORT:=5432}"
: "${PRIMARY_USER:=postgres}"
: "${REPL_PASSWORD?Need to set REPL_PASSWORD}"
# Database name isn't strictly required for these commands, but psql needs one to connect.
# 'postgres' is usually a safe default.
: "${DB_FOR_CONNECT:=postgres}"
SLOT_NAME="laterbase_standby_slot"
# --- End Configuration ---

export PGPASSWORD="$REPL_PASSWORD"

echo "Attempting to connect to primary database at $PRIMARY_HOST:$PRIMARY_PORT as user $PRIMARY_USER..."
psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$PRIMARY_USER" -d "$DB_FOR_CONNECT" -c "SELECT version();" || { echo "Connection failed. Check PRIMARY_HOST, PRIMARY_PORT, PRIMARY_USER, REPL_PASSWORD, and network connectivity."; exit 1; }
echo "Connection successful."
echo ""

echo "1. Granting REPLICATION privilege to user '$PRIMARY_USER'..."
psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$PRIMARY_USER" -d "$DB_FOR_CONNECT" -c "ALTER USER \"${PRIMARY_USER}\" WITH REPLICATION;"
echo "   User '$PRIMARY_USER' granted REPLICATION privilege."
echo ""

echo "2. Creating physical replication slot '$SLOT_NAME'..."
# Check if slot exists first to avoid error if run multiple times
psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$PRIMARY_USER" -d "$DB_FOR_CONNECT" -tAc "SELECT slot_name FROM pg_replication_slots WHERE slot_name = '$SLOT_NAME';" | grep -q "$SLOT_NAME"
if [ $? -eq 0 ]; then
    echo "   Slot '$SLOT_NAME' already exists. Skipping creation."
else
    psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$PRIMARY_USER" -d "$DB_FOR_CONNECT" -c "SELECT pg_create_physical_replication_slot('$SLOT_NAME');"
    echo "   Slot '$SLOT_NAME' created."
fi
echo ""

echo "3. Attempting to reload PostgreSQL configuration via SQL..."
psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$PRIMARY_USER" -d "$DB_FOR_CONNECT" -c "SELECT pg_reload_conf();"
echo "   SQL command 'SELECT pg_reload_conf();' executed."
echo "   NOTE: This command might succeed but not apply pg_hba.conf changes, or it might fail if the user lacks privileges."
echo "   You may still need to manually reload/restart the primary PostgreSQL server after editing pg_hba.conf."
echo ""

echo "Primary DB Preparation Script Finished."
echo "IMPORTANT: You MUST still manually edit 'pg_hba.conf' on the primary server ($PRIMARY_HOST) to allow replication connections."
echo "           See README.md for manual instructions."

unset PGPASSWORD
exit 0