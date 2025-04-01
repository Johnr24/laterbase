# Laterbase: DaVinci Resolve PostgreSQL Standby, Backup Agent, and pgAdmin Setup

Laterbase, sets up a Docker-based environment specifically designed for **DaVinci Resolve PostgreSQL databases**. It consists of:

1.  **PostgreSQL Standby Server:** Creates a hot standby replica of your primary DaVinci Resolve PostgreSQL database using streaming replication.
2.  **Hourly Backup Agent:** Performs hourly logical backups (`pg_dump`) of your primary DaVinci Resolve database, optionally uploads them to cloud storage using `rclone`, and manages local backup retention.
3.  **pgAdmin 4 UI:** Provides a web-based graphical interface for managing and monitoring both the primary DaVinci Resolve database and the standby replica.

<p align="center">
  <img src="readme/laterbase.gif" alt="Jonson From the Peepshow saying Screw it, Sort it Later Stick it on the Laterbase">
</p>

## Architecture Overview

This diagram shows how the Laterbase components interact with your primary DaVinci Resolve PostgreSQL database:

```mermaid
graph TD
    subgraph "DaVinci Resolve Host"
        PrimaryDB[(Primary PostgreSQL DB)]
        ReplicationSlot["Physical Replication Slot<br>(laterbase_standby_slot)"]
        PrimaryDB -- Manages --> ReplicationSlot
    end

    subgraph "Laterbase (Docker Host)"
        StandbyDB[("laterbase-standby<br>PostgreSQL Standby")]
        BackupAgent["laterbase-backup-agent<br>(Hourly pg_dump, rclone upload, retention)"]
        PgAdminUI[("laterbase-pgadmin<br>pgAdmin 4 UI")]
        BackupVolume["Local Backups backups"]
        RcloneConfigVolume[Rclone Config<br>./rclone_config]
    end

    subgraph "Cloud Storage (Optional)"
        CloudBackup{{Rclone Remote<br>e.g., S3, Google Drive}}
    end

    PrimaryDB -- Streaming Replication --> StandbyDB
    PrimaryDB -- pg_dump --> BackupAgent
    BackupAgent -- Writes .sql.gz --> BackupVolume
    BackupAgent -- Copies .sql.gz --> CloudBackup
    BackupAgent -- Reads Config --> RcloneConfigVolume
    PgAdminUI -- User Connects --> PrimaryDB
    PgAdminUI -- User Connects --> StandbyDB
    StandbyDB -- Uses --> ReplicationSlot

    style PrimaryDB fill:#071782,stroke:#333,stroke-width:2px
    style StandbyDB fill:#374ac4,stroke:#333,stroke-width:2px
    style BackupAgent fill:#6b0b9e,stroke:#333,stroke-width:2px
    style PgAdminUI fill:#0b9e92,stroke:#333,stroke-width:2px
    style ReplicationSlot fill:#359e0b,stroke:#333,stroke-width:1px
    style BackupVolume fill:#9e8f0b,stroke:#333,stroke-width:1px
    style RcloneConfigVolume fill:#b0a01c,stroke:#333,stroke-width:1px
    style CloudBackup fill:#1caab0,stroke:#333,stroke-width:2px
```

**Note on Physical Replication Slot:** A physical replication slot (`laterbase_standby_slot` in this setup) is a feature on the primary PostgreSQL server. It ensures that the primary server retains the necessary transaction logs (WAL segments) required by the standby server, even if the standby disconnects temporarily. This prevents the standby from falling too far behind and needing a full resynchronization.

