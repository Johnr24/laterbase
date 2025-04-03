# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /app

# Install system dependencies:
# - postgresql-client: Provides psql, createdb, dropdb
# - gzip: Provides gunzip (often included, but good to be explicit)
# Clean up apt cache afterwards to keep image size down
RUN apt-get update && \
    apt-get install -y --no-install-recommends postgresql-client gzip && \
    rm -rf /var/lib/apt/lists/*

# Copy the requirements file into the container at /app
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container at /app
COPY . .

# Make port 5001 available to the world outside this container
EXPOSE 5001

# Define environment variables (can be overridden at runtime)
# Default target DB connection details (match app.py defaults)
# TARGET_DB_PASSWORD MUST be provided via docker-compose or .env

# Run app.py when the container launches
CMD ["python", "app.py"]