#!/usr/bin/env bash
#
# update-stack.sh — universal deployer with interactive menu
#
# Usage examples
# --------------
#  Interactive (menu + questions):
#     ./update-stack.sh
#  Non‑interactive:
#     ./update-stack.sh cloud-remote 6
#
# Deploy modes
# ------------
#   cloud-remote   → Traefik TLS + remote Postgres
#   cloud-local    → Traefik TLS + local Postgres container
#   local-remote   → HTTP only   + remote Postgres (port 5678)
#   local-local    → HTTP only   + local Postgres container
#
# Requirements: Docker Engine 20.10+, Compose v2, OpenSSL

set -euo pipefail
STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

#######################################
# 0) Mode and worker count
#######################################
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
# 1) Map profiles / overrides
#######################################
PROFILE_TLS=""; PROFILE_DB=""; EXTRA_FILE=""
case "$MODE" in
  cloud-remote)  PROFILE_TLS="--profile tls" ;;
  cloud-local)   PROFILE_TLS="--profile tls"; PROFILE_DB="--profile dblocal" ;;
  local-remote)  EXTRA_FILE="-f docker-compose.local.yml" ;;
  local-local)   PROFILE_DB="--profile dblocal"; EXTRA_FILE="-f docker-compose.local.yml" ;;
esac

#######################################
# 2.5) Ensure external network exists
#######################################
if docker compose config | grep -q 'external: true'; then
  if ! docker network inspect proxy >/dev/null 2>&1; then
    echo ">> Creating external network 'proxy'..."
    docker network create proxy
  else
    echo ">> External network 'proxy' already exists."
  fi
fi

#######################################
# 3) Deploy stack
#######################################
DC="docker compose $PROFILE_TLS $PROFILE_DB -f docker-compose.yml $EXTRA_FILE"

echo ">> Stopping previous containers..."
$DC down

echo ">> Pulling latest images..."
$DC pull

echo ">> Rebuilding custom n8n image..."
$DC build --no-cache n8n n8n-worker

echo ">> Starting stack..."
$DC up -d --scale n8n-worker="$WORKERS"

echo ">> Cleaning dangling images..."
docker image prune -f

echo "✅  Stack is up — $WORKERS worker(s) running."
