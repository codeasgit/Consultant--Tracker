#!/usr/bin/env bash
# Idempotent deploy helper to be executed on the Azure VM from the workflow
# Assumes:
#  - docker & docker-compose (or docker compose) are installed
#  - working directory is the deploy path where docker-compose.prod.yml is present
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")/../" && pwd)"
echo "Running deploy script in $DEPLOY_DIR"
cd "$DEPLOY_DIR"

# If docker-compose CLI exists use it, otherwise use `docker compose`
if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
elif docker compose version >/dev/null 2>&1; then
  DC="docker compose"
else
  echo "docker-compose (or docker compose) not found. Please install Docker and Docker Compose."
  exit 1
fi

# Stop previous containers gracefully (if any)
echo "Stopping any existing containers (if running)"
$DC -f docker-compose.prod.yml down || true

# Recreate images & containers
echo "Starting services using docker-compose.prod.yml"
$DC -f docker-compose.prod.yml pull || true
$DC -f docker-compose.prod.yml up -d --build

# Optional: cleanup dangling images
echo "Pruning dangling images (safe)"
docker image prune -f || true

echo "Deploy script completed successfully"
