#!/bin/bash
set -e # Exit on error

# This script now simply executes the command passed to the container.
# The default command in the Dockerfile starts the Duplicati server.
# Example: CMD ["duplicati-server", "--webservice-port=8200", ...]

echo "Executing command: $@"
exec "$@"