## Configuration
1.  **`.env` File:**
    *   Open the `.env` file.
    *   Set `PRIMARY_HOST` to the hostname or IP address of your main **DaVinci Resolve** PostgreSQL server.
    *   Set `REPL_PASSWORD` to the password for the `postgres` user (or your designated replication user) on the primary DaVinci Resolve server.
    *   **Crucially:** Replace `YOUR_LATERBASE_PRIMARY_DB_NAME_HERE` with the **actual name** of your main **DaVinci Resolve** database on the primary server (e.g., `ResolveProjects`, for backups).
    *   Replace `YOUR_PGADMIN_EMAIL_HERE` with the email address you want to use for the pgAdmin login.
    *   Replace `YOUR_PGADMIN_PASSWORD_HERE` with the password you want for the pgAdmin login.
    *   Adjust `PRIMARY_PORT` or `PRIMARY_USER` if they differ from the defaults (5432, postgres).
    *   Optionally, uncomment and set `POSTGRES_USER`, `POSTGRES_DB`, or `PGDATA` under the "Standby Server Configuration" section to override the defaults used by the standby service.
    *   **Rclone Upload (Optional):**
        *   Set `RCLONE_REMOTE_NAME` to the name of the remote you have configured in your `rclone.conf` file (e.g., `mygdrive`, `s3remote`). Leave blank to disable uploads.
        *   Set `RCLONE_REMOTE_PATH` to the directory path within your rclone remote where backups should be stored (e.g., `resolve_backups/production`). Leave blank to disable uploads.
    *   **Backup Retention (Optional):**
        *   Set `BACKUP_RETENTION_DAYS` to the number of days you want to keep local backups in the `./backups` directory. Defaults to 7 if not set.

2.  **Primary PostgreSQL Server Preparation (`PRIMARY_HOST`):**

    *   **Ensure DaVinci Resolve Database is Accessible:** Make sure your DaVinci Resolve database is configured to allow network connections if Laterbase is running on a different machine. Check the DaVinci Resolve Project Server settings if applicable.
    *   **Primary Server Configuration Steps (macOS Example):**
        **VERY IMPORTANT:** Configuring the primary server involves **both** manual file editing and running an automated script. These steps **must** be completed on your **primary macOS server** (`PRIMARY_HOST`) *before* you attempt to start the main Laterbase Docker containers (`docker-compose up`). Laterbase only configures the standby replica; it does **not** automatically configure your primary server.

        **Step 1: Manually Edit `pg_hba.conf` (Requires `sudo` on Primary Server)**
            *   This step **must** be done manually on the primary server.
            *   Open `Terminal.app` on the primary Mac where DaVinci Resolve's PostgreSQL is running.
            *   **Find the `pg_hba.conf` file:** For a standard DaVinci Resolve installation on macOS, the path is usually:
                `/Library/Application Support/PostgreSQL/<VERSION>/data/pg_hba.conf`
                (Replace `<VERSION>` with your PostgreSQL version number, e.g., `13`. You can find it by running `ls "/Library/Application Support/PostgreSQL/"` in Terminal).
            *   **Edit the file:** Use `nano` with `sudo`:
                ```bash
                sudo nano "/Library/Application Support/PostgreSQL/<VERSION>/data/pg_hba.conf"
                ```
                (Again, replace `<VERSION>` with the correct number).
            *   **Add the replication line:** Add the following line to the end of the file. **Adjust the IP address/subnet (`192.168.1.0/24`)** to match the network of your Docker host running Laterbase, allowing it to connect. Use the correct `PRIMARY_USER` if it's not `postgres`.
                ```
                # Allow replication connections from the Laterbase Docker host
                host    replication     postgres        192.168.1.0/24         md5
                ```
            *   **Save and Exit:** Press `Ctrl+O`, then `Enter` to save. Press `Ctrl+X` to exit `nano`.

        **Step 2: Run the Preparation Script (Requires Docker & `.env` on Laterbase Host)**
            *   This script automates granting replication privileges, creating the replication slot, and attempting a configuration reload via SQL.
            *   Ensure your `.env` file in the Laterbase project directory is correctly configured with `PRIMARY_HOST`, `PRIMARY_PORT`, `PRIMARY_USER`, and `REPL_PASSWORD`.
            *   From the Laterbase project directory (where `docker-compose.yml` is), run the script using `docker-compose run`:
                ```bash
                docker-compose run --rm --no-deps app bash /app/prepare_primary_db.sh
                ```
                *   `--rm`: Removes the temporary container after execution.
                *   `--no-deps`: Prevents starting linked services (like the standby DB itself).
                *   `app`: The service name defined in `docker-compose.yml` that has `psql` and the script.
            *   The script uses the `REPL_PASSWORD` from your `.env` file to connect.
            *   Review the script's output for any errors (e.g., connection refused, authentication failed).

        **Step 3: Manually Reload/Restart Primary PostgreSQL Server (on Primary Server)**
            *   **Crucial:** Changes to `pg_hba.conf` (Step 1) require the primary PostgreSQL server configuration to be reloaded or the server restarted. The script (Step 2) attempts `SELECT pg_reload_conf();`, but this **may not be sufficient** for `pg_hba.conf` changes or might fail due to permissions.
            *   You **must** ensure the configuration is reloaded on the primary server. Choose **one** of the following methods on the primary Mac:

                *   **Method A (Full Server Restart - Use if unsure):** If methods A or B don't work or you're unsure, a full restart of the Mac hosting the primary database will ensure the changes are applied, although it's less ideal.

                *   **Method B ** Quit and restart the **DaVinci Resolve Project Server** application. This usually restarts the underlying PostgreSQL server gracefully.

        **Step 4: Verify Primary Server is Running**
            *   After reloading/restarting, ensure your primary PostgreSQL server (and the DaVinci Resolve Project Server application, if used) is running and accessible before proceeding to start the Laterbase services.

