#!/usr/bin/env bash
#
# deploy-workers-only.sh
#
# Spin up **ONLY** n8n‑workers on a secondary server.
# Workers connect to the Redis and Postgres of the primary server.
#
# Usage
# -----
#   Interactive (prompts for worker count):
#       ./deploy-workers-only.sh
#   Non‑interactive (e.g., 8 workers):
#       ./deploy-workers-only.sh 8
#
# Prerequisites on this server
# ----------------------------
#   • .env with Redis / Postgres variables pointing to the main server
#   • Local Dockerfile present in the same folder
#   • N8N_ENCRYPTION_KEY identical to the main server

set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

#########################################
# Config section
#########################################
DEFAULT_WORKERS=4

#########################################
# 1) Worker count
#########################################
WORKERS="${1:-}"
if [[ -z "$WORKERS" ]]; then
  read -rp "Workers to start? [${DEFAULT_WORKERS}]: " WORKERS
  WORKERS="${WORKERS:-$DEFAULT_WORKERS}"
fi
if ! [[ "$WORKERS" =~ ^[0-9]+$ ]]; then
  echo "Invalid input — using ${DEFAULT_WORKERS}."
  WORKERS=$DEFAULT_WORKERS
fi
echo ">> Workers to deploy: $WORKERS"

#########################################
# 2) Validate .env variables
#########################################
REQUIRED_VARS=(
  N8N_ENCRYPTION_KEY
  POSTGRES_HOST
  POSTGRES_PORT
  POSTGRES_DB
  POSTGRES_USER
  POSTGRES_PASSWORD
  QUEUE_BULL_REDIS_HOST
  QUEUE_BULL_REDIS_PORT
  REDIS_PASSWORD
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: missing environment variable '$var'"
    exit 1
  fi
done

#########################################
# 3) Generate minimal compose (on the fly)
#########################################
cat > docker-compose.worker.yml <<'YAML'
services:
  n8n-worker:
    image: n8nio/n8n:latest
    command: worker
    environment:
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: ${QUEUE_BULL_REDIS_HOST}
      QUEUE_BULL_REDIS_PORT: ${QUEUE_BULL_REDIS_PORT:-6379}
      QUEUE_BULL_REDIS_PASSWORD: ${REDIS_PASSWORD}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: ${POSTGRES_HOST}
      DB_POSTGRESDB_PORT: ${POSTGRES_PORT:-5432}
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: "true"
      OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS: "true"
    restart: unless-stopped
YAML

#########################################
# 4) Deploy
#########################################
echo ">> Building worker image..."
docker compose -f docker-compose.worker.yml build

echo ">> Starting ${WORKERS} worker(s)..."
docker compose -f docker-compose.worker.yml up -d --scale n8n-worker="${WORKERS}"

echo "✅  ${WORKERS} worker(s) running on this server."
