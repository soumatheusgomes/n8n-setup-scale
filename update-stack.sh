#!/usr/bin/env bash

set -euo pipefail
STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

MODES=(cloud-remote cloud-local local-remote local-local)

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
# Ask whether to include browserless
#######################################
INCLUDE_BROWSERLESS="false"
read -rp "Do you want to include the Browserless container? (y/N): " INCLUDE_BROWSERLESS_ANSWER
case "$INCLUDE_BROWSERLESS_ANSWER" in
  [yY][eE][sS]|[yY]) INCLUDE_BROWSERLESS="true" ;;
  *) INCLUDE_BROWSERLESS="false" ;;
esac

#######################################
# Compose profile and override mapping
#######################################
PROFILE_TLS=""; PROFILE_DB=""; EXTRA_FILE=""
case "$MODE" in
  cloud-remote)  PROFILE_TLS="--profile tls" ;;
  cloud-local)   PROFILE_TLS="--profile tls"; PROFILE_DB="--profile dblocal" ;;
  local-remote)  EXTRA_FILE="-f docker-compose.local.yml" ;;
  local-local)   PROFILE_DB="--profile dblocal"; EXTRA_FILE="-f docker-compose.local.yml" ;;
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

# Remove browserless manually if not included
if [[ "$INCLUDE_BROWSERLESS" != "true" ]]; then
  echo ">> Cleaning up browserless container if exists..."
  docker ps -a --filter "name=browserless" --format "{{.ID}}" | xargs -r docker rm -f
fi