3.  **Create Backup Directory:**
    *   In the same directory as the `docker-compose.yml` file on your Docker host, create the backups directory:
        ```bash
        mkdir backups
        ```

4.  **Rclone Configuration (Optional):**
    *   If you want to use the cloud upload feature:
        *   Create a directory named `rclone_config` in the same directory as `docker-compose.yml`:
            ```bash
            mkdir rclone_config
            ```
        *   Place your configured `rclone.conf` file inside the `./rclone_config/` directory. The backup container will mount this directory read-only at `/config/rclone/rclone.conf`. (Note: path inside container updated)
        *   Ensure the remote name you use in `rclone.conf` matches the `RCLONE_REMOTE_NAME` set in your `.env` file.
        *   **Security Note:** The `rclone.conf` file contains sensitive credentials. Ensure appropriate file permissions are set on the host machine (`chmod 600 ./rclone_config/rclone.conf`).

## Usage

1.  **Build and Start Containers:**
    *   Navigate to the project directory in your terminal.
    *   Run:
        ```bash
        docker-compose up --build -d
        ```
2.  **Access pgAdmin:**
    *   Open a web browser and go to `http://<your-docker-host-ip>:5050` (or `http://localhost:5050` if running Docker locally).
    *   Log in using the email and password you configured in the `.env` file.
3.  **Connect Servers in pgAdmin:**
    *   Add a server connection for your **Primary** database (`PRIMARY_HOST`:5432). Use the user/password defined in `.env`.
    *   Add a server connection for your **Standby** database. Use these settings:
        *   **Host name/address:** `laterbase-standby` (the service name)
        *   **Port:** `5432` (the internal port)
        *   **Username:** `postgres` (or `PRIMARY_USER` from `.env`)
        *   **Password:** Use the *primary* server's password (likely `REPL_PASSWORD` from `.env`).
4.  **Monitor:**
    *   Use pgAdmin to monitor server status and replication lag (see pgAdmin documentation or previous conversation notes for specific queries like `pg_stat_replication`).
    *   Check the `./backups` directory on the host for hourly `.sql.gz` backup files.
    *   Check container logs using `docker logs laterbase-standby` and `docker logs laterbase-backup-agent`.
5.  **Stop Containers:**
    *   Run:
        ```bash
        docker-compose down
        ```

## Files

*   `docker-compose.yml`: Defines the three services (`laterbase-standby`, `laterbase-backup-agent`, `laterbase-pgadmin`), their configurations, volumes, and network.
*   `app/Dockerfile`: Instructions to build the PostgreSQL standby server image (based on `postgres:15`).
*   `backup/Dockerfile.backup`: Instructions to build the backup agent image (based on Debian, includes `cron`, `rclone`, and `postgresql-client`).
*   `.env`: Configuration file for environment variables (database credentials, pgAdmin login, etc.). **Requires user configuration.**
*   `app/prepare_primary_db.sh`: **(New)** Script to automate granting replication role and creating the replication slot on the primary server via `psql`. Run manually before starting services.
*   `app/setup_standby.sh`: Script run inside the standby container on first start to perform the initial base backup and configure replication.
*   `backup/backup.sh`: Script run by cron inside the backup agent container to perform hourly `pg_dump` backups, optionally upload via rclone, and manage retention.
*   `backup/entrypoint.sh`: Entrypoint for backup container, sets up cron.
*   `backup/crontab.txt`: Defines the cron schedule for `backup.sh`.
*   `./backups/` (Directory to be created): Host directory where local backup files (`.sql.gz`) will be stored by the backup agent.
*   `./rclone_config/` (Directory to be created, optional): Host directory containing the `rclone.conf` file for cloud uploads.
