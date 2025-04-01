# Use an official PostgreSQL 13 image
FROM postgres:15

# Set environment variables (adjust PGUSER if Resolve uses a different default admin user)
# We'll pass the password via docker-compose for better security than hardcoding
# POSTGRES_USER, POSTGRES_DB, and PGDATA will be set via environment variables
# in docker-compose.yml, sourced from the .env file.
# The base postgres image will use these variables at runtime.

# Copy the setup script into the container
COPY setup_standby.sh /docker-entrypoint-initdb.d/setup_standby.sh
RUN chmod +x /docker-entrypoint-initdb.d/setup_standby.sh

# Expose the PostgreSQL port
EXPOSE 5432

# The default entrypoint will start PostgreSQL after running init scripts