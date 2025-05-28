#!/usr/bin/env bash
# install.sh  –  Provisiona/atualiza a stack n8n + Traefik
# -------------------------------------------------------
# Uso:   ./install.sh <MODE> [WORKERS]
# MODE  : cloud-remote | cloud-docker | localhost-remote | localhost-docker
# WORKERS (opcional)  : nº de workers (default 4)

set -euo pipefail
STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

MODES=(cloud-remote cloud-docker localhost-remote localhost-docker)

MODE="${1:-}"
WORKERS="${2:-}"

if [[ -z "$MODE" ]]; then
  echo "Choose deploy mode: [Only numbers]"
  select MODE in "${MODES[@]}"; do
    [[ -n "$MODE" ]] && break
    echo "Invalid option."
  done
fi

if [[ ! " ${MODES[*]} " =~ " $MODE " ]]; then
  echo "Invalid mode. Options: ${MODES[*]}"
  exit 1
fi

if [[ -z "$WORKERS" ]]; then
  read -rp "Number of workers? [Default 4]: " WORKERS
  WORKERS="${WORKERS:-4}"
fi
if ! [[ "$WORKERS" =~ ^[0-9]+$ ]]; then
  echo "Invalid number — using 4."
  WORKERS=4
fi

echo ">> Deploy mode : $MODE"
echo ">> Worker count: $WORKERS"

#######################################
# Ajusta WEBHOOK_URL dinamicamente
#######################################
ENV_FILE="$STACK_DIR/.env"
touch "$ENV_FILE"
sed -i '/^WEBHOOK_URL=/d' "$ENV_FILE"

# Captura N8N_PROTOCOL e N8N_HOST já definidos (com fallback)
N8N_PROTOCOL_VAL=$(grep -E '^N8N_PROTOCOL=' "$ENV_FILE" | cut -d= -f2-) || true
N8N_PROTOCOL_VAL=${N8N_PROTOCOL_VAL:-http}

N8N_HOST_VAL=$(grep -E '^N8N_HOST=' "$ENV_FILE" | cut -d= -f2-) || true
N8N_HOST_VAL=${N8N_HOST_VAL:-localhost}

if [[ "$MODE" == L* ]]; then
  echo "WEBHOOK_URL=${N8N_PROTOCOL_VAL}://localhost:5678" >> "$ENV_FILE"
  echo ">> WEBHOOK_URL definido (local): ${N8N_PROTOCOL_VAL}://localhost:5678"
else
  echo "WEBHOOK_URL=${N8N_PROTOCOL_VAL}://${N8N_HOST_VAL}" >> "$ENV_FILE"
  echo ">> WEBHOOK_URL definido (cloud): ${N8N_PROTOCOL_VAL}://${N8N_HOST_VAL}"
fi

#######################################
# Pergunta se inclui o Browserless
#######################################
INCLUDE_BROWSERLESS="false"
read -rp "Do you want to include the Browserless container? (y/N): " INCLUDE_BROWSERLESS_ANSWER
case "$INCLUDE_BROWSERLESS_ANSWER" in
  [yY][eE][sS]|[yY]) INCLUDE_BROWSERLESS="true" ;;
  *) INCLUDE_BROWSERLESS="false" ;;
esac

#######################################
# Compose profile e overrides
#######################################
PROFILE_TLS=""; PROFILE_DB=""; EXTRA_FILE=""
case "$MODE" in
  cloud-remote)  PROFILE_TLS="--profile tls" ;;
  cloud-docker)   PROFILE_TLS="--profile tls"; PROFILE_DB="--profile dblocal" ;;
  localhost-remote)  EXTRA_FILE="-f docker-compose.local.yml" ;;
  localhost-docker)   PROFILE_DB="--profile dblocal"; EXTRA_FILE="-f docker-compose.local.yml" ;;
esac

#######################################
# Deploy stack
#######################################
DC="docker compose $PROFILE_TLS $PROFILE_DB -f docker-compose.yml $EXTRA_FILE"
EXTRA_PROFILES=""
if [[ "$INCLUDE_BROWSERLESS" == "true" ]]; then
  EXTRA_PROFILES="--profile browserless"
fi

echo ">> Stopping previous containers..."
$DC down --remove-orphans

echo ">> Pulling latest images..."
$DC pull

echo ">> Rebuilding custom n8n image..."
$DC build --no-cache n8n n8n-worker

echo ">> Starting stack..."
$DC $EXTRA_PROFILES up -d --scale n8n-worker="$WORKERS" --remove-orphans

echo ">> Cleaning dangling images..."
docker image prune -f

echo "✅  Stack is up — $WORKERS worker(s) running."

# Remove browserless manual se não incluído
if [[ "$INCLUDE_BROWSERLESS" != "true" ]]; then
  echo ">> Cleaning up browserless container if exists..."
  docker ps -a --filter "name=browserless" --format "{{.ID}}" | xargs -r docker rm -f
fi