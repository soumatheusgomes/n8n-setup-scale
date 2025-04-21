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
#   • .env with Redis / Postgres variables pointing to the primary stack
#   • secrets/n8n_encryption_key.txt (identical to primary)
#   • secrets/redis_password.txt     (identical to primary)

set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

#########################################
# Config section
#########################################
DEFAULT_WORKERS=4
IMAGE_TAG=matheus/n8n-custom:latest

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
# 2) Validate secrets
#########################################
SECRET_DIR="secrets"
for f in n8n_encryption_key.txt redis_password.txt; do
  [[ -s $SECRET_DIR/$f ]] || { echo "Error: missing '$SECRET_DIR/$f'"; exit 1; }
done
chmod 600 "$SECRET_DIR"/*.txt

#########################################
# 3) Generate minimal compose (on the fly)
#########################################
cat > docker-compose.worker.yml <<YAML
version: "3.9"
services:
  n8n-worker:
    image: ${IMAGE_TAG}
    command: n8n worker
    environment:
      EXECUTIONS_MODE: queue
      QUEUE_BULL_REDIS_HOST: \${QUEUE_BULL_REDIS_HOST}
      QUEUE_BULL_REDIS_PORT: \${QUEUE_BULL_REDIS_PORT:-6379}
      QUEUE_BULL_REDIS_PASSWORD_FILE: /run/secrets/redis_password
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: \${POSTGRES_HOST}
      DB_POSTGRESDB_PORT: \${POSTGRES_PORT:-5432}
      DB_POSTGRESDB_DATABASE: \${POSTGRES_DB}
      DB_POSTGRESDB_USER: \${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: \${POSTGRES_PASSWORD}
      N8N_ENCRYPTION_KEY_FILE: /run/secrets/n8n_encryption_key
    secrets:
      - redis_password
      - n8n_encryption_key
    restart: unless-stopped

secrets:
  redis_password:
    file: ./secrets/redis_password.txt
  n8n_encryption_key:
    file: ./secrets/n8n_encryption_key.txt
YAML

#########################################
# 4) Deploy
#########################################
echo ">> Pulling worker image..."
docker compose -f docker-compose.worker.yml pull

echo ">> Starting ${WORKERS} worker(s)..."
docker compose -f docker-compose.worker.yml up -d --scale n8n-worker="${WORKERS}"

echo "✅  ${WORKERS} worker(s) running on this server."