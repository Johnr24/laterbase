import os
import subprocess
from flask import Flask, render_template, request, flash, redirect, url_for

app = Flask(__name__)
app.secret_key = os.urandom(24) # Needed for flashing messages

BACKUP_DIR = "/backups"
# --- Database Connection Details (Read from Environment Variables) ---
# These will be needed for the restore operation
TARGET_DB_HOST = os.environ.get("TARGET_DB_HOST", "db") # Default to 'db' service name
TARGET_DB_PORT = os.environ.get("TARGET_DB_PORT", "5432")
TARGET_DB_USER = os.environ.get("TARGET_DB_USER", "postgres")
TARGET_DB_PASSWORD = os.environ.get("TARGET_DB_PASSWORD") # MUST be provided

DEFAULT_RESTORE_SUFFIX = "_restore"

def get_backup_files():
    """Scans the backup directory for .sql.gz files."""
    backups = []
    if not os.path.isdir(BACKUP_DIR):
        flash(f"Error: Backup directory '{BACKUP_DIR}' not found or not accessible.", "danger")
        return backups
    try:
        for filename in sorted(os.listdir(BACKUP_DIR), reverse=True):
            if filename.endswith(".sql.gz"):
                # Extract original DB name (assuming format DB_NAME_backup_TIMESTAMP.sql.gz)
                parts = filename.split('_backup_')
                original_db = parts[0] if len(parts) > 0 else "unknown_db"
                backups.append({"filename": filename, "original_db": original_db})
    except OSError as e:
        flash(f"Error reading backup directory '{BACKUP_DIR}': {e}", "danger")
    return backups

@app.route('/')
def index():
    """Displays the list of backups and the restore form."""
    backup_files = get_backup_files()
    return render_template('index.html', backups=backup_files, default_suffix=DEFAULT_RESTORE_SUFFIX)

@app.route('/restore', methods=['POST'])
def restore_backup():
    """Handles the restore request."""
    selected_backup = request.form.get('backup_file')
    restore_suffix = request.form.get('restore_suffix', DEFAULT_RESTORE_SUFFIX).strip()

    if not selected_backup:
        flash("Error: No backup file selected.", "danger")
        return redirect(url_for('index'))

    if not restore_suffix:
        restore_suffix = DEFAULT_RESTORE_SUFFIX # Ensure default if user enters empty string

    # Basic validation for suffix (prevent potentially harmful characters)
    if not restore_suffix.replace('_', '').isalnum():
         flash(f"Error: Invalid suffix '{restore_suffix}'. Only letters, numbers, and underscores are allowed.", "danger")
         return redirect(url_for('index'))

    backup_path = os.path.join(BACKUP_DIR, selected_backup)

    if not os.path.exists(backup_path):
        flash(f"Error: Selected backup file '{selected_backup}' not found.", "danger")
        return redirect(url_for('index'))

    # Extract original DB name again for safety
    parts = selected_backup.split('_backup_')
    original_db_name = parts[0] if len(parts) > 0 else None

    if not original_db_name:
        flash(f"Error: Could not determine original database name from '{selected_backup}'.", "danger")
        return redirect(url_for('index'))

    new_db_name = f"{original_db_name}{restore_suffix}"

    # --- Input Validation ---
    if not TARGET_DB_PASSWORD:
        flash("Error: TARGET_DB_PASSWORD environment variable is not set. Cannot connect to target database.", "danger")
        return redirect(url_for('index'))

    # --- Restore Process ---
    try:
        # 1. Create the new database
        flash(f"Attempting to create new database: '{new_db_name}' on host '{TARGET_DB_HOST}'...", "info")
        create_db_cmd = [
            "createdb",
            "-h", TARGET_DB_HOST,
            "-p", TARGET_DB_PORT,
            "-U", TARGET_DB_USER,
            new_db_name
        ]
        env = os.environ.copy()
        env['PGPASSWORD'] = TARGET_DB_PASSWORD
        # Use check_output to capture stderr on failure
        subprocess.check_output(create_db_cmd, stderr=subprocess.STDOUT, env=env)
        flash(f"Successfully created database '{new_db_name}'.", "success")

        # 2. Decompress and restore using psql
        flash(f"Attempting to restore '{selected_backup}' into '{new_db_name}'...", "info")
        # Command: gunzip < backup_path | psql -h host -p port -U user -d new_db_name
        # We use shell=True because of the pipe. Be cautious with user input (already validated suffix).
        restore_cmd_str = f"gunzip < \"{backup_path}\" | psql -h \"{TARGET_DB_HOST}\" -p \"{TARGET_DB_PORT}\" -U \"{TARGET_DB_USER}\" -d \"{new_db_name}\" --quiet"

        # Run the command
        # Use check_output to capture stderr on failure
        process = subprocess.run(restore_cmd_str, shell=True, capture_output=True, text=True, env=env)

        if process.returncode == 0:
             flash(f"Successfully restored backup '{selected_backup}' to database '{new_db_name}'.", "success")
        else:
             # Attempt to drop the partially created/restored DB on failure
             flash(f"Error during restore process (Exit Code: {process.returncode}). Attempting cleanup...", "danger")
             flash(f"Stderr: {process.stderr}", "warning")
             flash(f"Stdout: {process.stdout}", "warning")
             try:
                 drop_db_cmd = [
                     "dropdb", "--if-exists",
                     "-h", TARGET_DB_HOST,
                     "-p", TARGET_DB_PORT,
                     "-U", TARGET_DB_USER,
                     new_db_name
                 ]
                 subprocess.check_output(drop_db_cmd, stderr=subprocess.STDOUT, env=env)
                 flash(f"Cleaned up (dropped) database '{new_db_name}'.", "info")
             except subprocess.CalledProcessError as drop_e:
                 flash(f"Error during cleanup (dropping '{new_db_name}'): {drop_e.output.decode()}", "danger")

    except subprocess.CalledProcessError as e:
        flash(f"Error executing command: {e.cmd}", "danger")
        flash(f"Output: {e.output.decode()}", "warning")
        # If createdb failed, no need to drop
    except Exception as e:
        flash(f"An unexpected error occurred: {e}", "danger")

    return redirect(url_for('index'))


if __name__ == '__main__':
    # Use 0.0.0.0 to be accessible within Docker network
    app.run(host='0.0.0.0', port=5001, debug=True) # Use a different port like 5001